#!/usr/bin/env bash
set -euo pipefail

server="${1:?server required}"
database="${2:?database required}"
user="${3:?user required}"
parallel_calls="${4:-20}"
sqlcmd_bin="${SQLCMD_BIN:-sqlcmd}"

if [[ -z "${SQLCMDPASSWORD:-}" ]]; then
  echo "Set SQLCMDPASSWORD in the environment; do not pass it on the command line." >&2
  exit 2
fi

root="stkc$RANDOM"
setup="$($sqlcmd_bin -S "$server" -d "$database" -U "$user" -C -b -h -1 -W -s "," -Q "
SET NOCOUNT ON;
DECLARE @now datetime = GETUTCDATE(), @u int, @q int;
INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
VALUES (N'$root commenter', @now, @now, 1, 0, 0, 0);
SET @u = CONVERT(int, SCOPE_IDENTITY());
INSERT dbo.Posts (Body, Title, Tags, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount)
VALUES (N'$root body', N'$root title', N'<sql-server>', 1, @u, @now, @now, 0, 0, 0, 0, 0);
SET @q = CONVERT(int, SCOPE_IDENTITY());
SELECT @u, @q;
")"
IFS="," read -r actor post <<< "$setup"

cleanup() {
  "$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "
DELETE FROM dbo.Comments WHERE PostId = $post;
DELETE FROM dbo.Posts WHERE Id = $post;
DELETE FROM dbo.Users WHERE Id = $actor;" >/dev/null || true
}
trap cleanup EXIT

for i in $(seq 1 "$parallel_calls"); do
  "$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "EXEC dbo.Stackish_AddComment $post, $actor, N'$root comment $i';" >/dev/null &
done
wait

"$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "
DECLARE @stored int = (SELECT CommentCount FROM dbo.Posts WHERE Id = $post);
DECLARE @actual int = (SELECT COUNT(*) FROM dbo.Comments WHERE PostId = $post);
IF NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = $post AND CommentCount = $parallel_calls)
    THROW 51480, 'Concurrent AddComment lost CommentCount increments.', 1;
IF @actual <> $parallel_calls
BEGIN
    DECLARE @msg nvarchar(2048) = CONCAT(N'Concurrent AddComment inserted ', @actual, N' comments while stored counter is ', @stored, N'.');
    THROW 51481, @msg, 1;
END;
IF @stored <> @actual
    THROW 51481, 'Concurrent AddComment inserted the wrong number of comments.', 1;
PRINT 'Component 04 concurrent comment check passed.';
"

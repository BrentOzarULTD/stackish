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

root="stka$RANDOM"
setup="$($sqlcmd_bin -S "$server" -d "$database" -U "$user" -C -b -h -1 -W -s "," -Q "
SET NOCOUNT ON;
DECLARE @now datetime = GETUTCDATE(), @owner int, @answerer int, @q int;
INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
VALUES (N'$root owner', @now, @now, 1, 0, 0, 0), (N'$root answerer', @now, @now, 1, 0, 0, 0);
SET @answerer = CONVERT(int, SCOPE_IDENTITY());
SET @owner = @answerer - 1;
INSERT dbo.Posts (Body, Title, Tags, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount)
VALUES (N'$root body', N'$root title', N'<sql-server>', 1, @owner, @now, @now, 0, 0, 0, 0, 0);
SET @q = CONVERT(int, SCOPE_IDENTITY());
SELECT @owner, @answerer, @q;
")"
IFS="," read -r owner answerer question <<< "$setup"

cleanup() {
  "$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "
DELETE FROM dbo.PostHistory WHERE PostId IN (SELECT Id FROM dbo.Posts WHERE ParentId = $question OR Id = $question);
DELETE FROM dbo.Posts WHERE ParentId = $question OR Id = $question;
DELETE FROM dbo.Users WHERE Id IN ($owner, $answerer);" >/dev/null || true
}
trap cleanup EXIT

for i in $(seq 1 "$parallel_calls"); do
  "$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "EXEC dbo.Stackish_CreateAnswer $question, $answerer, N'$root answer $i';" >/dev/null &
done
wait

"$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "
IF NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = $question AND AnswerCount = $parallel_calls)
    THROW 51380, 'Concurrent CreateAnswer lost AnswerCount increments.', 1;
IF (SELECT COUNT(*) FROM dbo.Posts WHERE ParentId = $question AND PostTypeId = 2) <> $parallel_calls
    THROW 51381, 'Concurrent CreateAnswer inserted the wrong number of answers.', 1;
PRINT 'Component 03 concurrent answer check passed.';
"

answer="$($sqlcmd_bin -S "$server" -d "$database" -U "$user" -C -b -h -1 -W -Q "SET NOCOUNT ON; SELECT TOP (1) Id FROM dbo.Posts WHERE ParentId = $question AND PostTypeId = 2 ORDER BY Id;")"

for i in $(seq 1 "$parallel_calls"); do
  "$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "EXEC dbo.Stackish_EditAnswer $answer, $answerer, N'$root edited $i';" >/dev/null &
  "$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "EXEC dbo.Stackish_SetAcceptedAnswer $question, $owner, $answer;" >/dev/null &
  "$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "EXEC dbo.Stackish_SetAcceptedAnswer $question, $owner, NULL;" >/dev/null &
done
wait

"$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "
IF NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = $answer AND Body LIKE N'$root edited%')
    THROW 51382, 'Concurrent EditAnswer did not leave the answer editable.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = $question AND AnswerCount = $parallel_calls)
    THROW 51383, 'Concurrent acceptance changed AnswerCount.', 1;
IF EXISTS (SELECT 1 FROM dbo.Users WHERE Id IN ($owner, $answerer) AND Reputation <> 1)
    THROW 51384, 'Concurrent acceptance changed reputation.', 1;
PRINT 'Component 03 concurrent edit/accept check passed.';
"

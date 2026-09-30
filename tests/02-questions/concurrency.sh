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

root="stkq$RANDOM"
setup="$($sqlcmd_bin -S "$server" -d "$database" -U "$user" -C -b -h -1 -W -s "," -Q "
SET NOCOUNT ON;
DECLARE @now datetime = GETUTCDATE(), @u int, @q int;
DECLARE @w TABLE (Outcome varchar(20), EntityId int);
DECLARE @tagA nvarchar(150)=N'$root-a', @tagB nvarchar(150)=N'$root-b', @tagC nvarchar(150)=N'$root-c';
INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
VALUES (N'$root user', @now, @now, 1, 0, 0, 0);
SET @u = CONVERT(int, SCOPE_IDENTITY());
INSERT dbo.Tags (TagName, [Count], ExcerptPostId, WikiPostId) VALUES (@tagA, 0, 0, 0), (@tagB, 0, 0, 0), (@tagC, 0, 0, 0);
INSERT @w EXEC dbo.Stackish_CreateQuestion @u, N'$root title', N'$root body', N'<$root-a><$root-b>';
SELECT @q = EntityId FROM @w WHERE Outcome = 'Applied';
SELECT @u, @q;
")"
IFS="," read -r actor question <<< "$setup"

cleanup() {
  "$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "
DELETE FROM dbo.PostHistory WHERE PostId IN (SELECT Id FROM dbo.Posts WHERE OwnerUserId = $actor OR Id = $question);
DELETE FROM dbo.Posts WHERE OwnerUserId = $actor OR Id = $question;
DELETE FROM dbo.Tags WHERE TagName LIKE N'$root%';
DELETE FROM dbo.Users WHERE Id = $actor;" >/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 "$parallel_calls"); do
  "$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "EXEC dbo.Stackish_RecordQuestionView $question;" >/dev/null &
done
wait

"$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "
IF NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = $question AND ViewCount = $parallel_calls)
    THROW 51280, 'Concurrent RecordQuestionView lost increments.', 1;
PRINT 'Component 02 concurrent view check passed.';
"

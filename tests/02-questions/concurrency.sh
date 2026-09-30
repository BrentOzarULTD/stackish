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

wait_for_jobs() {
  local status=0
  local pid
  for pid in "$@"; do
    if ! wait "$pid"; then
      status=1
    fi
  done
  return "$status"
}

root="stkq$RANDOM"
setup="$($sqlcmd_bin -S "$server" -d "$database" -U "$user" -C -b -h -1 -W -s "," -Q "
SET NOCOUNT ON;
DECLARE @now datetime = GETUTCDATE(), @u int, @q int, @q1 int, @q2 int;
DECLARE @w TABLE (Outcome varchar(20), EntityId int);
DECLARE @tagA nvarchar(150)=N'$root-a', @tagB nvarchar(150)=N'$root-b', @tagC nvarchar(150)=N'$root-c';
INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
VALUES (N'$root user', @now, @now, 1, 0, 0, 0);
SET @u = CONVERT(int, SCOPE_IDENTITY());
INSERT dbo.Tags (TagName, [Count], ExcerptPostId, WikiPostId) VALUES (@tagA, 0, 0, 0), (@tagB, 0, 0, 0), (@tagC, 0, 0, 0);
INSERT @w EXEC dbo.Stackish_CreateQuestion @u, N'$root view title', N'$root view body', N'<$root-c>';
SELECT @q = EntityId FROM @w WHERE Outcome = 'Applied';
DELETE @w; INSERT @w EXEC dbo.Stackish_CreateQuestion @u, N'$root retag one', N'$root retag body one', N'<$root-a>';
SELECT @q1 = EntityId FROM @w WHERE Outcome = 'Applied';
DELETE @w; INSERT @w EXEC dbo.Stackish_CreateQuestion @u, N'$root retag two', N'$root retag body two', N'<$root-b>';
SELECT @q2 = EntityId FROM @w WHERE Outcome = 'Applied';
SELECT @u, @q, @q1, @q2;
")"
IFS="," read -r actor question retag_one retag_two <<< "$setup"

cleanup() {
  "$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "
DELETE FROM dbo.PostHistory WHERE PostId IN (SELECT Id FROM dbo.Posts WHERE OwnerUserId = $actor OR Id = $question);
DELETE FROM dbo.Posts WHERE OwnerUserId = $actor OR Id = $question;
DELETE FROM dbo.Tags WHERE TagName LIKE N'$root%';
DELETE FROM dbo.Users WHERE Id = $actor;" >/dev/null || true
}
trap cleanup EXIT

pids=()
for _ in $(seq 1 "$parallel_calls"); do
  "$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "EXEC dbo.Stackish_RecordQuestionView $question;" >/dev/null &
  pids+=("$!")
done
wait_for_jobs "${pids[@]}"

"$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "
IF NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = $question AND ViewCount = $parallel_calls)
    THROW 51280, 'Concurrent RecordQuestionView lost increments.', 1;
PRINT 'Component 02 concurrent view check passed.';
"

pids=()
for _ in $(seq 1 "$parallel_calls"); do
  "$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "EXEC dbo.Stackish_RetagQuestion $retag_one, $actor, N'<$root-b>';" >/dev/null &
  pids+=("$!")
  "$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "EXEC dbo.Stackish_RetagQuestion $retag_two, $actor, N'<$root-a>';" >/dev/null &
  pids+=("$!")
done
wait_for_jobs "${pids[@]}"

"$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b -Q "
IF NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = $retag_one AND Tags = N'<$root-b>')
    THROW 51281, 'Concurrent RetagQuestion left the first question with the wrong tags.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = $retag_two AND Tags = N'<$root-a>')
    THROW 51282, 'Concurrent RetagQuestion left the second question with the wrong tags.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Tags WHERE TagName = N'$root-a' AND [Count] = 1)
    THROW 51283, 'Concurrent RetagQuestion left the first tag count wrong.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Tags WHERE TagName = N'$root-b' AND [Count] = 1)
    THROW 51284, 'Concurrent RetagQuestion left the second tag count wrong.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Tags WHERE TagName = N'$root-c' AND [Count] = 1)
    THROW 51285, 'Concurrent RetagQuestion changed an unrelated tag count.', 1;
PRINT 'Component 02 concurrent retag check passed.';
"

#!/usr/bin/env bash
# Component 05 concurrency and rollback checks. COMMITS fixture rows, then deletes them on exit.
# Usage: SQLCMDPASSWORD=... tests/05-votes/concurrency.sh <server> <database> <user> [parallel_calls]
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

sq() { "$sqlcmd_bin" -S "$server" -d "$database" -U "$user" -C -b "$@"; }

work="$(mktemp -d)"
root="stkv$RANDOM"
owner="" voter="" question="" voters=""

cleanup() {
  # Runs on every exit, including failed workers or failed assertions. Workers are waited on
  # before any assertion, so nothing is still writing when this runs.
  # Only rows this run created: fixture IDs, never a name pattern, and never orphan dump rows.
  if [[ -n "$question" ]]; then
    sq -Q "
DELETE FROM dbo.Votes WHERE PostId = $question AND (UserId IN ($owner, $voter) ${voters:+OR UserId IN ($voters)});
DELETE FROM dbo.Posts WHERE Id = $question;
DELETE FROM dbo.Users WHERE Id IN ($owner, $voter${voters:+, $voters});" >/dev/null || echo "cleanup failed for $root" >&2
  fi
  rm -rf "$work"
}
trap cleanup EXIT

setup="$(sq -h -1 -W -s "," -Q "
SET NOCOUNT ON;
DECLARE @now datetime = GETUTCDATE(), @owner int, @voter int, @q int;
INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
VALUES (N'$root owner', @now, @now, 1, 0, 0, 0);
SET @owner = CONVERT(int, SCOPE_IDENTITY());
INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
VALUES (N'$root voter', @now, @now, 1, 0, 0, 0);
SET @voter = CONVERT(int, SCOPE_IDENTITY());
INSERT dbo.Posts (Body, Title, Tags, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount)
VALUES (N'$root body', N'$root title', N'<sql-server>', 1, @owner, @now, @now, 0, 0, 0, 0, 0);
SET @q = CONVERT(int, SCOPE_IDENTITY());
SELECT @owner, @voter, @q;
")"
IFS="," read -r owner voter question <<< "$setup"
[[ "$question" =~ ^[0-9]+$ ]] || { echo "fixture setup failed: $setup" >&2; exit 1; }

# The dump holds orphan votes above the current identity values; measure against a baseline
# instead of assuming a fresh post has no vote rows.
base_rows="$(sq -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.Votes WHERE PostId = $question;")"
attributed="$(sq -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.Votes WHERE PostId = $question AND UserId = $voter;")"
if [[ "$attributed" != "0" ]]; then echo "fixture collided with orphan votes by $voter; rerun" >&2; exit 1; fi

# Run N copies of a statement in separate sessions. Each worker writes its outcome (or its error)
# to its own file; a worker failure is recorded, not ignored.
# If a gate row is given, a separate session holds an X lock on that Users row while the workers
# start, so they pile up and are released together. That widens the check-then-insert window
# enough for the harness to catch a missing lock (verified against an UPDLOCK-less build).
race() {
  local label="$1" statement="$2" gate="${3:-}" i pids=() gate_pid=""
  rm -f "$work/$label".*
  if [[ -n "$gate" ]]; then
    sq -Q "BEGIN TRANSACTION; UPDATE dbo.Users SET Views = Views WHERE Id = $gate; WAITFOR DELAY '00:00:03'; COMMIT;" >/dev/null &
    gate_pid="$!"
    sleep 0.5
  fi
  for i in $(seq 1 "$parallel_calls"); do
    ( sq -h -1 -W -s "," -Q "SET NOCOUNT ON; $statement" > "$work/$label.$i.out" 2>&1 || echo "WORKER_FAILED" >> "$work/$label.$i.out" ) &
    pids+=("$!")
  done
  for i in "${pids[@]}"; do wait "$i"; done
  if [[ -n "$gate_pid" ]]; then wait "$gate_pid"; fi
}
count_outcome() { cat "$work/$1".*.out | grep -c "^$2," || true; }
failures() { cat "$work/$1".*.out | grep -c "WORKER_FAILED" || true; }
expect() { # label applied nochange
  local a n f
  a="$(count_outcome "$1" Applied)"; n="$(count_outcome "$1" "$3")"; f="$(failures "$1")"
  if [[ "$f" != "0" || "$a" != "$2" || $((a + n)) -ne "$parallel_calls" ]]; then
    echo "$1: expected $2 Applied and the rest $3, got Applied=$a $3=$n failed=$f" >&2
    cat "$work/$1".*.out | sort | uniq -c >&2
    exit 1
  fi
}

race up "EXEC dbo.Stackish_UpvoteQuestion $question, $voter;" "$voter"
expect up 1 NoChange
sq -Q "
SET NOCOUNT ON;
IF (SELECT COUNT(*) FROM dbo.Votes WHERE PostId = $question AND UserId = $voter AND VoteTypeId = 2) <> 1
   OR (SELECT COUNT(*) FROM dbo.Votes WHERE PostId = $question) <> $base_rows + 1
    THROW 51580, 'Identical concurrent upvotes inserted the wrong number of rows.', 1;
IF (SELECT Score FROM dbo.Posts WHERE Id = $question) IS DISTINCT FROM 1
   OR (SELECT Reputation FROM dbo.Users WHERE Id = $owner) IS DISTINCT FROM 11
   OR (SELECT UpVotes FROM dbo.Users WHERE Id = $voter) IS DISTINCT FROM 1
    THROW 51581, 'Identical concurrent upvotes applied the wrong deltas.', 1;
PRINT 'Identical concurrent upvotes: one Applied, one row, one delta.';"

race down "EXEC dbo.Stackish_DownvoteQuestion $question, $voter;"
expect down 0 Conflict

race remove "EXEC dbo.Stackish_RemovePostVote $question, $voter;" "$voter"
expect remove 1 NoChange
sq -Q "
SET NOCOUNT ON;
IF EXISTS (SELECT 1 FROM dbo.Votes WHERE PostId = $question AND UserId = $voter)
   OR (SELECT COUNT(*) FROM dbo.Votes WHERE PostId = $question) <> $base_rows
    THROW 51582, 'Concurrent removals left the wrong rows.', 1;
IF (SELECT Score FROM dbo.Posts WHERE Id = $question) IS DISTINCT FROM 0
   OR (SELECT Reputation FROM dbo.Users WHERE Id = $owner) IS DISTINCT FROM 1
   OR (SELECT UpVotes FROM dbo.Users WHERE Id = $voter) IS DISTINCT FROM 0
    THROW 51583, 'Concurrent removals reversed the wrong deltas.', 1;
PRINT 'Identical concurrent removals: one Applied, deltas reversed once.';"

# Many different voters at once: no lost score or reputation updates.
# Use exactly the IDs this insert produced; concurrent inserts elsewhere can interleave identity values.
voters="$(sq -h -1 -W -Q "
SET NOCOUNT ON;
DECLARE @now datetime = GETUTCDATE();
DECLARE @ids TABLE (Id int);
INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
OUTPUT inserted.Id INTO @ids
SELECT CONCAT(N'$root many ', value), @now, @now, 1, 0, 0, 0 FROM GENERATE_SERIES(1, $parallel_calls);
SELECT STRING_AGG(CONVERT(varchar(max), Id), ',') FROM @ids;")" || true
[[ "$voters" =~ ^[0-9]+(,[0-9]+)*$ ]] || { echo "voter setup failed: $voters" >&2; voters=""; exit 1; }
if [[ "$(sq -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.Votes WHERE PostId = $question AND UserId IN ($voters);")" != "0" ]]; then
  echo "fixture voters collided with orphan votes; rerun" >&2; exit 1
fi
pids=()
IFS="," read -ra voter_ids <<< "$voters"
for id in "${voter_ids[@]}"; do
  ( sq -h -1 -W -s "," -Q "SET NOCOUNT ON; EXEC dbo.Stackish_UpvoteQuestion $question, $id;" > "$work/many.$id.out" 2>&1 || echo "WORKER_FAILED" >> "$work/many.$id.out" ) &
  pids+=("$!")
done
for p in "${pids[@]}"; do wait "$p"; done
expect many "$parallel_calls" NoChange
sq -Q "
SET NOCOUNT ON;
IF (SELECT Score FROM dbo.Posts WHERE Id = $question) IS DISTINCT FROM $parallel_calls
   OR (SELECT Reputation FROM dbo.Users WHERE Id = $owner) IS DISTINCT FROM 1 + 10 * $parallel_calls
   OR (SELECT COUNT(*) FROM dbo.Users WHERE Id IN ($voters) AND UpVotes = 1) <> $parallel_calls
    THROW 51584, 'Concurrent votes by different users lost updates.', 1;
PRINT 'Concurrent votes by different users: no lost score/reputation/counter updates.';"

# Unexpected failure after the vote row and score are written: owner reputation overflows int.
# The call must raise and leave no vote row and no score/counter change.
sq -Q "UPDATE dbo.Users SET Reputation = 2147483647 WHERE Id = $owner;" >/dev/null
before_score="$(sq -h -1 -W -Q "SET NOCOUNT ON; SELECT Score FROM dbo.Posts WHERE Id = $question;")"
if sq -Q "EXEC dbo.Stackish_UpvoteQuestion $question, $voter;" > "$work/overflow.out" 2>&1; then
  echo "Overflowing reputation should have raised an error." >&2; exit 1
fi
grep -q "Msg 8115" "$work/overflow.out" || { echo "Expected arithmetic overflow:" >&2; cat "$work/overflow.out" >&2; exit 1; }
sq -Q "
SET NOCOUNT ON;
IF EXISTS (SELECT 1 FROM dbo.Votes WHERE PostId = $question AND UserId = $voter)
   OR (SELECT Score FROM dbo.Posts WHERE Id = $question) IS DISTINCT FROM $before_score
   OR (SELECT UpVotes FROM dbo.Users WHERE Id = $voter) IS DISTINCT FROM 0
   OR (SELECT Reputation FROM dbo.Users WHERE Id = $owner) IS DISTINCT FROM 2147483647
    THROW 51585, 'A failed vote left partial changes.', 1;
PRINT 'Failed vote rolled back completely.';"

# Same failure inside a caller transaction: the procedure rolls back the caller's work too and
# does not leave a transaction open.
sq -Q "
SET NOCOUNT ON;
BEGIN TRANSACTION;
UPDATE dbo.Posts SET ViewCount = ViewCount + 1000 WHERE Id = $question;
BEGIN TRY
    EXEC dbo.Stackish_UpvoteQuestion $question, $voter;
END TRY
BEGIN CATCH
END CATCH;
IF @@TRANCOUNT <> 0 THROW 51586, 'A failed vote left the caller transaction open.', 1;
IF (SELECT ViewCount FROM dbo.Posts WHERE Id = $question) IS DISTINCT FROM 0
    THROW 51587, 'Caller work survived a failed vote rollback.', 1;
PRINT 'Failed vote inside a caller transaction rolled back the whole transaction.';"

echo "Component 05 concurrency checks passed."

#!/usr/bin/env bash
# Component 09 concurrency and rollback checks. COMMITS fixture rows, then deletes them on exit.
# Needs component 03 (CreateAnswer) deployed for the close/answer race.
# Usage: SQLCMDPASSWORD=... tests/09-moderation/concurrency.sh <server> <database> <user> [parallel_calls]
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
scalar() { sq -h -1 -W -Q "SET NOCOUNT ON; $1"; }

work="$(mktemp -d)"
root="stkm$RANDOM"
actor="" q1="" q2="" link_base="" history_base=""

cleanup() {
  # Runs on every exit, including failed workers or assertions; workers are always waited on
  # before assertions run. Deletes only rows created by this run (by ID), never orphan dump rows.
  if [[ -n "$q2" ]]; then
    sq -Q "
DELETE FROM dbo.PostLinks WHERE Id > $link_base AND PostId IN ($q1, $q2);
DELETE FROM dbo.PostHistory WHERE Id > $history_base AND PostId IN (SELECT Id FROM dbo.Posts WHERE Id IN ($q1, $q2) OR (ParentId IN ($q1, $q2) AND Id > $q1));
DELETE FROM dbo.Posts WHERE ParentId IN ($q1, $q2) AND Id > $q1;
DELETE FROM dbo.Posts WHERE Id IN ($q1, $q2);
DELETE FROM dbo.Users WHERE Id = $actor;" >/dev/null || echo "cleanup failed for $root" >&2
  fi
  rm -rf "$work"
}
trap cleanup EXIT

link_base="$(scalar "SELECT ISNULL(MAX(Id), 0) FROM dbo.PostLinks;")"
history_base="$(scalar "SELECT ISNULL(MAX(Id), 0) FROM dbo.PostHistory;")"
setup="$(sq -h -1 -W -s "," -Q "
SET NOCOUNT ON;
DECLARE @now datetime = GETUTCDATE(), @u int, @q1 int, @q2 int;
INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
VALUES (N'$root actor', @now, @now, 1, 0, 0, 0);
SET @u = CONVERT(int, SCOPE_IDENTITY());
INSERT dbo.Posts (Body, Title, Tags, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount)
VALUES (N'$root body 1', N'$root title 1', N'<sql-server>', 1, @u, @now, @now, 0, 0, 0, 0, 0);
SET @q1 = CONVERT(int, SCOPE_IDENTITY());
INSERT dbo.Posts (Body, Title, Tags, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount)
VALUES (N'$root body 2', N'$root title 2', N'<sql-server>', 1, @u, @now, @now, 0, 0, 0, 0, 0);
SET @q2 = CONVERT(int, SCOPE_IDENTITY());
SELECT @u, @q1, @q2;
")"
IFS="," read -r actor q1 q2 <<< "$setup"
[[ "$q2" =~ ^[0-9]+$ ]] || { echo "fixture setup failed: $setup" >&2; exit 1; }
if [[ "$(scalar "SELECT COUNT(*) FROM dbo.PostLinks WHERE PostId = $q1 AND RelatedPostId = $q2;")" != "0" ]]; then
  echo "fixture IDs collided with orphan PostLinks rows; rerun" >&2; exit 1
fi

# A gate session X-locks one row (Users or Posts) while workers start, so they queue and are
# released together instead of trickling in one process launch at a time.
gate_start() { # table id seconds
  sq -Q "BEGIN TRANSACTION; UPDATE dbo.$1 SET $( [[ $1 == Users ]] && echo Views=Views || echo ViewCount=ViewCount ) WHERE Id = $2; WAITFOR DELAY '00:00:0$3'; COMMIT;" >/dev/null &
  gate_pid="$!"
  sleep 0.5
}
launch() { # label index statement
  ( sq -h -1 -W -s "," -Q "SET NOCOUNT ON; $3" > "$work/$1.$2.out" 2>&1 || echo "WORKER_FAILED" >> "$work/$1.$2.out" ) &
  pids+=("$!")
}
wait_all() { local p; for p in "${pids[@]}"; do wait "$p"; done; wait "$gate_pid"; pids=(); }
count_outcome() { cat "$work/$1".*.out | grep -c "^$2," || true; }
expect() { # label applied other_outcome
  local a n f
  a="$(count_outcome "$1" Applied)"; n="$(count_outcome "$1" "$3")"
  f="$(cat "$work/$1".*.out | grep -c WORKER_FAILED || true)"
  if [[ "$f" != "0" || "$a" != "$2" || $((a + n)) -ne "$parallel_calls" ]]; then
    echo "$1: expected $2 Applied and the rest $3, got Applied=$a $3=$n failed=$f" >&2
    cat "$work/$1".*.out | sort | uniq -c >&2
    exit 1
  fi
}
race() { # label statement gate_table gate_id
  local i
  rm -f "$work/$1".*
  pids=()
  gate_start "$3" "$4" 3
  for i in $(seq 1 "$parallel_calls"); do launch "$1" "$i" "$2"; done
  wait_all
}

# 1. Identical closes, then identical reopens.
race close "EXEC dbo.Stackish_CloseQuestion $q1, $actor, N'$root reason';" Users "$actor"
expect close 1 NoChange
race reopen "EXEC dbo.Stackish_ReopenQuestion $q1, $actor;" Users "$actor"
expect reopen 1 NoChange
sq -Q "
SET NOCOUNT ON;
IF (SELECT COUNT(*) FROM dbo.PostHistory WHERE Id > $history_base AND PostId = $q1 AND PostHistoryTypeId = 10) <> 1
   OR (SELECT COUNT(*) FROM dbo.PostHistory WHERE Id > $history_base AND PostId = $q1 AND PostHistoryTypeId = 11) <> 1
   OR NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = $q1 AND ClosedDate IS NULL)
    THROW 51960, 'Concurrent close/reopen wrote the wrong history or final state.', 1;
PRINT 'Identical concurrent closes and reopens: one Applied each, one history row each.';"

# 2. Close racing CreateAnswer. Every worker queues behind a lock on the question row, then the
#    close lands somewhere among the answers. Answers must either precede the close or be rejected.
rm -f "$work/answer".* "$work/closer".*
pids=()
gate_start Posts "$q1" 4
half=$((parallel_calls / 2))
# The pauses usually put the close mid-queue, but lock grant order isn't guaranteed: every
# answer before the close, or none, are also valid serializations. The invariants below hold
# for any order.
for i in $(seq 1 "$parallel_calls"); do
  launch answer "$i" "EXEC dbo.Stackish_CreateAnswer $q1, $actor, N'$root answer $i';"
  if [[ "$i" == "$half" ]]; then
    sleep 0.3
    launch closer 1 "EXEC dbo.Stackish_CloseQuestion $q1, $actor, N'$root race';"
    sleep 0.3
  fi
done
wait_all
applied="$(count_outcome answer Applied)"; conflicts="$(count_outcome answer Conflict)"
if [[ "$(count_outcome closer Applied)" != "1" || $((applied + conflicts)) -ne "$parallel_calls" ]] || grep -q WORKER_FAILED "$work"/answer.*.out "$work"/closer.*.out; then
  echo "close/answer race: closer=$(cat "$work"/closer.1.out) applied=$applied conflicts=$conflicts" >&2
  cat "$work"/answer.*.out | sort | uniq -c >&2
  exit 1
fi
sq -Q "
SET NOCOUNT ON;
DECLARE @closed datetime = (SELECT ClosedDate FROM dbo.Posts WHERE Id = $q1);
IF @closed IS NULL THROW 51961, 'Question should be closed after the race.', 1;
IF (SELECT COUNT(*) FROM dbo.Posts WHERE ParentId = $q1 AND Id > $q1 AND PostTypeId = 2) <> $applied
   OR (SELECT AnswerCount FROM dbo.Posts WHERE Id = $q1) IS DISTINCT FROM $applied
    THROW 51962, 'Answer rows/AnswerCount do not match Applied answers.', 1;
IF EXISTS (SELECT 1 FROM dbo.Posts WHERE ParentId = $q1 AND Id > $q1 AND CreationDate > @closed)
    THROW 51963, 'An answer was created after the question closed.', 1;
IF (SELECT COUNT(*) FROM dbo.PostHistory WHERE Id > $history_base AND PostId = $q1 AND PostHistoryTypeId = 10) <> 2
    THROW 51964, 'Close during the answer race wrote the wrong history.', 1;
PRINT CONCAT('Close vs CreateAnswer: ', $applied, ' answers before the close, ', $conflicts, ' rejected, none after.');"

# 3. Identical link inserts, then identical removals of that LinkId.
race link "EXEC dbo.Stackish_AddQuestionLink $q1, $q2, $actor, 3;" Users "$actor"
expect link 1 NoChange
ids="$(cat "$work"/link.*.out | grep -E '^(Applied|NoChange),' | cut -d, -f2 | sort -u)"
if [[ "$(wc -l <<< "$ids" | tr -d ' ')" != "1" ]]; then echo "Link race returned different EntityIds: $ids" >&2; exit 1; fi
sq -Q "
SET NOCOUNT ON;
IF (SELECT COUNT(*) FROM dbo.PostLinks WHERE PostId = $q1 AND RelatedPostId = $q2 AND LinkTypeId = 3) <> 1
   OR NOT EXISTS (SELECT 1 FROM dbo.PostLinks WHERE Id = $ids AND PostId = $q1 AND RelatedPostId = $q2 AND LinkTypeId = 3)
    THROW 51965, 'Concurrent identical links inserted duplicates.', 1;
IF (SELECT COUNT(*) FROM dbo.PostHistory WHERE Id > $history_base AND PostId = $q1 AND PostHistoryTypeId = 10) <> 2
    THROW 51966, 'Duplicate link wrote closure history.', 1;
PRINT 'Identical concurrent links: one row, one LinkId returned to every caller.';"

race unlink "EXEC dbo.Stackish_RemoveQuestionLink $ids, $actor;" Users "$actor"
expect unlink 1 NotFound
if [[ "$(scalar "SELECT COUNT(*) FROM dbo.PostLinks WHERE Id = $ids;")" != "0" ]]; then echo "Link $ids survived removal." >&2; exit 1; fi
echo "Identical concurrent removals: one Applied, the rest NotFound."

# 4. Unexpected failure after the Posts update: PostHistory is table-locked by another session and
#    the caller's LOCK_TIMEOUT expires on the history insert. The close must roll back entirely.
before="$(scalar "SELECT CONVERT(varchar(30), LastActivityDate, 126) FROM dbo.Posts WHERE Id = $q2;")"
sq -Q "BEGIN TRANSACTION; SELECT COUNT(*) FROM dbo.PostHistory WITH (TABLOCKX, HOLDLOCK); WAITFOR DELAY '00:00:04'; COMMIT;" >/dev/null &
blocker="$!"
sleep 0.5
if sq -Q "SET LOCK_TIMEOUT 1000; EXEC dbo.Stackish_CloseQuestion $q2, $actor, N'$root timeout';" > "$work/timeout.out" 2>&1; then
  wait "$blocker"; echo "Close should have failed on the lock timeout." >&2; exit 1
fi
wait "$blocker"
grep -q "Msg 1222" "$work/timeout.out" || { echo "Expected lock timeout:" >&2; cat "$work/timeout.out" >&2; exit 1; }
sq -Q "
SET NOCOUNT ON;
IF NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = $q2 AND ClosedDate IS NULL AND CONVERT(varchar(30), LastActivityDate, 126) = '$before')
   OR EXISTS (SELECT 1 FROM dbo.PostHistory WHERE Id > $history_base AND PostId = $q2)
    THROW 51967, 'A failed close left partial changes.', 1;
PRINT 'Failed close rolled back completely.';"

# 5. A close/reopen that waits behind another writer on the question row must stamp the time it
#    got the lock, not the time it was called. Hold the row for 3 s; the stamp must land well
#    after the call started.
for op in close reopen; do
  pids=()
  gate_start Posts "$q2" 3
  t0="$(scalar "SELECT CONVERT(varchar(23), GETUTCDATE(), 126);")"
  if [[ "$op" == close ]]; then stmt="EXEC dbo.Stackish_CloseQuestion $q2, $actor, N'$root late';"; else stmt="EXEC dbo.Stackish_ReopenQuestion $q2, $actor;"; fi
  rm -f "$work/late$op".*
  launch "late$op" 1 "$stmt"
  wait_all
  grep -q "^Applied," "$work/late$op.1.out" || { echo "late $op did not apply:" >&2; cat "$work/late$op.1.out" >&2; exit 1; }
  sq -Q "
SET NOCOUNT ON;
DECLARE @stamp datetime = (SELECT LastActivityDate FROM dbo.Posts WHERE Id = $q2);
IF DATEDIFF(millisecond, '$t0', @stamp) < 1500
   OR (SELECT MAX(CreationDate) FROM dbo.PostHistory WHERE Id > $history_base AND PostId = $q2) IS DISTINCT FROM @stamp
   OR ('$op' = 'close' AND (SELECT ClosedDate FROM dbo.Posts WHERE Id = $q2) IS DISTINCT FROM @stamp)
    THROW 51968, 'A $op that waited for the row lock stamped the time it was called.', 1;
PRINT 'A $op that waited for the row lock stamped the time it got the lock.';"
done

echo "Component 09 concurrency checks passed."

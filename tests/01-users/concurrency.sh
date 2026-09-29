#!/usr/bin/env bash
# Concurrent RecordProfileView check. MUTATES DATA (commits one fixture user): disposable database only.
# Usage: SQLCMDPASSWORD=... tests/01-users/concurrency.sh <server> <database> <login> [workers=8] [calls=200]
# Connection details come from arguments/environment; nothing is stored in the repository.
set -euo pipefail
server=$1; db=$2; login=$3; workers=${4:-8}; calls=${5:-200}
q() { sqlcmd -S "$server" -d "$db" -U "$login" -C -b -h -1 -W "$@"; }

id=$(q -Q "SET NOCOUNT ON; DECLARE @r TABLE(o varchar(20), id int); INSERT @r EXEC dbo.Stackish_CreateUser @DisplayName=N'Stackish concurrency fixture'; SELECT id FROM @r")
echo "fixture user $id, $workers workers x $calls calls"
pids=()
cleanup() {
    for p in "${pids[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null || true; done
    wait 2>/dev/null || true
    q -Q "SET NOCOUNT ON; DELETE dbo.Users WHERE Id = $id" >/dev/null || echo "WARNING: fixture user $id was not deleted"
}
trap cleanup EXIT   # runs on success, failure or interrupt, after stopping outstanding workers

worker_sql="SET NOCOUNT ON; DECLARE @i int = 0; WHILE @i < $calls BEGIN EXEC dbo.Stackish_RecordProfileView @UserId = $id; SET @i += 1; END"
for _ in $(seq "$workers"); do
    q -Q "$worker_sql" >/dev/null & pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done

views=$(q -Q "SET NOCOUNT ON; SELECT Views FROM dbo.Users WHERE Id = $id")
expected=$((workers * calls))
if [ "$views" -ne "$expected" ]; then echo "FAIL: Views=$views expected $expected"; exit 1; fi
echo "PASS: Views=$views"

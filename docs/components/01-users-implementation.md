# Step 2: users implementation

Implements [component 01](01-users.md): six procedures on SQL Server 2025 / compatibility 170. No parser or other component is used.

| Object | Purpose |
|---|---|
| `dbo.Stackish_CreateUser` | Insert a user with the shared initial values |
| `dbo.Stackish_UpdateUserProfile` | Replace the five editable fields; `NoChange` when identical |
| `dbo.Stackish_RecordUserAccess` | Set `LastAccessDate` to now |
| `dbo.Stackish_RecordProfileView` | `Views = Views + 1` |
| `dbo.Stackish_GetUserCard` | One UserCard row |
| `dbo.Stackish_ListUsers` | Directory by reputation / newest / name, literal prefix, paging |

```sh
sqlcmd -S <server> -d <database> -b -i sql/01-users/deploy.sql
sqlcmd -S <server> -d <database> -b -i tests/01-users/metadata.sql
sqlcmd -S <server> -d <database> -b -t 600 -i tests/01-users/acceptance.sql     # mutates, rolled back
tests/01-users/concurrency.sh <server> <database> <login>                        # mutates, commits then deletes one fixture user
sqlcmd -S <server> -d <database> -b -i examples/01-users/calls.sql               # mutates
```

## Implementation choices

- **Validation** works on the full `nvarchar(max)` input before it is converted to the column size: DisplayName required, not blank (space/tab/CR/LF) and at most 40 UTF-16 units; Location at most 100; WebsiteUrl at most 200; Age not negative. Errors are `THROW` 50101-50105 (write text/age), 50111 (NULL UserId on writes) and 50121/50122 (list paging/sort). Optional text is stored as supplied, including an empty string; only NULL clears. Nothing is trimmed.
- **Transactions**: every write is a single statement, so it is atomic without an explicit transaction; the procedures never begin, commit or roll back one. They do not change `XACT_ABORT`, so validation errors inherit the caller's policy: with the caller's `XACT_ABORT ON`, a `THROW` inside an open transaction leaves it uncommittable (`XACT_STATE() = -1`). The acceptance test sets `XACT_ABORT OFF` explicitly because it continues after caught errors.
- **NoChange detection** compares raw bytes (`CAST(... AS varbinary(max))` under `EXCEPT`, which also treats NULL as equal to NULL). A plain `<>` would use the case-insensitive, trailing-space-insensitive collation and report `bob` -> `Bob` as `NoChange`. The compare is part of the UPDATE's WHERE clause, so an identical profile writes nothing.
- **Concurrency**: `RecordProfileView` computes `Views + 1` from the locked row inside one UPDATE, so parallel calls serialize on the row lock and no increment is lost. Concurrent profile updates are last-writer-wins per whole call.
- **Special users (judgment call)**: `GetUserCard` returns imported nonpositive users (only Id -1 on the 2018-06 copy). Writes on `Id <= 0` return `NotFound` without touching the row, on the reading that Community/placeholder accounts are not editable. `ListUsers` includes them. NULL `@UserId` throws on writes and returns an empty set on `GetUserCard`.
- **ListUsers**: one SELECT per sort (no `CASE` ordering), `Id` as tie-breaker (ascending for reputation/name, descending for newest). The prefix is escaped (`!`, `%`, `_`, `[`) and used with `LIKE ... ESCAPE`, so it is literal; matching follows the database collation. NULL or empty prefix means no filter. Newest and name sorts scan `Users` unless the target has a suitable index; none was added.
- The writes report Applied/NoChange/NotFound only; `Conflict` has no use here. `RecordUserAccess` reports `Applied` whenever the user exists, even if the timestamp lands on the same value.
- No 2025-only feature was needed.

## Validation status

Executed September 29, 2026 on the authorized `StackOverflow` 2018-06 research database (SQL Server 2025 CU9, compatibility 170):

- `deploy.sql` succeeded.
- [metadata.sql](../../tests/01-users/metadata.sql) passed (parameters, defaults, result shapes for all six).
- [acceptance.sql](../../tests/01-users/acceptance.sql) passed, and passed again on rerun. Fixture rows were rolled back; identity values were consumed, not reseeded.
- [concurrency.sh](../../tests/01-users/concurrency.sh): 8 workers x 200 `RecordProfileView` calls produced Views = 1,600 exactly.
- [calls.sql](../../examples/01-users/calls.sql) ran cleanly; it leaves one committed "Example User" row on that database.
- The first acceptance run failed on a wrong expectation in the test itself (a renamed fixture no longer matched the Unicode prefix); the test was corrected, no procedure changed.

Not covered: the 2024-04 restore, a concurrent mix of profile updates with views, and performance of the newest/name sorts on the full table.

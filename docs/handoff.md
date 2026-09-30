# Giving an assignment to another LLM

Start each session with this repository and exactly one component brief. The schema capture is sufficient for authoring; do not pass around the research credentials in prompts committed to Git. Supply access separately if and when you authorize testing.

Copy the following prompt and replace the assignment placeholder:

> Implement Stackish component `<number and name>` from `docs/components/<file>.md`.
>
> Read `docs/design.md`, `docs/contracts.md`, `docs/result-shapes.md`, `docs/research/schema.md`, and your component brief first. Use the existing Stack Overflow SQL Server schema exactly as documented. Target SQL Server 2025 with compatibility level 170. Use 2025-only features when they naturally solve a problem, without going looking for ways to showcase them. Produce the procedures/function assigned to you under your component's `sql/` directory, executable call examples under its `examples/` directory, and a short implementation note describing choices, dependencies and checks actually run.
>
> Preserve the public names, parameters, result shapes, data rules and scope. Write natural SQL in your own style. Do not imitate another component's formatting or refactor other contributors' files. Do not deliberately introduce bugs, teaching traps, waits or broken transactions. Do not build a web app or teaching material.
>
> Do not add or alter tables, indexes, columns, constraints, database settings, triggers, or table types. Do not depend on report tables, customized index names, hidden helper objects, or historical rows absent from the dump. New stored procedures and the assigned tag function are the only planned database objects.
>
> This assignment authorizes preparing repository files. Do not connect to or change a database unless this session separately authorizes it. If no test database is authorized, provide runnable checks and clearly state they were not executed. Avoid credentials and hard-coded database names in files. Use CREATE OR ALTER with suitable batch separators, and do not deploy or run workload calls merely by opening an example script.
>
> Each procedure needs a normal call and missing-target example. Include the acceptance checks in your brief. Write procedures should meet their invariants under concurrent calls, but production-grade infrastructure is unnecessary. Do not force all implementations into one generic framework. Raise a concrete contract conflict instead of silently changing another component's interface. Finish with a list of created objects and validation results.

## Contributor delivery checklist

- One script per public object, or a clearly organized component script with GO boundaries.
- No USE statement that silently switches to a hard-coded production/research database.
- No data seeding, bulk repairs, schema migrations, index maintenance, or lookups rewritten during deployment.
- Examples use IDs selected from the target database; placeholders are clearly labeled.
- A validation note distinguishes authored checks, executed checks and outstanding integration checks.
- Any proposed interface change is documented with its impact on other components before adoption.

## Ordered implementation plan

The component numbers identify ownership, not development order. Follow this sequence for a straightforward series of LLM handoffs. Only the shared tag parser is a required dependency between components; the later placement of some components makes integration easier, rather than imposing extra procedure dependencies.

| Step | Component | Why this position / prerequisites |
|---|---|---|
| 1 | [07 Tags and parsing](components/07-tags.md) | Implement and validate `dbo.Stackish_SplitTags` first, then the three tag procedures. Questions, token-based discovery, and profile top tags use this function. Single-tag analytics may use exact delimiter matching instead. No other component is required. |
| 2 | [01 Users](components/01-users.md) | Establish user creation and profile behavior early. No dependency on the parser or another component; imported users are already available for other components' tests. |
| 3 | [02 Questions](components/02-questions.md) | Requires the parser from step 1. Establish tag-count and initial/edit-history behavior before integrating other content writers. Does not call user procedures. |
| 4 | [03 Answers](components/03-answers.md) | Integrate parent answer counts, activity, history and acceptance with question behavior. No required procedure dependency: existing questions and users are sufficient to develop it independently. |
| 5 | [04 Comments](components/04-comments.md) | Verify comment behavior on both questions and answers. No required component dependency; use imported content if earlier writers are unavailable. |
| 6 | [05 Votes and reputation](components/05-votes.md) | Check vote deltas alongside established post/user behavior. No required component dependency; acceptance remains owned by Answers. |
| 7 | [09 Moderation and links](components/09-moderation.md) | Check closing against answer creation and shared history rules. No required procedure dependency. |
| 8 | [06 Question discovery](components/06-discovery.md) | Requires the parser from step 1. Validate reads against imported content and, when available, changes produced by the earlier writers. |
| 9 | [10 Badge browsing](components/10-badges.md) | Independent read-only component; may be implemented at any time. Establish badge output before the final profile integration. |
| 10 | [08 Page reads and activity](components/08-pages.md) | Requires the parser from step 1. Integrate question/profile result sets after the underlying behavior and shared output shapes are exercised. Pages query base tables directly and need not call the other components' procedures. |
| 11 | Integration and workload packaging | Once all ten assignments are complete, assemble deployment scripts, check the 43-object inventory and interfaces, run cross-component checks on an authorized disposable restore, and package SQLQueryStress calls as described in [the workload plan](workload.md). |

If using separate sessions concurrently, steps 2, 4, 5, 6, 7 and 9 can start immediately. Steps 3, 8 and 10 can be authored against the documented parser interface, but need its implementation for execution checks. The step-1 leaderboard uses exact delimiter matching and does not call the parser. No component needs a newly created user, question or answer from another component before it can operate on the imported database.

Deployment order is simpler than the recommended development sequence: verify SQL Server 2025 / compatibility 170 and the existing schema, create the parser, then create the 42 procedures in any order. There are no mandatory calls between procedures. Do not introduce such dependencies silently. Perform mutation tests only after database access and changes have been authorized for that implementation session.

## Lessons from step 1

- The parser removes duplicate tokens under database collation, so write components must validate raw syntax and duplicates separately before calling it. Validate the full input length before a bounded function parameter can truncate it.
- Unknown tags should return before scanning Posts. Existing-tag leaderboards still require an expensive membership search on this schema; exact `<tag>` matching avoids token expansion but does not make the search indexed.
- Tag wiki pointers may be zero, dangling or point to a different post type. Keep the catalog row and return NULL wiki text.
- A procedure using a local temp table may not support static result discovery through `sys.dm_exec_describe_first_result_set`. Verify its actual result through execution as well.
- Rollback-based fixture tests consume identity values even when their rows are rolled back. Use disposable restores and never reseed to hide the gaps.

## Lessons from step 2

- The database collation ignores case and trailing spaces, so `=`/`<>` cannot detect a no-op edit; compare bytes (see [users implementation](components/01-users-implementation.md)).
- A `THROW` under the caller's `XACT_ABORT ON` dooms an open transaction (`XACT_STATE() = -1`); procedures inherit that setting. Choose each procedure's transaction policy for correctness (multi-statement writes may well want `XACT_ABORT ON`), and have tests that continue after caught errors set the session option explicitly or isolate those cases.
- `EXEC` parameter values cannot be expressions (`REPLICATE(...)`, concatenation); assign them to variables first.

## Lessons from steps 3-5

- Stored procedures captured with `INSERT ... EXEC` cannot issue `ROLLBACK`, even for an expected NotFound/Conflict branch that changed no data. For expected status returns inside an opened procedure transaction, commit the empty transaction and reserve rollback for actual error paths or changed work.
- The shared research server may default logins to a smaller restore such as `StackOverflow2010`; explicitly target the intended disposable database before deployment/testing and verify required tables such as `PostHistory`.

## Integration ownership

The integration session owns the deployment manifest, object-count check, final schema preflight, SQLQueryStress packaging and cross-component verification. Deployment creates the parser first, then all procedures; there are no required inter-procedure dependencies. Integration can fix correctness and contract disagreements, but must preserve the diversity of implementation styles.

Confirm every referenced base table/column/type and required lookup ID exists on the eventual 2024-04 restore. Stop and report a mismatch rather than adding the missing schema. A performance difference from this research server is not by itself a reason to add indexes. Database changes require authorization for the current implementation session; authorization was granted for step-1 deployment and testing on the disposable research server.

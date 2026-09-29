# Stackish design assessment

Status: design only, September 29, 2026. No database objects or data were changed. This repository currently supplies implementation assignments, not an executable workload.

## Purpose and boundaries

Build a recognizable Stack Overflow workload using stored procedures against the existing public SQL Server database. Call it directly from SQLQueryStress; no website, service, authentication system, or teaching material is required. Reads and writes both matter. Existing imported content may be changed, and new content may be created. Restore a backup to reset the experiment.

Preserve the existing schema: no new tables, columns, indexes, constraints, types, or triggers; no database setting changes. New procedures and the explicitly listed function are the intended future deliverables. Use `dbo.Stackish_` names to separate them from imported objects. Do not depend on this research server's extra indexes or report tables.

Use ordinary working code with contributor-specific formatting, naming of local variables, query structure, and implementation choices. Do not deliberately add bugs, broken transactions, or artificial delays. Shared behavior and interfaces must agree; internal style does not need to agree. Brent will make teaching modifications separately.

## What the inspection established

The research database is `StackOverflow` (2018-06 data, as supplied by Brent), not the smaller `StackOverflow2010` or `StackOverflow2013` databases also on the server. It has about 40.7 million posts, 8.9 million users, 66.4 million comments, 150.8 million votes, 27.3 million badge awards, 5.1 million post links, and 52,445 tags. These are metadata estimates, not scans or audited totals.

[Full schema and indexes](research/schema.md), [machine-readable metadata](research/schema-snapshot.json), and [lookup values](research/lookup-values.json) capture the inspection. No credentials or connection endpoint are included in these files.

| Table | Stackish use | Important limitation |
|---|---|---|
| Users | Registration, profile, counters, directory | No passwords or sessions; display names are not unique |
| Posts | Questions, answers, tag wiki content | Multiple post types; tags are a delimited string, not a join table |
| Comments | Comments on either kind of post | No separate comment-voter records |
| Votes | Post voting and legacy favorites | Imported sampled upvotes have NULL UserId; cannot reconstruct actors |
| Tags | Tag directory, counts, wiki pointers | No PostTags table; wiki pointers are required integers |
| PostHistory | New post revisions and moderation events | Empty on this research copy; no historical revisions to reconstruct |
| PostLinks | Links and duplicates | Link types 1 (linked), 3 (duplicate); no unique pair constraint |
| Badges | Existing award lists and summaries | No badge class or definition table in this schema |
| Four lookup tables | Post, vote, history, link type meanings | Read-only; do not add invented enum values |
| Report_BadgePopularity, Report_UsersByQuestions | None | Research extras, not dependencies |

The research engine is SQL Server 2025 CU9, compatibility 170. The implementation floor is SQL Server 2025 with database compatibility level 170. Use 2025-only features when they fit the problem naturally; do not seek out uses merely to showcase them. Do not change database settings during deployment; the target database must already meet this baseline. Final testing must include a restored 2024-04 database; its structures are expected to match based on Brent's information, but that copy has not been verified here.

Observed legacy details: question 13 has AcceptedAnswerId = 0; 129 of the first 1,000 questions have that value and none in that sample have NULL. Answer 18 has OwnerUserId = 0. The first ten vote records sampled have NULL UserId. Missing references must tolerate zero, NULL, and absent rows. No full data integrity audit was attempted. Read procedures must preserve content when a user or related record is unavailable.

## Website assessment and feature mapping

The website provides inspiration rather than a specification to reproduce exactly. Reviewed September 29, 2026:

| Surface/source | Relevant behavior | Stackish component |
|---|---|---|
| [Tour](https://stackoverflow.com/tour) | Questions, answers, acceptance, votes, comments, editing | Questions, answers, comments, votes |
| [Question directory](https://stackoverflow.com/questions) | Newest/active sorting, scores, answer counts, tags, unanswered filters | Discovery |
| [Example question](https://stackoverflow.com/questions/11227809/why-is-conditional-processing-of-a-sorted-array-faster-than-of-an-unsorted-array) | Question body and metadata, answers, comments, author information, links | Page reads |
| [Search help](https://stackoverflow.com/help/searching) | Tags, text, author, score, dates, acceptance and answer filters | Parameterized search; no search-language parser |
| [User directory](https://stackoverflow.com/users) and [profile example](https://stackoverflow.com/users/22656/jon-skeet) | Reputation, biography, posts, tags, badges | Users, profiles, badges |
| [Tag directory](https://stackoverflow.com/tags) | Name filtering, popularity, excerpts | Tags |
| [Accepted answers](https://stackoverflow.com/help/accepted-answer) | Question author chooses an answer | Answers; pointer-only simplified acceptance |
| [Downvoting](https://stackoverflow.com/help/privileges/vote-down) | Scores and reputation effects | Simplified vote deltas, without privilege thresholds |

Page procedures return SQL result sets, not HTML. Stored body text is treated as opaque content; no Markdown renderer or HTML sanitizer is needed for this workload.

## Planned scope

Ten component assignments contain 42 procedures and one inline table-valued function, 43 objects total. There is no quota to fill with views or extra helpers. Proposed objects and exact interfaces are in the [component briefs](components/README.md); shared behavior is in [contracts](contracts.md).

| Assignment | Objects | Responsibility |
|---|---:|---|
| 01 Users | 6 procedures | Registration, profile updates, access/views, directory, user card |
| 02 Questions | 4 procedures | Create, edit, retag, record views |
| 03 Answers | 3 procedures | Create, edit, set/clear accepted answer |
| 04 Comments | 4 procedures | Add, edit, delete, list |
| 05 Votes | 6 procedures | Question/answer up/down votes, removal, summary |
| 06 Discovery | 5 procedures | Lists, search by text/tag, unanswered, related |
| 07 Tags | 3 procedures + 1 function | Directory, detail, top contributors, tag parsing |
| 08 Pages | 4 procedures | Question page, profile page, user posts, post history |
| 09 Moderation and links | 4 procedures | Close, reopen, add/remove links including duplicates |
| 10 Badges | 3 procedures | User awards, badge directory, recipients |

No new badge-awarding engine, bounties, saved collections, watched tags, notifications, inbox, authentication, subscriptions, full-text infrastructure, post deletion/undeletion, reputation ledger, or review queues. Those need missing state, substantially more rules, or misleading approximations. Historical favorite and bounty counts can be displayed, but new favorite/bounty actions are outside this first release. No comment voting because the schema cannot record who voted on a comment. No badge class inferred from names. Do not fabricate absent edit history.

Acceptance changes only AcceptedAnswerId and activity; it does not replay vote type 1 or grant/revoke acceptance reputation. Closing is immediate, without a close-vote quorum. Duplicate links and closing are separate actions. These simplifications allow useful independent calls with much less inter-component coupling.

## Phases and handoff order

1. **Assessment (this delivery):** recorded schema, features, interfaces, boundaries, and assignments.
2. **Independent implementation:** give each LLM the common handoff and one component brief. Implement tags first because its parser is the one shared function; users, comments, votes, moderation, and badges can be authored independently. Questions, discovery, profiles, and tag analytics use the parser. Answers follow the shared rules but do not call question procedures. Authoring can overlap; deployment must put the parser first. Follow the [ordered implementation plan](handoff.md#ordered-implementation-plan) for the recommended handoff sequence.
3. **Integration:** assemble scripts, check output contracts, verify write invariants and concurrent calls on an authorized disposable restore. Resolve interface disagreements without restyling all code.
4. **Workload packaging:** parameter queries and independent SQLQueryStress call scripts, then mixed sessions; no need to chain new IDs between operations.
5. **Release validation:** repeat smoke/concurrency checks against 2024-04, confirm schema compatibility and runnable examples, publish installation and restore instructions. No permanent data cleanup mechanism.

Each LLM owns its own SQL and example files. The integrating session owns deployment order and shared contracts. Contributor questions that change a contract should become an explicit design amendment, not silent local divergence. [Handoff instructions](handoff.md) provide a copyable prompt.

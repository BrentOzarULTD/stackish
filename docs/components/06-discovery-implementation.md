# Question discovery implementation

Implemented `Stackish_ListQuestions`, `Stackish_SearchQuestions`, `Stackish_GetQuestionsByTag`, `Stackish_GetUnansweredQuestions`, and `Stackish_GetRelatedQuestions` in `sql/06-discovery/`.

The procedures use explicit question/answer type checks, left joins for optional authors, delimiter-complete tag matching, escaped literal search text, and actual child answers for both unanswered modes. Accepted-answer output is normalized only when the pointer resolves to a type-2 child. Related questions expand tags with the existing parser and count distinct shared tokens. These are potentially expensive scans/aggregations on the public dump; no indexes were added.

Validation scripts are provided in `tests/06-discovery/acceptance.sql`. They were run on the authorized disposable 2018-06 database after deploying the parser dependency. The checks are SQLCMD smoke calls; the integration suite now verifies exact returned types and ordered columns.

Integration adds a typed-empty early return for unknown catalog tags in GetQuestionsByTag, preserving the documented unknown-tag behavior even when imported post tokens lack a catalog row. The known-tag query is unchanged. See [integration evidence](../integration-validation.md) for live checks and observed scan costs.

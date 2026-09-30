# Question discovery implementation

Implemented `Stackish_ListQuestions`, `Stackish_SearchQuestions`, `Stackish_GetQuestionsByTag`, `Stackish_GetUnansweredQuestions`, and `Stackish_GetRelatedQuestions` in `sql/06-discovery/`.

The procedures use explicit question/answer type checks, left joins for optional authors, delimiter-complete tag matching, escaped literal search text, and actual child answers for both unanswered modes. Accepted-answer output is normalized only when the pointer resolves to a type-2 child. Related questions expand tags with the existing parser and count distinct shared tokens. These are potentially expensive scans/aggregations on the public dump; no indexes were added.

Validation scripts are provided in `tests/06-discovery/acceptance.sql`. They were authored but not executed in this session because SQL Server connectivity was not available through the sandbox. Disposable-server execution remains an integration check.

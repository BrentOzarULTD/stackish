# Comments Implementation Notes

Implemented objects:

- `dbo.Stackish_AddComment`
- `dbo.Stackish_EditComment`
- `dbo.Stackish_DeleteComment`
- `dbo.Stackish_GetPostComments`

Comment creation accepts existing questions and answers only, inserts the comment and increments that exact post's `CommentCount` in one transaction. Editing and deletion require the original positive user id and an existing acting user. Editing preserves score and creation date. Deletion physically removes the comment and decrements the parent counter if the parent question/answer still exists; owned orphan comments are still removable.

`GetPostComments` returns the shared `Comment` shape ordered by `CreationDate`, then `Id`. It joins through an existing question/answer post, so a missing post returns an empty typed result set even if orphaned comments reference the same id. Missing positive users are preserved with `NULL` display names.

Validation authored:

- `tests/04-comments/acceptance.sql` covers question and answer comments, missing/wrong-type targets, author-only editing/deletion, no-op edits, preserving score/creation date, missing comment authors on reads, empty reads for missing posts, repeated deletion, owned orphan deletion, oversized/blank text and invalid paging.
- `tests/04-comments/concurrency.sh` covers separate-session concurrent comment creation, delete races and post comment-count deltas.

Checks run on the authorized disposable `StackOverflow` database:

- Deployment scripts for 07 Tags, 02 Questions, 03 Answers and 04 Comments.
- `tests/04-comments/acceptance.sql`
- `tests/04-comments/concurrency.sh` with 20 parallel calls

Remaining integration coverage: run these same checks on the eventual 2024-04 restore.

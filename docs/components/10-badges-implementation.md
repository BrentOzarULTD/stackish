# Badge Browsing Implementation Notes

Implemented objects (read-only):

- `dbo.Stackish_GetUserBadges`
- `dbo.Stackish_ListBadges`
- `dbo.Stackish_GetBadgeRecipients`

`GetUserBadges` returns every award row for a user that exists in `Users`, ordered by Date then Id descending. Awards whose UserId is missing from `Users` exist in the dump; per the brief, a missing user returns empty even if such awards exist.

`ListBadges` groups the award rows by Name: `COUNT_BIG(*)` awards, `COUNT_BIG(DISTINCT UserId)` recipients (dangling user IDs included), `MIN(Date)` first award. The prefix is literal (`%`, `_`, `[` and `\` are escaped; a trailing space counts); NULL or empty means all badges. Names group under the database collation, so case variants would group together. No class, tier or award-rule data exists or is invented.

`GetBadgeRecipients` requires a nonblank name and returns one row per award, Date then Id descending, left-joining `Users` so missing recipients stay with NULL DisplayName (UserId 0 would be returned as NULL).

Cost: there is no index leading on `Badges.Name`, so `ListBadges` scans and aggregates all ~27M rows (about 2.7 s elapsed / 9 s CPU on the research server) and `GetBadgeRecipients` scans for the name (about 0.6-1.1 s). `GetUserBadges` uses the UserId index here (~20 ms). No index was added; the report tables were not used.

Validation authored and executed on the authorized disposable `StackOverflow` research database:

- `tests/10-badges/acceptance.sql` (fixtures inserted in a rolled-back transaction): repeated awards, same-timestamp ties, award count vs distinct recipients, a recipient missing from Users, Unicode badge and display names, literal `_`/`%`/`[` and trailing-space prefixes, NULL vs empty prefix, AwardCount/Name ordering, paging, missing user/badge empties, invalid paging and blank names, result shape metadata. Row order is compared against independent queries, and the order-capture table variable's identity column is used only for relative order, since DELETE does not reset it. Passed.
- `examples/10-badges/calls.sql` executed.

Not executed: the 2024-04 restore. No concurrency test; these procedures do not write.

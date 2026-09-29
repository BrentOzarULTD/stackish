# Badge browsing

## Scope and ownership

Base tables: Read Badges, Users.
Dependencies: None. No writes or award engine.

Own future files under `sql/10-badges/` and `examples/10-badges/`; do not edit other components. Deliver working code for this assignment, examples, and a short implementation/validation note. This brief authorizes file preparation, not deployment to the research server.

## Procedure contracts

| Name (after Stackish_) | Parameters | Output | Behavior |
|---|---|---|---|
| `GetUserBadges` | `@UserId int, PAGE` | BadgeId int, Name nvarchar(40), AwardedDate datetime | Latest Date descending then BadgeId descending; keep repeated awards. Missing user returns empty. |
| `ListBadges` | `@NamePrefix nvarchar(40)=NULL, PAGE` | Name nvarchar(40), AwardCount bigint, RecipientCount bigint, FirstAwarded datetime | Group by name; order AwardCount descending then Name ascending. Distinct UserId recipient count; includes imported missing user IDs in aggregate counts. |
| `GetBadgeRecipients` | `@BadgeName nvarchar(40), PAGE` | BadgeId int, UserId int, DisplayName nvarchar(40), AwardedDate datetime | Latest awards first, BadgeId desc; left join users so missing recipients do not remove awards. |

## Acceptance checks

Check repeated awards, distinct recipients vs award count, same-date ties, missing user display names and Unicode badge names. Do not invent bronze/silver/gold metadata or automatic award rules.

Also apply common input, missing-ID, no-op and unexpected-error rules. Writes must be all-or-nothing. Provide a normal call and missing-target example per procedure, plus the component-specific checks above. Run mutations only on an explicitly authorized disposable database; report unrun checks honestly.

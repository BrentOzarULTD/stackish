# Users

## Scope and ownership

Base tables: Users; read-only Posts only if needed for validation.
Dependencies: None.

Own future files under `sql/01-users/` and `examples/01-users/`; do not edit other components. Deliver working code for this assignment, examples, and a short implementation/validation note. This brief authorizes file preparation, not deployment to the research server.

## Procedure contracts

| Name (after Stackish_) | Parameters | Output | Behavior |
|---|---|---|---|
| `CreateUser` | `@DisplayName nvarchar(max), @AboutMe nvarchar(max)=NULL, @Location nvarchar(max)=NULL, @WebsiteUrl nvarchar(max)=NULL, @Age int=NULL` | Write | Create a user using the shared initial values. |
| `UpdateUserProfile` | `@UserId int, @DisplayName nvarchar(max), @AboutMe nvarchar(max)=NULL, @Location nvarchar(max)=NULL, @WebsiteUrl nvarchar(max)=NULL, @Age int=NULL` | Write | Replace all editable fields; NULL clears optional fields. Leave reputation, voting counters, access times and account fields alone. Identical values are NoChange. |
| `RecordUserAccess` | `@UserId int` | Write | Set LastAccessDate to now. |
| `RecordProfileView` | `@UserId int` | Write | Increment Views by one; does not update LastAccessDate. |
| `GetUserCard` | `@UserId int` | UserCard | One user; include nonpositive imported IDs for reads. |
| `ListUsers` | `@NamePrefix nvarchar(40)=NULL, @Sort varchar(20)='reputation', PAGE` | UserCard | Sort reputation descending, newest CreationDate descending, or name DisplayName ascending. Prefix is literal, not a LIKE expression. |

## Acceptance checks

Check Unicode names, duplicate display names, optional-field clearing, unchanged profiles, missing users, atomic view increments, and each sort. Verify counter defaults on creation.

Also apply common input, missing-ID, no-op and unexpected-error rules. Writes must be all-or-nothing. Provide a normal call and missing-target example per procedure, plus the component-specific checks above. Run mutations only on an explicitly authorized disposable database; report unrun checks honestly.

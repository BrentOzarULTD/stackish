# Stackish

A Stack Overflow database workload built from stored procedures, for SQLQueryStress and database classes. It reads and modifies the existing public database without adding tables or indexes.

The implementation floor is SQL Server 2025 with compatibility level 170.

Step 1, tags and parsing, is implemented for review: three read procedures and the shared tag parser. The assessment and current tests use the 2018-06 research database; the planned release targets the 2024-04 dataset. Step 2, users, is implemented for review but not yet executed against a database; see [its note](docs/components/01-users-implementation.md). The remaining components are still planned.

Start with the [design assessment](docs/design.md), then choose one of the [ten component assignments](docs/components/README.md). The proposed scope is **42 stored procedures and one tag-parsing function**.

- [Step 1 installation, examples and validation](docs/components/07-tags-implementation.md)
- [Shared behavior and interfaces](docs/contracts.md)
- [Result-set definitions](docs/result-shapes.md)
- [Observed database schema and indexes](docs/research/schema.md)
- [Copyable implementation handoff](docs/handoff.md)
- [Workload mix and integration plan](docs/workload.md)

Contributors should write working code in their own style while respecting the shared contracts. There is no requirement to make all components look alike, and no need to add intentional defects. Restore the database from backup to reset the workload.

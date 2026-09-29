# Stackish

A Stack Overflow database workload built from stored procedures, for SQLQueryStress and database classes. It reads and modifies the existing public database without adding tables or indexes.

The implementation floor is SQL Server 2025 with compatibility level 170.

The project is currently in the design phase. The assessment uses the 2018-06 research database; the planned release targets the 2024-04 dataset. No procedures have been implemented or deployed yet.

Start with the [design assessment](docs/design.md), then choose one of the [ten component assignments](docs/components/README.md). The proposed scope is **42 stored procedures and one tag-parsing function**.

- [Shared behavior and interfaces](docs/contracts.md)
- [Result-set definitions](docs/result-shapes.md)
- [Observed database schema and indexes](docs/research/schema.md)
- [Copyable implementation handoff](docs/handoff.md)
- [Workload mix and integration plan](docs/workload.md)

Contributors should write working code in their own style while respecting the shared contracts. There is no requirement to make all components look alike, and no need to add intentional defects. Restore the database from backup to reset the workload.

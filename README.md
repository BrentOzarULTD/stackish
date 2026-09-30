# Stackish

A Stack Overflow database workload built from stored procedures, for SQLQueryStress and database classes. It reads and modifies the existing public database without adding tables or indexes.

The implementation floor is SQL Server 2025 with compatibility level 170.

All ten components are implemented: **42 stored procedures and one tag-parsing function**, matching the original 43-object plan. The integration package supplies complete deployment, executable smoke and contention checks, and independent SQLQueryStress workloads. The release targets the **2024-04 dataset**; current live validation uses the authorized 2018-06 research copy with customized indexes.

- [Installation, validation, operation and reset](docs/installation.md)
- [Complete SQLCMD deployment](sql/deploy.sql)
- [SQLQueryStress batches, parameter queries and mappings](workload/README.md)
- [Workload mix](docs/workload.md)
- [Executed checks and release gaps](docs/integration-validation.md)
- [Design assessment](docs/design.md), [shared contracts](docs/contracts.md), and [result shapes](docs/result-shapes.md)
- [Component briefs and implementation notes](docs/components/README.md)
- [Observed research schema](docs/research/schema.md)

Contributors should write working code in their own style while respecting the shared contracts. There is no requirement to make all components look alike, and no need to add intentional defects. Restore the database from backup to reset the workload.

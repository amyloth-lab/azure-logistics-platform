# ADR-0004: Azure SQL Database as the transactional store

- **Status:** Proposed
- **Date:** 2026-11-03
- **Deciders:** Application and data platform
- **Related:** [Identity and RBAC](../day-01/identity-and-rbac.md)

## Context

Inventory and orders require multi-row transactions, uniqueness constraints, foreign keys, optimistic concurrency, and reliable point-in-time recovery. The team is familiar with SQL and wants a managed service with Entra authentication, private endpoints, auditing, and a clear backup model.

## Decision

Use **Azure SQL Database**:

- General Purpose serverless in dev (auto-pause), General Purpose zone-redundant in prod.
- Private endpoint only; public network access disabled.
- Entra-only authentication; no SQL logins.
- TDE with a customer-managed key in Key Vault for production; service-managed key acceptable in dev if documented.
- Auditing to Log Analytics and immutable storage.
- PITR 35 days; long-term retention per policy.
- Transactional outbox table in the same database.
- Alembic migrations run by a separate migration identity with `db_ddladmin`.

## Consequences

### Positive

- ACID transactions make inventory reservation and order creation correct.
- Mature backup, PITR, auditing, and threat detection.
- Entra integration and private endpoint fit the zero-trust model.
- Relational constraints catch data-quality bugs early.
- Outbox can commit in the same transaction as the business change.

### Negative / trade-offs

- Vertical scaling and connection management need attention.
- Serverless cold starts in dev can confuse latency tests.
- CMK adds Key Vault dependency and operational work.
- Schema migrations require discipline (expand/contract).
- Less horizontally elastic than a globally distributed NoSQL store.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Azure Cosmos DB | Global distribution and elasticity, but cross-partition transactional patterns are more complex; relational integrity is a better fit |
| PostgreSQL Flexible Server | Viable alternative; team preference and Azure SQL integration won |
| SQL Managed Instance | Overkill for this workload and more expensive |
| SQLite/Postgres in a container | Not production-grade for this availability/backup requirement |

## Review trigger

- Multi-region write requirements.
- Sustained throughput beyond SQL tier limits.
- A regulatory requirement that SQL cannot meet.
- Migration to PostgreSQL becomes an organizational standard.

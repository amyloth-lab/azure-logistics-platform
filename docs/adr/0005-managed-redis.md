# ADR-0005: Azure Managed Redis for cache and idempotency

- **Status:** Proposed
- **Date:** 2026-11-03
- **Deciders:** Application platform, data platform
- **Related:** [Network design](../day-01/network-design.md)

## Context

Inventory reads are frequent and tolerate short-lived staleness. Order creation needs idempotency keys to prevent duplicate submissions during retries. The database should remain the source of truth, but repeated identical reads and writes create unnecessary load and duplicate side effects.

## Decision

Use **Azure Managed Redis** (Balanced B0/B1 in the lab, B1/B3 in production):

- Private endpoint only; public access disabled.
- Microsoft Entra authentication; access keys disabled.
- TLS required.
- Cache-aside for inventory reads with a short TTL (for example, 30 seconds) and explicit invalidation on writes.
- Idempotency keys for order creation with a TTL matching the business retry window.
- No session storage; the API remains stateless.
- Redis is never the source of truth. If Redis is unavailable, the API degrades to SQL.

## Consequences

### Positive

- Lower SQL load and latency for repeated inventory reads.
- Idempotent order creation protects against client retries.
- Entra auth avoids shared access keys.
- Private endpoint keeps cache traffic off the public internet.

### Negative / trade-offs

- Cache invalidation is hard; stale reads are possible within the TTL.
- Another stateful service to monitor, patch, and pay for.
- Entra token refresh for Redis connections needs client-library support.
- A cache outage must not become an API outage; fallback logic is required.
- Eviction policy and memory sizing need production tuning.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| No cache, SQL only | Simpler, but higher latency and load; misses the brief's Redis requirement |
| In-memory cache per pod | Inconsistent across pods; not shared |
| Azure Cache for Redis (classic) | Migration path to Managed Redis; new deployments should use Managed Redis |
| Cosmos DB as cache | Expensive and operationally heavier for this use case |

## Implementation note

Use the `azurerm_managed_redis` resource with a pinned azurerm 4.x provider. If your provider version does not yet expose a required setting, use `azapi_resource` and pin the API version rather than falling back to access keys. Validate the private DNS zone (`privatelink.redis.azure.net`) and Entra token refresh behavior in the client library on Day 3.

## Review trigger

- Cache hit ratio below target.
- Redis latency or eviction alerts.
- Redis is used for data that cannot be reconstructed.
- Azure Managed Redis is unavailable in the chosen region.

# ADR-0006: Service Bus + Functions with a transactional outbox

- **Status:** Proposed
- **Date:** 2026-11-03
- **Deciders:** Application and integration
- **Related:** [Logical architecture](../../diagrams/logical-architecture.png)

## Context

Order and inventory changes must trigger asynchronous work (audit, notifications, reconciliation, downstream ERP integration) without making the HTTP request wait. Publishing directly to a broker after a database commit creates a dual-write failure: the database can commit while the publish fails, or the publish can succeed while the transaction rolls back.

## Decision

- Use **Azure Service Bus** topics for `order-events`, `inventory-events`, and `shipment-events`.
- Write an **outbox row in the same SQL transaction** as the business change.
- A relay process publishes unprocessed outbox rows to Service Bus and marks them processed.
- Use **Azure Functions** (Flex Consumption) with Service Bus triggers for asynchronous consumers.
- Consumers are idempotent, use `MessageId` for duplicate detection, and send poison messages to the DLQ after the retry limit.
- Topic subscriptions use filters so each consumer receives only the events it needs.
- Use managed identity for producer and consumer; no SAS keys.

## Consequences

### Positive

- No lost events when the broker is unavailable after a database commit.
- Retries are safe and observable.
- Consumers scale independently.
- DLQ gives operators a recovery path.
- Functions can scale to zero when there is no work.

### Negative / trade-offs

- The relay adds a component to operate and monitor.
- Outbox table growth needs cleanup/archival.
- Exactly-once delivery is not guaranteed; consumers must be idempotent.
- **Service Bus Premium is required for private endpoints.** Standard supports service endpoints/IP firewall but not Private Link. The design keeps Premium to preserve the private data plane; if cost forces Standard, record a deviation that replaces the private endpoint with a service-endpoint + firewall rule set.
- Event schema evolution needs versioning discipline.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Publish directly after commit | Dual-write problem; lost or phantom events |
| Database triggers to call Service Bus | Hard to test, opaque, poor failure handling |
| Event Grid custom topic | Good for reactive Azure events, but Service Bus fits ordered business messaging and DLQ better |
| Kafka/Event Hubs | Higher throughput/streaming, overkill for this workload |

## Review trigger

- Event volume exceeds Service Bus tier limits.
- Need for exactly-once processing or event sourcing.
- Outbox relay lag becomes an SLO risk.
- A standard enterprise event bus is mandated.

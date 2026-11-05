# ADR-0003: AKS for the core API, App Service for the partner webhook

- **Status:** Proposed
- **Date:** 2026-11-03
- **Deciders:** Application platform, security
- **Related:** [Logical architecture](../../diagrams/logical-architecture.png)

## Context

The brief requires both Azure Web Apps and AKS. Using both without a reason creates operational waste. The core inventory/order API needs container portability, internal ingress, pod-level network policy, workload identity, horizontal scaling, and a realistic container supply chain. The partner webhook is low-volume, has a different trust boundary, and benefits from a managed PaaS with deployment slots and a private endpoint.

## Decision

- **AKS** hosts `logistics-api` (FastAPI) with the inventory and order routes, internal NGINX ingress, HPA, PDB, network policy, workload identity, and Key Vault CSI.
- **App Service** hosts `partner-webhook` (FastAPI), a small service that receives carrier delivery-status callbacks and publishes `shipment.updated` events.
- **Azure Functions** handles asynchronous order events and reconciliation.

The split is by operational characteristics and trust boundary, not by technology preference.

## Consequences

### Positive

- Demonstrates a realistic container platform and a managed PaaS path in one project.
- Partner webhook can be scaled and deployed independently.
- App Service slots provide a simple blue/green path for the webhook.
- AKS gives the core API pod-level controls and a portable deployment unit.
- Different blast radii for the public partner surface and the core API.

### Negative / trade-offs

- Two compute platforms to patch, monitor, and pipeline.
- More deployment YAML and more identity assignments.
- App Service VNet integration is outbound only; inbound requires a private endpoint.
- AKS requires node pool capacity planning and cluster upgrades.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Everything on AKS | Meets the brief but loses the App Service learning objective; overkill for a low-volume webhook |
| Everything on App Service | Simpler, but does not demonstrate container supply chain, network policy, or AKS operations |
| Azure Container Apps for both | Good serverless container option, but the brief specifically asks for AKS and Web Apps |
| Functions for the core API | Poor fit for long-running transactional API and container supply chain |

## Review trigger

- Partner webhook volume grows beyond App Service limits.
- AKS operational burden exceeds the team's capacity.
- A platform standard mandates one compute service.

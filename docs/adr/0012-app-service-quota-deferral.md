# ADR-0012: Defer App Service and host the partner webhook on AKS temporarily

- **Status:** Proposed
- **Date:** 2026-11-08
- **Deciders:** Project owner, platform engineering
- **Related:** ADR-0003, [Day 3B guide](../day-03b/README.md), [Project state](../PROJECT-STATE.md)

## Context

The project design uses Azure App Service for the partner webhook because it demonstrates a managed PaaS path with VNet integration and a private endpoint.

The lab subscription has **zero App Service VM quota** in `australiaeast`. The quota increase request was rejected as **ineligible for adjustment**. Changing B1 to S1 does not help: both SKUs require App Service VM quota.

App Service private endpoint and VNet integration require a paid plan. A Free/Shared plan would lose the private endpoint, VNet integration, and the intended security properties.

## Decision

- Keep the App Service Terraform module in the repository, but disable it with `enable_app_service = false`.
- Do not create a public App Service plan as a workaround.
- Host the partner webhook on AKS in a separate namespace for the remainder of the lab.
- Record App Service as a **deferred production gap**, not as completed.
- Re-enable the module only after moving to a subscription with App Service quota.

## Consequences

### Positive

- The private network and zero-trust data plane remain intact.
- The project can continue without a public webhook endpoint.
- The App Service code is preserved for a future subscription.

### Negative / trade-offs

- The “Azure Web Apps” learning objective is deferred.
- The partner webhook shares AKS with the core API; isolation is namespace/network policy, not a separate compute platform.
- A future migration to App Service requires DNS, private endpoint, and deployment changes.
- The five-day scope now has a documented requirement gap.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Public Free/Shared App Service | No private endpoint, no VNet integration, weaker security |
| Different region | VNet integration must be in the same region as the VNet; would require a new network stack |
| Container Apps or Functions | Still not Web Apps; adds a third compute model without solving the requirement |
| Stop the project | Unnecessary; the rest of the platform is still valid |

## Review trigger

- A subscription with App Service quota is available.
- The lab is rebuilt in a region/subscription that supports App Service.
- The partner webhook needs independent scaling or deployment slots.

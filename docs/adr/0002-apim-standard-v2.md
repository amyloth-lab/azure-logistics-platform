# ADR-0002: APIM Standard v2 with private endpoint and outbound VNet integration

- **Status:** Proposed
- **Date:** 2026-11-03
- **Deciders:** Platform engineering, security
- **Related:** [Network design](../day-01/network-design.md), [Identity and RBAC](../day-01/identity-and-rbac.md)

## Context

The API gateway must validate Entra tokens, enforce quotas and rate limits, expose a stable API contract, and reach private backends without exposing them to the internet. The classic APIM Developer tier supports VNet injection but has no SLA and is for non-production. The classic Premium tier supports injection and zone redundancy but is expensive. APIM Standard v2 supports an inbound private endpoint and outbound VNet integration, which fits a production-shaped, cost-conscious design.

## Decision

Use **APIM Standard v2** with:

- An **inbound private endpoint** in the workload VNet (`snet-private-endpoints`) for the gateway.
- An **outbound VNet integration** subnet (`snet-apim-outbound`, delegated to `Microsoft.Web/serverFarms`).
- Public network access **disabled** after the private endpoint is approved.
- A JWT validation policy, per-operation role/scope checks, rate limits, correlation IDs, and backend mTLS.
- App Gateway as the public entry point, routing to the APIM default gateway hostname over the private endpoint.

Do not use classic VNet injection assumptions. Standard v2 does not inject the whole service into the VNet; it uses two separate networking features.

Delegation is tier-specific and is a common review trap:

| Mode | Tier | Subnet delegation |
|---|---|---|
| Classic VNet injection | Developer, Premium | **None** |
| VNet injection | Premium v2 | `Microsoft.ApiManagement/service` |
| Outbound VNet integration | Standard v2 | `Microsoft.Web/serverFarms` |

The `Microsoft.Web/serverFarms` delegation is **required** for Standard v2 outbound integration. It does not mean App Service shares the subnet; the subnet remains dedicated to the APIM instance. Removing it would break the Standard v2 integration. If you switch to classic injection, remove the delegation; if you switch to Premium v2 injection, change it to `Microsoft.ApiManagement/service`.

## Consequences

### Positive

- Private inbound gateway without Premium-tier cost.
- APIM can reach AKS and App Service private endpoints.
- Built-in policy, quotas, analytics, and versioning.
- No public APIM endpoint after configuration.

### Negative / trade-offs

- Standard v2 has feature limits compared with Premium (for example, no multi-region and no availability-zone support).
- Custom domain behavior in v2 tiers requires a publicly resolvable DNS name; the design uses App Gateway for the client-facing domain and APIM's default hostname for the backend.
- Two subnets and a private DNS zone add configuration complexity.
- Public network access can only be disabled after the private endpoint exists; Terraform must order the resources correctly.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| APIM Developer with VNet injection | No SLA; not production-appropriate; different networking model |
| APIM Premium with VNet injection | Strong but expensive for a five-day lab |
| Azure Front Door + APIM | Good global option, but adds cost and another edge layer; App Gateway meets the WAF requirement |
| No APIM, App Gateway directly to AKS | Loses API governance, quotas, and centralized policy |
| APIM Consumption | No VNet injection/private endpoint support for this design |

## Implementation note

Terraform ordering matters: create the APIM instance, the inbound private endpoint, approve it, then disable public network access. The outbound integration requires the delegated `snet-apim-outbound` subnet and an NSG rule that allows outbound 443 to Azure Key Vault. Do not try to model Standard v2 as classic VNet injection.

## Review trigger

- Multi-region or zone-redundant requirement.
- Need for APIM self-hosted gateway or workspaces.
- Custom domain requirement that cannot be met with the App Gateway pattern.
- Traffic volume that exceeds Standard v2 scale limits.

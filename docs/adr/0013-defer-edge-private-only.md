# ADR-0013: Defer the public edge and run the lab APIM private-only

- **Status:** Accepted
- **Date:** 2026-11-09
- **Deciders:** Project owner
- **Related:** ADR-0002, ADR-0003, ADR-0012, [Day 3B guide](../day-03b/README.md), [Project state](../PROJECT-STATE.md)

## Context

The design uses Application Gateway WAF_v2 as the only public application entry point, forwarding to the private APIM gateway.

The subscription has a **3 public IP limit** in `australiaeast`. All three are already used by:

- Azure Firewall data IP
- Azure Firewall management IP
- Azure Bastion IP

App Gateway needs a fourth public IP. The public IP quota increase is not available for this lab, and deleting the firewall or Bastion IP is not acceptable.

App Service is also blocked by an unrelated zero App Service VM quota (ADR-0012).

## Decision

- Keep the App Gateway Terraform module in the repository, but disable it with `enable_app_gateway = false`.
- Do not create a public IP, public listener, or WAF for the lab.
- Keep APIM private-only, reachable only through the private endpoint and private DNS.
- Demonstrate the API from inside the workload network:
  - `az aks command invoke` from AKS, or
  - a Bastion-connected management VM.
- Record the missing edge and WAF as a production gap.
- Do not expose APIM publicly to compensate.

## Consequences

### Positive

- No new public attack surface.
- The private APIM, private AKS, private data services, and zero-trust service-to-service path remain intact.
- The lab can continue without deleting firewall or Bastion controls.
- The App Gateway code is preserved for a subscription with public IP quota.

### Negative / trade-offs

- No public API endpoint and no external partner webhook reachability.
- No WAF inspection, TLS termination, or edge routing demonstration.
- The “Application Gateway WAF_v2” learning objective is deferred.
- A production deployment cannot accept external traffic until the edge is restored.
- The lab demo must be run from inside the network.

## Production remediation

Choose one when quota or architecture allows:

1. Request a public IP quota increase to at least 4 and enable the existing App Gateway module.
2. Use Azure Front Door with APIM as a private origin, accepting the edge/WAF product change.
3. Move to a subscription with public IP quota and deploy the original App Gateway design.

Do not remove Azure Firewall or Bastion to free a public IP. Both are security controls.

## Review trigger

- Public IP quota becomes available.
- The project needs an external partner integration.
- The lab is rebuilt in a subscription with sufficient public IP quota.

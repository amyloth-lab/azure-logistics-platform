# ADR-0015: Temporarily enable ACR public access for hosted build agents

- **Status:** Accepted (temporary lab exception)
- **Date:** 2026-11-09
- **Deciders:** Project owner
- **Related:** ADR-0003, [Day 4 guide](../day-04/README.md), [Project state](../PROJECT-STATE.md)

## Context

The ACR is Premium with a private endpoint and public network access disabled.

Azure DevOps uses a Microsoft-hosted Ubuntu agent for the build pipeline. That agent runs outside the lab VNet, so it cannot resolve or reach the ACR private endpoint. `az acr login` and `docker push` fail with a 403 / connectivity error even when the service connection has AcrPush.

ACR Tasks is also not permitted for this subscription (`TasksOperationsNotAllowed`), so the remote-build path is unavailable.

## Decision

- Temporarily set `acr_public_network_access_enabled = true`.
- Keep the private endpoint and private DNS in place for in-VNet consumers.
- Keep the ACR admin user disabled.
- Grant the build service connection identity **AcrPush** on the ACR.
- Build locally on the hosted agent and push to the public ACR endpoint.
- Document this as a lab-only exception, not the production design.

## Consequences

### Positive

- The hosted build pipeline can authenticate and push.
- The ACR remains reachable privately from AKS and other VNet resources.
- No ACR admin credentials or stored registry password are introduced.

### Negative / trade-offs

- The registry data plane is reachable from the public internet.
- Authentication is still Entra-based, but the network exposure is broader than the original zero-trust design.
- A production deployment must use a self-hosted agent inside the VNet or another private build path.

## Remediation

1. Deploy a self-hosted Azure DevOps agent in the workload/management VNet.
2. Set `acr_public_network_access_enabled = false`.
3. Run the build from the private agent.
4. Keep AcrPush scoped to the ACR.

Do not enable the ACR admin user as a workaround.

## Review trigger

- The build moves to a VNet-hosted agent.
- The lab ends and public access should be removed.
- A security review requires the original private-only registry.

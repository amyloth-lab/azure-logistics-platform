# ADR-0007: Terraform remote state in Blob with Entra auth and lease locking

- **Status:** Proposed
- **Date:** 2026-11-03
- **Deciders:** Platform engineering, security
- **Related:** [Identity and RBAC](../day-01/identity-and-rbac.md), [Plan of action](../day-01/plan-of-action.md)

## Context

Terraform state contains resource IDs, IP addresses, and sometimes sensitive values. Local state cannot be shared safely, has no locking, and is easy to lose. The team wants a production-shaped backend with least privilege, encryption, versioning, and recovery.

## Decision

Use an Azure Storage account and Blob container as the Terraform backend:

- Dedicated resource group `rg-logistics-tfstate`.
- Storage account with TLS 1.2, public network access disabled after bootstrap, shared key access disabled, Entra-only auth.
- Private endpoint in the management VNet; private DNS `privatelink.blob.core.windows.net`.
- Container `tfstate`; one state key per environment and stack (`dev/network.tfstate`, `dev/hub.tfstate`, `prod/...`).
- Enable blob versioning, soft delete (30 days in the lab, 90 in production), change feed, and an immutable policy where operationally feasible.
- State locking via Blob lease.
- The deployer/release identity gets `Storage Blob Data Contributor` on the state storage account/container; no broader subscription data-plane role.
- Bootstrap with a small Terraform stack using local state, then migrate that state into the Blob backend. Do not leave the bootstrap state local.
- Backend configuration uses `use_azuread_auth = true`; no storage account keys.
- CI runs `terraform plan` with `-lock=false` only for read-only plan jobs; apply uses the lock.

**Bootstrap exception:** the state storage is created before the management VNet and private endpoint exist. Until Day 3 creates the private endpoint, the storage account keeps a public endpoint with `default_action = "Deny"`, an IP allow-list containing only the deployer's public IP, Entra-only auth, and shared keys disabled. This is a time-boxed exception, not the target state. Day 3 adds the private endpoint, links `privatelink.blob.core.windows.net`, and disables public network access.

## Consequences

### Positive

- Shared, durable state with locking.
- Entra-only access; no storage keys in pipeline variables.
- Versioning and soft delete support recovery from accidental state damage.
- Private endpoint keeps state traffic off the public internet.
- Separate state keys reduce blast radius between environments/stacks.

### Negative / trade-offs

- Bootstrap is a chicken-and-egg problem; the state storage cannot be fully managed by the state it stores.
- Private endpoint and DNS add setup complexity.
- State can still contain sensitive values; access must be tightly controlled.
- Blob lease locking can leave a stale lease after a crashed apply; operators need a safe recovery procedure.
- Immutable policy can interfere with legitimate state recovery; test the policy before enabling.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Local state | No locking, no sharing, easy loss |
| Terraform Cloud/Enterprise | Good option, but adds a vendor and cost; not needed for this course |
| Azure DevOps-hosted state | Not a native Terraform backend; custom tooling required |
| Storage account with shared key | Simpler, but long-lived keys violate the no-secret rule |

## Review trigger

- Team grows beyond a few concurrent operators.
- Need for policy-as-code enforcement on state access.
- State contains regulated data that requires additional controls.
- Migration to Terraform Cloud or another managed backend.

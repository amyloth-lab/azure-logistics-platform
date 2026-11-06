# Architecture Decision Records

An ADR captures a decision that is expensive to reverse, the context at the time, and the consequences. It is not a design document and it is not a vote. It is a durable record so the next engineer does not have to guess why the platform looks the way it does.

**Status values:** Proposed -> Accepted -> Superseded / Deprecated

Most ADRs below are **Proposed** on Day 1. Mark them **Accepted** after your architecture review, or change them before you write Terraform. ADR-0011 is **Accepted** because the Entra ID Free license is a fixed project constraint. If a decision changes during the week, update the ADR in the same pull request as the code.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-hub-and-spoke-network.md) | Hub-and-spoke network with centralized egress | Proposed |
| [0002](0002-apim-standard-v2.md) | APIM Standard v2 with private endpoint and outbound VNet integration | Proposed |
| [0003](0003-aks-core-app-service-partner.md) | AKS for the core API, App Service for the partner webhook | Proposed |
| [0004](0004-azure-sql.md) | Azure SQL Database as the transactional store | Proposed |
| [0005](0005-managed-redis.md) | Azure Managed Redis for cache and idempotency | Proposed |
| [0006](0006-service-bus-functions-outbox.md) | Service Bus + Functions with a transactional outbox | Proposed |
| [0007](0007-terraform-remote-state.md) | Terraform remote state in Blob with Entra auth and lease locking | Proposed |
| [0008](0008-ansible-scope.md) | Ansible for Linux/agent hardening and Kubernetes baseline | Proposed |
| [0009](0009-build-release-separation.md) | Separate build and release pipelines and identities | Proposed |
| [0010](0010-authn-authz-separation.md) | Authentication and authorization are separate concerns | Proposed |
| [0011](0011-entra-id-free-license.md) | Operate with Microsoft Entra ID Free and compensating controls | Accepted |

## Writing a new ADR

1. Copy the structure from an existing ADR.
2. Number it sequentially; never reuse a number.
3. State the context and the forces, not just the answer.
4. List at least two alternatives and why they were rejected.
5. Record the negative consequences. An ADR with no downsides is marketing.
6. Link the Terraform module, pipeline, or code that implements it.
7. Review the ADR when the trigger condition occurs, not on a fixed calendar.

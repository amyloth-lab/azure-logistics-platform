# Interview brief — Azure logistics platform

This is the honest version of the project: what was delivered, what was deferred because of subscription and Entra Free limits, and how to explain the trade-offs clearly.

---

## 1. The 60-second explanation

> I built a private, hub-and-spoke Azure platform for a Python logistics API with inventory and orders. The API runs on private AKS, is published only through a private APIM endpoint, and uses Entra ID tokens with app-role authorization. Data services — Azure SQL, Blob Storage, Service Bus, Managed Redis, Key Vault, and ACR — are private. Terraform creates the platform; Helm configures the Kubernetes workload. Ansible was planned for host configuration but was deferred by vCPU quota, so I do not claim it was executed. The build is separated from release: the build pipeline tests, scans, and pushes an immutable image digest; the release pipeline deploys that same digest and smoke-tests it.
>
> The lab subscription had hard limits: zero App Service quota, three public IPs, and four regional vCPUs. I did not fake those services. I deferred App Service, the public WAF edge, and the Ansible VM with ADRs, kept the private security model intact, and documented exactly what a production subscription would need.

---

## 2. Architecture in plain English

Think of the platform as an office building:

- The **hub** is the main security gate. All spokes connect to it.
- The **spokes** are separate departments: ingress, workload, data, management.
- **Azure Firewall** is the security guard checking traffic between departments and the internet.
- **Bastion** is the supervised visitor entrance for administrators. There are no public SSH ports.
- **Private endpoints** are private doors into Azure services. The service has no public front door.
- **APIM** is the receptionist: it receives API calls, checks identity, applies policy, and forwards to the API.
- **AKS** is the factory floor where the API containers run.
- **Service Bus** is the internal mailroom: reliable messages between order processing and downstream workers.
- **Terraform** is the blueprint; **Terraform state** is the as-built ledger.
- **Entra ID** is the company badge system. A **managed identity** is a badge issued to a workload so it never needs a password.
- **RBAC** is the set of keys: which badge can open which door.

### Network layout

| Spoke | CIDR | Purpose |
|---|---|---|
| Hub | `10.0.0.0/16` | Firewall, Bastion, shared DNS |
| Ingress | `10.1.0.0/16` | App Gateway subnet (deferred) |
| Workload | `10.2.0.0/16` | AKS, APIM, App Service/Functions subnets |
| Data | `10.3.0.0/16` | SQL, Storage, Service Bus, Redis, Key Vault private endpoints |
| Management | `10.4.0.0/16` | ACR, Terraform state, management private endpoints |

AKS uses Azure CNI Overlay:

```text
pods     100.64.0.0/16
services 10.60.0.0/16
DNS      10.60.0.10
```

Every spoke is peered to the hub. Route tables send `0.0.0.0/0` to Azure Firewall. Private DNS zones are linked to the hub and spokes, so private endpoints resolve to private IPs.

### Request path that actually works

```text
internal client / AKS pod
  -> APIM private endpoint
  -> APIM outbound integration
  -> AKS internal LoadBalancer 10.2.12.10:80
  -> FastAPI pod
  -> Azure SQL private endpoint (10.3.1.x:1433)
```

There is **no public API endpoint**. The public App Gateway/WAF edge was deferred.

### Delivery path

```text
GitHub
  -> Azure DevOps build
     -> tests, Ruff, pip-audit, Bandit, Gitleaks
     -> docker build
     -> Trivy
     -> ACR immutable digest
  -> Azure DevOps release
     -> same digest
     -> Helm into private AKS
     -> migration Job
     -> APIM smoke test
```

---

## 3. Why these services

### Why AKS instead of only App Service?

The API is a containerized Python service that needs private networking, workload identity, scaling, and a clean path to private data services. AKS provides that and avoids exposing the API publicly. App Service was intended for the partner webhook, but the subscription had zero App Service VM quota.

### Why APIM?

APIM gives one controlled API front door: private inbound endpoint, outbound VNet integration, future JWT policy, quotas, and a single place to add WAF/edge later. Directly exposing the AKS internal load balancer would bypass API governance.

### Why Service Bus?

Orders are business events. They need reliable delivery, retries, dead-lettering, and multiple consumers. HTTP calls are a poor fit for that. Service Bus decouples the order API from inventory, audit, and partner processing.

### Why Terraform?

The platform has many dependent resources — VNets, peerings, DNS links, private endpoints, role assignments, AKS, APIM. Terraform makes the order repeatable and reviewable. The state file is the source of truth for what exists.

### Why Ansible?

The original design used an Ansible control VM for host hardening and Kubernetes baseline. It was deferred because the region had no free vCPU quota. Helm and AKS run command were used instead. I do not claim Ansible was executed.

---

## 4. Challenges and how they were overcome

Some of these are Entra Free limits. Some are subscription quotas. Some are ordinary engineering failures. The distinction matters in an interview.

| Challenge | Root cause | Resolution | Lesson |
|---|---|---|---|
| No Conditional Access, PIM, access reviews, ID Protection | Entra ID Free licence | Security Defaults, separate admin accounts, manual JIT, quarterly manual reviews, app roles, workload identity | Licence gaps must be documented, not hand-waved |
| App Service could not be created | App Service VM quota was 0 and the increase was ineligible | Deferred App Service and partner webhook; ADR-0012 | Check quotas before designing a service |
| No public WAF edge | Subscription allowed 3 public IPs; firewall data, firewall management, and Bastion used all 3 | Deferred App Gateway; APIM private-only; ADR-0013 | Public IP is a design constraint, not an afterthought |
| No Ansible VM | 4/4 Total Regional Cores used by AKS; VM needed 2 | Deferred Ansible; ADR-0014 | A smaller VM does not help at zero free cores |
| ACR Tasks not permitted | Subscription returned `TasksOperationsNotAllowed` | Local `docker build` + `docker push` | Do not depend on a service the subscription forbids |
| Hosted agent could not reach private ACR | Private endpoint only; Microsoft-hosted agent is outside the VNet | Temporary ACR public access with ADR-0015; production fix is a VNet self-hosted agent | Private endpoints and hosted build agents are often incompatible |
| APIM Standard v2 outbound integration failed | `virtualNetworkType=None` is invalid with a subnet | Set `External` for Standard v2 outbound integration | Provider/API behavior must be tested, not guessed |
| APIM private endpoint failed | Private Link group ID is case-sensitive | Used `Gateway`, not `gateway` | Small casing issues cause long debugging sessions |
| AKS `Forbidden: nodes` | Entra authentication worked, but no Kubernetes RBAC role | Granted `Azure Kubernetes Service RBAC Cluster Admin` to the admin user | Authentication and authorization are separate |
| Function VNet integration failed | Flex Consumption requires `Microsoft.App/environments` delegation, not `Microsoft.Web/serverFarms` | Changed the functions subnet delegation; registered `Microsoft.App` | Each PaaS has its own subnet rules |
| AKS could not pull from ACR | Firewall blocked AKS → ACR private endpoint | Added `acr-private-endpoint` rule for `10.2.0.0/16` → `10.4.2.0/24:443` | A private endpoint is useless without the network path |
| SQL login timed out | Firewall blocked AKS → SQL private endpoint | Added `sql-private-endpoint` rule for `10.2.0.0/16` → `10.3.1.0/24:1433` | Build a private-endpoint traffic matrix early |
| Pod `CreateContainerConfigError` | `runAsNonRoot` with a non-numeric image user | Numeric UID/GID `10001:10001` in image and Helm | Kubernetes cannot verify a username |
| Migration Job `ModuleNotFoundError: pyodbc` | `pyproject.toml` and `app/db.py` were not committed; pipeline built old code | Committed dependencies; Dockerfile now fails build if imports fail | The pipeline builds Git, not your laptop |
| pyodbc `FA005` with access token | SQLAlchemy pyodbc dialect added `Trusted_Connection=Yes` when no user was present | Built an explicit ODBC string and used a connection creator with only the access-token attribute | Know what your ORM generates |
| Helm `--atomic` hid the real error | Failed hook caused rollback and no release | Deployed without atomic, inspected Job logs, then fixed | Do not use atomic until the first install is understood |
| Trivy zlib CVEs | Base image OS packages were stale | Runtime image upgrades `zlib1g` from Debian security | Rebuild base images regularly |
| pytest PYSEC-2026-1845 | pytest 8.4.2 was vulnerable | Pinned `pytest>=9.0.3`; removed unused pytest-asyncio | Security scanning applies to dev dependencies too |
| Azure CLI could not get a custom API token | Azure CLI app has no permission for an arbitrary custom API | Added a dedicated public client and MSAL device-code flow | Do not use Azure CLI as the client for every custom API |
| Entra sign-in 530035 | Personal/guest account or device policy | Used a tenant member account; checked sign-in logs | Identity errors are often tenant-boundary problems, not app bugs |

---

## 5. Service Bus — use case and why

### What it is

Service Bus is a reliable message queue/topic service. A producer sends a message; one or more consumers process it later. If a consumer fails, the message is retried and eventually moved to a dead-letter queue.

### Use case in this project

When an order is created or changed:

1. The API writes the order to SQL.
2. It publishes an `OrderCreated` or `OrderUpdated` event to the `orders` topic.
3. The `order-processor` subscription reserves inventory.
4. The `order-audit` subscription writes an audit record.
5. A Functions consumer can notify the partner or reconcile failures.
6. Failed messages retry up to 10 times and then go to the DLQ.

The Terraform creates the namespace, topics (`orders`, `inventory`, `shipments`), and subscriptions (`order-processor`, `order-audit`). The application producer/consumer code is not yet implemented; the infrastructure and design are in place. Do not claim an end-to-end event flow that was not exercised.

### Why Service Bus rather than alternatives?

| Option | Why not the primary choice |
|---|---|
| Event Grid | Good for reactive Azure resource events; weaker fit for business order messages with strong retry/DLQ semantics |
| Storage Queue | Simple and cheap, but no topics/subscriptions for multiple independent consumers |
| Direct HTTP call | Couples services, no buffering, no DLQ, caller must handle every retry |
| Event Hubs | Designed for high-volume telemetry/streaming, not per-order business workflow |

### Why Premium?

Private endpoints for Service Bus require the Premium tier. Standard would have required service endpoints and a weaker network design. That is a cost trade-off, not a Free-tier limitation.

### Reliability features

- Topics and subscriptions for multiple consumers.
- `max_delivery_count = 10`.
- Dead-letter queue for poison messages.
- Managed identity sender/receiver roles.
- Private endpoint and private DNS.

Not yet implemented: outbox table, idempotency keys, duplicate detection, and the actual producer/consumer code.

---

## 6. AKS architecture and why it matters

### What was built

- Private API server; no public FQDN.
- System node pool for AKS components.
- User node pool for application workloads.
- Azure CNI Overlay.
- Azure network policy enabled.
- UDR to Azure Firewall.
- OIDC issuer and workload identity enabled.
- Entra RBAC; local accounts disabled.
- Kubelet identity has `AcrPull`.
- AKS identity has `Network Contributor` on the workload VNet and `Private DNS Zone Contributor` on the AKS private DNS zone.
- Internal LoadBalancer Service for the API at `10.2.12.10`.
- Helm deployment and migration Job.
- No public node IPs.

### Why it matters

- **Isolation:** the API is not reachable from the internet.
- **Identity:** pods use workload identity, not stored secrets.
- **Control:** firewall and NSGs govern east-west and egress traffic.
- **Portability:** the same container can run in another cluster.
- **Scaling:** node pools and replicas can grow independently.
- **Governance:** Entra RBAC, Azure Policy, and private DNS apply consistently.

### Traffic flow

```text
APIM outbound VNet integration
  -> internal LoadBalancer 10.2.12.10
  -> Kubernetes Service
  -> FastAPI pod
  -> SQL/Redis/Blob/Service Bus private endpoints
```

### What I would improve in production

- Use a dedicated ingress controller with TLS instead of a raw internal LoadBalancer.
- Add NetworkPolicy manifests; enabling the policy engine alone is not enough.
- Add HPA and cluster autoscaler policies.
- Use a private AKS node pool with no public egress except firewall.
- Add Pod Security Standards and admission policies.
- Add multi-zone node pools and a disaster-recovery region.

---

## 7. Security best practices

### 7.1 Identity

- Entra ID is the identity provider.
- Users authenticate and receive a JWT access token.
- The API validates signature, issuer, audience, expiry, tenant, object ID, and app roles.
- App roles:
  - `Inventory.Reader`
  - `Inventory.Contributor`
  - `Order.Reader`
  - `Order.Contributor`
  - `Logistics.Manager`
  - `Partner.Webhook`
- Manager-only deletes.
- Normal users can only read/update their own orders; another user's order returns `404` to avoid leaking existence.
- The API validates tokens even though APIM will also validate them later. Defense in depth.

### 7.2 Why managed identity instead of a service principal secret?

A **service principal** is an app identity with a credential — often a secret. A **managed identity** is an identity whose credential Azure manages. A **workload identity** federates a Kubernetes service account to a user-assigned managed identity using OIDC, so the pod gets a short-lived token and no secret is stored.

Used here:

| Workload | Identity | Why |
|---|---|---|
| FastAPI pods | User-assigned managed identity + AKS federated credential | No SQL/Blob/Service Bus password in the image or Helm values |
| Function App | User-assigned managed identity | Private storage and Service Bus access without keys |
| AKS kubelet | Managed identity | Pull images from ACR |
| Terraform | Entra user/service principal via Azure CLI | Create infrastructure with Entra auth |
| Azure DevOps build | Service connection app registration with AcrPush | Push images only |
| Azure DevOps release | Separate service connection + AKS roles | Deploy only; no ACR push |

A service principal with a secret would work, but it creates rotation and leakage risk. Managed identity removes the secret. The trade-off is that identity-to-resource role assignments and federated credentials must be correct.

### 7.3 RBAC map

| Scope | Principal | Role | Purpose |
|---|---|---|---|
| ACR | AKS kubelet identity | `AcrPull` | Pull images |
| ACR | Build service connection | `AcrPush` | Push images |
| AKS cluster | Human admin | `Azure Kubernetes Service RBAC Cluster Admin` | `kubectl`/run command |
| AKS cluster | Release service connection | `Azure Kubernetes Service Cluster Admin Role` | `az aks command invoke` |
| AKS cluster | Release service connection | `Azure Kubernetes Service RBAC Cluster Admin` | Helm/kubectl inside command |
| Workload VNet | AKS identity | `Network Contributor` | Join subnets/load balancer |
| AKS private DNS zone | AKS identity | `Private DNS Zone Contributor` | Manage private API DNS |
| Storage account | API/Function identity | `Storage Blob Data Contributor` | Blob access |
| Service Bus namespace | API identity | `Azure Service Bus Data Sender` / `Receiver` | Publish/consume |
| Service Bus namespace | Function identity | `Azure Service Bus Data Receiver` | Consume events |
| Azure SQL | API identity | Contained user with `db_datareader`, `db_datawriter` | Data access |
| Key Vault | Human/ops | RBAC data-plane roles | Secret/cert management |
| Terraform state storage | Platform engineers | Blob data contributor | Read/write state |

The principle: give each identity the smallest scope and role for its job. The build identity cannot deploy. The release identity cannot push images. The API identity cannot manage Azure resources.

### 7.4 Network security

- Hub-and-spoke with firewall-forced egress.
- No public IP on AKS nodes, APIM, SQL, Storage, Service Bus, Redis, Key Vault, or ACR private endpoint.
- Private endpoints and private DNS for all data services.
- NSGs on subnets.
- UDR to Azure Firewall.
- Bastion for administrative access; no public SSH/RDP.
- Firewall rules for AKS → ACR and AKS → SQL private endpoints.
- ACR public access is a **temporary** exception for hosted build agents; the private endpoint remains.

### 7.5 Data protection

- Azure SQL: Entra-only authentication; no SQL password.
- Storage: shared key disabled; Entra/RBAC access.
- ACR: admin user disabled.
- Key Vault: RBAC, purge protection, public access disabled, private endpoint.
- Service Bus: Premium, private endpoint, managed identity.
- Managed Redis: encrypted client protocol, access keys disabled, Entra authentication.
- TLS 1.2+ where configured.
- Secrets are not in Git or Helm values; workload identity and Key Vault are the pattern.

### 7.6 Supply chain and CI/CD

Implemented:

- Pull-request build pipeline.
- `pytest` (18 tests), Ruff.
- `pip-audit` against a frozen requirements file.
- Bandit source scan.
- Gitleaks secret scan.
- Docker multi-stage build, non-root numeric UID.
- Trivy image scan.
- Immutable image digest.
- Build identity with AcrPush only.
- Separate release identity.
- Tag-triggered release with environment approval.
- Helm `--atomic` for releases after the first install.
- Smoke test through private APIM.

Not yet implemented:

- Image signing (cosign/Notation).
- SBOM generation/attestation.
- Checkov/tflint in the pipeline.
- DAST.
- Dependency lock file beyond the pipeline freeze.
- Signed commits/branch protection as code.

### 7.7 Monitoring and operations

- Log Analytics workspace and AKS OMS agent.
- Runbook for health, rollback, migration failure, APIM, AKS, SQL restore, key rotation, cost, cleanup.
- Cost stop/start scripts.
- Known gap: alert coverage is not as mature as a production platform.

### 7.8 Postmortem — what went wrong and what it taught

The project had a series of real failures. A good interview answer explains the root cause, fix, and prevention, not just the final success.

| Incident | Root cause | Fix | Prevention |
|---|---|---|---|
| ACR Tasks forbidden | Subscription restriction | Local Docker build/push | Validate service availability first |
| Private ACR unreachable from hosted agent | Network boundary | Temporary public access + ADR; future self-hosted agent | Design build network with private endpoints |
| AKS image pull EOF | Firewall missing ACR rule | Added 10.2 → 10.4.2:443 | Build a complete private-endpoint traffic matrix |
| SQL login timeout | Firewall missing SQL rule | Added 10.2 → 10.3.1:1433 | Test each private endpoint from the workload |
| Missing pyodbc | Uncommitted dependency | Committed pyproject/Dockerfile; build-time import check | Pipeline builds Git; commit before build |
| FA005 token error | SQLAlchemy added Trusted_Connection | Explicit ODBC string + creator | Do not let the ORM silently choose auth mode |
| CreateContainerConfigError | Non-numeric image user | UID/GID 10001 | Numeric users in hardened images |
| Helm atomic hid failure | Rollback removed resources | Deploy without atomic, read Job logs | Use atomic only after a known-good install |
| 530035 sign-in | Tenant boundary/device policy | Member account; sign-in log analysis | Identity errors are not always app errors |
| App Service quota | Subscription limit | Deferred with ADR | Check quotas before design |

The biggest lesson: **private networking is not “create a private endpoint.” It is DNS + route + firewall + identity + role assignment, all tested from the workload.**

---

## 8. Security features that could have been added

Apart from Entra ID P1/P2, these are the main missing production controls.

### Identity and access

- Conditional Access (requires P1)
- PIM (requires P2)
- Access reviews (requires P1/P2)
- ID Protection (requires P2)
- Entra Password Protection
- Continuous Access Evaluation
- Token protection
- Named locations
- Break-glass accounts with monitoring

### Network and edge

- Application Gateway WAF_v2 (deferred)
- Azure Firewall Premium with IDPS and TLS inspection
- DDoS Protection Standard
- Azure Front Door with WAF and private origin
- Private Link for all supported services
- Network security groups with deny-by-default and flow logs
- Kubernetes NetworkPolicy objects
- Service mesh mTLS
- Egress restriction to an explicit allowlist

### Data

- Customer-managed keys for SQL, Storage, and ACR
- SQL auditing and advanced threat protection
- Microsoft Defender for SQL
- Microsoft Defender for Storage
- Key Vault HSM-backed keys
- Key Vault CSI driver for pod secrets
- Backup and restore testing
- Data classification and retention policies

### Containers and supply chain

- Microsoft Defender for Containers
- Image signing and verification
- SBOM generation and attestation
- Admission control to allow only signed images
- Pod Security Standards
- Runtime threat detection
- Dependency and base-image update automation
- Separate prod ACR with replication
- Checkov/tflint in CI
- DAST and API fuzzing

### Operations

- Microsoft Sentinel SIEM
- Central alerting and on-call
- Multi-region disaster recovery
- RTO/RPO testing
- Chaos testing
- Cost anomaly alerts
- Policy-as-code enforcement
- Regular penetration testing and threat modeling

The interview-safe statement is: **the core private identity and network controls are real; the premium governance, WAF, SIEM, and supply-chain controls are documented as production backlog, not claimed as delivered.**

---

## 9. Terraform state and repository with multiple engineers

### State

Use one remote state per environment:

```text
storage account: private, no public access
container:       tfstate
key:             dev/hub.tfstate
```

The backend uses Entra authentication, not storage keys:

```hcl
use_azuread_auth = true
```

Blob lease provides locking, so two engineers cannot apply at the same time.

State storage should have:

- Versioning.
- Soft delete.
- Private endpoint.
- RBAC limited to platform engineers and the pipeline identity.
- Diagnostic logs.
- Separate state per environment/subscription.

Never commit state, plans, `.tfvars`, backend config, or certificates. State can contain sensitive values.

### Repository workflow

- Trunk-based development with short-lived feature branches.
- Pull request required; at least one reviewer.
- `CODEOWNERS` for network, identity, and data modules.
- Required checks:
  - `terraform fmt -check`
  - `terraform validate`
  - `tflint`
  - Checkov
  - Python tests/Ruff
  - secret scan
- Plan on PR with a read-only identity; apply only from `main` through the pipeline.
- Environment approvals for prod.
- Lock file committed; provider upgrades via PR.
- Modules versioned by tag.
- ADRs for decisions and deviations.
- No manual portal changes; import drift or fix code.

### Multiple engineers in practice

1. Engineer opens PR.
2. CI runs format, validate, lint, security, and `terraform plan`.
3. Reviewer checks plan and architecture.
4. Merge to `main`.
5. Pipeline applies with a privileged identity.
6. State lock prevents concurrent applies.
7. Drift detection runs on a schedule.
8. Break-glass state operations are reviewed and logged.

For larger teams, use Terragrunt/Atlantis/Spacelift or a platform team that owns shared modules.

---

## 10. Other interview questions to prepare

### “Why not put the API directly behind App Gateway?”

App Gateway was the original plan, but the subscription had no public IP left. APIM already provides a private API front door. Adding a public edge without a public IP was impossible.

### “Why not expose APIM publicly?”

That would discard the private-by-design control and create an internet-facing API without the WAF that was deferred. The safer choice was a private lab demo with an explicit gap.

### “Why use both APIM and FastAPI authorization?”

APIM will eventually reject unauthenticated traffic at the edge. FastAPI still needs resource-level authorization because APIM does not know whether user A owns order B. Defense in depth.

### “How does AKS pull from a private ACR?”

The kubelet identity has `AcrPull`; the ACR private endpoint is in the management VNet; private DNS resolves the registry name; the firewall allows AKS → ACR on 443. All four must be correct.

### “How does APIM reach AKS?”

APIM has outbound VNet integration; the API Service is an internal LoadBalancer at `10.2.12.10`; APIM’s backend URL points there. There is no public hop.

### “Why not use service endpoints instead of private endpoints?”

Service endpoints keep traffic on the Azure backbone but the service still has a public endpoint. Private endpoints remove the public data plane and support private DNS. The project chose private endpoints.

### “How do you rotate secrets?”

There are almost no application secrets. Managed identities and federated credentials remove static credentials. Certificates and any remaining secrets live in Key Vault and are rotated there.

### “How would you scale this?”

- HPA for pods, cluster autoscaler for nodes.
- APIM scaling/quotas.
- SQL serverless or higher tier.
- Service Bus Premium messaging units.
- Redis scale.
- Multi-zone node pools.
- Multi-region is not implemented.

### “What is the disaster recovery plan?”

Current lab is single-region. Production would need:

- RTO/RPO defined.
- SQL geo-restore/failover group.
- ACR geo-replication.
- Secondary AKS or paired region.
- DNS failover.
- Tested restore and runbooks.

This is a documented gap, not a completed feature.

### “What would you do differently?”

- Build the private-endpoint traffic matrix before deploying workloads.
- Commit dependencies before building images.
- Use a VNet self-hosted agent from day one.
- Add Alembic migrations instead of `create_all`.
- Add NetworkPolicy manifests, not just enable the policy engine.
- Add WAF/edge earlier if public IP quota existed.
- Use a separate prod subscription and identity from the start.

### “What are you most proud of?”

The private path actually works end to end: AKS pulls from private ACR, APIM reaches the internal API, SQL authenticates with a managed identity, and the release deploys an immutable digest. The failures were documented and fixed rather than hidden.

### “What is not production-ready?”

Say it clearly:

- No public WAF edge.
- No App Service/partner webhook.
- No Ansible execution.
- No Alembic migrations.
- Redis Entra integration incomplete.
- APIM JWT policy not added.
- No separate prod stack.
- Limited alerting.
- ACR public access temporary.
- Single region.

---

## 11. Layman glossary for non-technical interviewers

| Term | Plain meaning |
|---|---|
| Hub-and-spoke | A central security gate with separate departments connected to it |
| Private endpoint | A private door to an Azure service; no public front door |
| Private DNS | An internal phone book that gives the private door’s address |
| Managed identity | An automatic ID badge for a workload; no password to steal |
| Service principal | A robot employee badge used by automation |
| RBAC | Which badge can open which door |
| JWT | A signed visitor pass that the API can verify |
| APIM | The receptionist that checks passes and forwards requests |
| AKS | The factory floor where containers run |
| Service Bus | The mailroom that holds messages until workers process them |
| Terraform | The blueprint for the building |
| Terraform state | The as-built ledger of what exists |
| Immutable digest | A fingerprint of an image that cannot be changed |
| WAF | A security guard for web traffic |
| Bastion | A supervised entrance for administrators |

---

## 12. What not to claim

Do not say:

- App Service is deployed.
- The partner webhook exists.
- WAF/App Gateway protects a public endpoint.
- Ansible was executed.
- A separate production deployment exists.
- APIM is publicly reachable.
- ACR is private-only while the public-access exception is active.
- Service Bus producer/consumer code is complete.
- Alembic migrations are implemented.

The strongest interview position is:

> “I delivered the private core, proved the end-to-end path, documented every constraint, and left a clear production backlog. I did not pretend the deferred pieces were done.”

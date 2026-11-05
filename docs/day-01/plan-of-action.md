# Plan of Action - Five Days, One Vertical Slice, Production Habits

**Audience:** A DevOps engineer in their first role, working 4-5 focused hours per day
**Goal:** Build a working, production-shaped logistics API platform, not a slide deck
**Rule:** Each day ends with evidence and a commit. The next day starts only after the previous day's exit criteria are met.

---

## 1. How a DevOps engineer would approach this project

A first-job DevOps engineer often starts with Terraform because it feels productive. A senior engineer starts with **constraints and decisions**:

1. **Clarify the outcome.** Two APIs, authenticated users, manager-only deletes, private data, separate build/release.
2. **Find the hard constraints.** Region, budget, Entra licenses, on-prem CIDRs, compliance, team skills, delivery date.
3. **Draw the boundaries.** Network, identity, data, deployment, operations.
4. **Make irreversible decisions early.** CIDRs, subscription model, state backend, domain, SKU tiers.
5. **Build a thin vertical slice.** One endpoint, one database table, one token, one pipeline, one log query. Then widen.
6. **Automate the guardrails before the workloads.** Policy, state locking, secret scanning, private DNS, least-privilege identities.
7. **Separate build from release.** Different questions, identities, permissions, and approvals.
8. **Design for failure.** What happens when the broker is down, the pod crashes, the certificate expires, or the pipeline is compromised?
9. **Make it observable.** If you cannot see it, you cannot operate it.
10. **Write down the decision and the gap.** ADRs and a runbook are part of the deliverable.

This course is structured to force those habits. Day 1 is design. Day 2 is the secure foundation. Day 3 is the platform. Day 4 is the application and build. Day 5 is release and operations.

### 1.1 Agile operating model in Azure Boards

Use a one-week sprint, but do not pretend a 48-item backlog fits into 22.5 hours. The CSV is a **course map**. Pull only the Day 1 stories and a small buffer into `Sprint 1`; keep the rest in the backlog or a second sprint.

| Agile element | How to use it here |
|---|---|
| Epic | A major capability, such as "Platform foundation" or "CI/CD" |
| Feature | A deliverable slice under an epic, such as "Private DNS and private endpoints" |
| User Story | A demonstrable outcome, such as "Manager can delete an order with an audit record" |
| Task | A small implementation step, usually less than 4 hours |
| Sprint goal | "A secure dev vertical slice: authenticated inventory/order APIs behind WAF/APIM, with a gated release path" |
| Capacity | 4.5 hours/day x 5 days = 22.5 hours; plan ~20 hours and keep 10% buffer |
| Board columns | `New` -> `Active` -> `Review` -> `Done`; WIP limits 3 and 2 |
| Daily standup | 15 minutes: yesterday, today, blockers, risk to the sprint goal |
| Sprint review | Demo the working API, RBAC, event, pipeline, and logs, not a slide deck |
| Retrospective | What slowed us down? What guardrail or documentation should change? |
| Definition of Done | Code + tests + security checks + docs + deployed/verified evidence + rollback |

Link every PR to a work item. Keep acceptance criteria testable. If a story cannot be demonstrated, it is not done. Move it back to the backlog rather than marking it complete.

---

## 2. The week at a glance

| Day | Theme | Primary outcome | Exit criteria |
|---|---|---|---|
| 1 | Architecture and guardrails | Approved design, repo, board | Diagrams, CIDR plan, RBAC matrix, threat model, ADRs, GitHub, Azure Boards |
| 2 | Foundation | Remote Terraform state + hub network + shared security | State in Blob with locking, hub applied, policy assigned, private DNS resolver, Log Analytics, Key Vault |
| 3 | Platform | Spokes + data + AKS + APIM + App Service + Functions + Ansible | Private endpoints resolve, AKS/APIM/App Service deployed, ACR pull works, Ansible idempotent |
| 4 | Application and CI | FastAPI + Entra auth + RBAC + build pipeline | Tests pass, image in ACR, SBOM/signature, build artifact traceable |
| 5 | Release and operations | Release pipeline, dev deploy, prod approval gate, runbook | Dev endpoint works, prod stage blocked on approval, alerts/runbook, cost/cleanup |

### 2.1 Critical path

```text
Day 1 design
  -> Day 2 state backend
  -> Day 2 hub + DNS + firewall
  -> Day 3 spokes + private endpoints
  -> Day 3 AKS/APIM/App Service
  -> Day 4 app + build
  -> Day 5 release + verify
```

If Day 2 slips, Day 3 slips. If private DNS slips, everything after it looks broken. Protect the critical path.

### 2.2 Work that can run in parallel

- Day 2 evening: scaffold the FastAPI project and write tests that do not need Azure.
- Day 3: write the build YAML while Terraform applies.
- Day 4: write the release YAML skeleton and runbook while the build runs.
- Any day: update ADRs and the README so the next day starts with context.

---

## 3. Day 1 detailed agenda (4.5 hours)

| Time | Activity | Output |
|---|---|---|
| 0:00-0:20 | Read the brief, confirm scope, assumptions, and non-goals | Scope statement |
| 0:20-0:50 | Business/technical contract: endpoints, roles, SLOs | Requirements table |
| 0:50-1:35 | Network design: CIDRs, subnets, routing, DNS | `network-design.md` review |
| 1:35-2:15 | Identity and RBAC: app roles, scopes, groups, matrix | `identity-and-rbac.md` review |
| 2:15-2:30 | Break | - |
| 2:30-3:00 | Threat model and zero-trust control map | `zero-trust-threat-model.md` review |
| 3:00-3:30 | ADRs and plan-of-action review | Accepted/proposed ADRs |
| 3:30-4:15 | Workstation setup, GitHub repo, branch protection, Azure DevOps board | Repo + board |
| 4:15-4:30 | Review checklist, evidence, commit, EOD | Tagged commit |

If you have only 3 hours, do the design sections and repo; move the Azure DevOps board to the next morning before Day 2. Do not skip the CIDR/RBAC review.

---

## 4. Day 2 - Foundation (high-level)

**Outcome:** A secure hub and a Terraform backend that the rest of the week can trust.

### 4.1 Bootstrap the Terraform state

- Create a dedicated resource group for state: `rg-logistics-tfstate`.
- Storage account: `stlogisticstfstate<unique>`, `Standard_GRS` or `ZRS`, TLS 1.2, public access disabled, shared key disabled, Entra-only auth.
- Container: `tfstate`.
- Enable versioning, soft delete (90 days), change feed, immutable policy for state blobs if feasible.
- Private endpoint in the management VNet; private DNS zone `privatelink.blob.core.windows.net`.
- Grant the release identity `Storage Blob Data Contributor` on the container.
- Bootstrap with Azure CLI and local state only for the bootstrap stack; migrate to remote backend immediately. Document the chicken-and-egg step.

### 4.2 Build the hub

- `vnet-hub` and subnets.
- Azure Firewall (Basic in lab, Premium in prod), policy, public IP, forced tunneling decision.
- Azure Bastion.
- VPN/ExpressRoute gateway (optional for the lab; Terraform module ready).
- Private DNS Resolver inbound/outbound.
- Route tables and NSGs.
- Log Analytics workspace, diagnostic settings, retention, daily cap.
- Key Vault for TLS/CMK, private endpoint, purge protection.
- Azure Policy initiative: allowed locations, required tags, deny public IPs outside the approved edge/hub resource groups, deny public blob, require private endpoints, require TLS, deny local auth for SQL, require diagnostic settings.
- Managed identities for App Gateway, APIM, AKS workload, App Service, Functions, migration.
- Budget and alerts.

### 4.3 Exit criteria

- [ ] `terraform init` uses the remote backend; state lock works.
- [ ] `terraform plan` is clean and reviewed; `terraform apply` succeeds.
- [ ] State storage has no public access and no shared key.
- [ ] Hub firewall, Bastion, DNS resolver, and Log Analytics are deployed.
- [ ] Policy assignments are visible in Defender for Cloud.
- [ ] No secrets in the repo; pipeline identity can read/write state only.

---

## 5. Day 3 - Platform (high-level)

**Outcome:** All required Azure services exist, are private, and can talk to each other.

### 5.1 Network and data

- Spokes: ingress, workload, data, management.
- VNet peering, route tables, NSGs, private endpoints.
- Private DNS zones and links.
- Azure SQL: server, database, Entra admin, auditing, TDE/CMK, PITR/LTR, private endpoint.
- Azure Managed Redis: private endpoint, Entra auth, TLS, disable access keys.
- Blob Storage: containers, private endpoint, versioning, soft delete, immutability, lifecycle.
- Service Bus: namespace, topics, subscriptions, DLQ, duplicate detection, private endpoint.
- Key Vault: certificates/keys, RBAC, private endpoint.

### 5.2 Compute and gateway

- ACR Premium: private endpoint, admin disabled, retention, scan.
- AKS: private cluster, system/user pools, CNI Overlay, network policy, workload identity, Key Vault CSI, internal ingress, PDB/HPA, PSS.
- App Service: Linux Python, VNet integration, private endpoint, slots, managed identity.
- Functions: Flex Consumption, VNet integration, Service Bus trigger, managed identity.
- APIM: Standard v2, inbound private endpoint, outbound VNet integration, public access disabled, JWT policy, products, OpenAPI import.
- App Gateway: WAF_v2, public IP, TLS cert from Key Vault, backend pool to APIM, health probe, WAF policy.
- Ansible: harden agent/Ansible VMs, install tooling, configure Kubernetes baseline (namespaces, quotas, network policies, RBAC).

### 5.3 Exit criteria

- [ ] Private DNS resolves SQL/Redis/Storage/Key Vault/Service Bus/ACR/APIM to private IPs.
- [ ] AKS nodes are Ready; no public IP on nodes; ACR pull works.
- [ ] APIM can reach AKS and App Service; App Gateway can reach APIM.
- [ ] WAF blocks a test payload; APIM returns 401 without a token.
- [ ] Ansible second run reports no changes.
- [ ] No public data-plane access on PaaS services.

---

## 6. Day 4 - Application and build (high-level)

**Outcome:** A tested, scanned, signed container image and a build pipeline that cannot deploy.

### 6.1 Application

- FastAPI project structure, settings from environment/managed identity.
- Entra JWT validation, role/scope dependencies.
- Inventory and order routes, Pydantic models, SQLAlchemy, Alembic.
- Ownership checks, manager-only deletes, pagination, idempotency.
- Redis cache-aside for inventory reads; invalidation on writes.
- Transactional outbox and relay.
- Functions for order events, reconciliation, audit.
- Unit, integration, and contract tests; OpenAPI schema.
- Structured logs, OpenTelemetry traces, health/readiness endpoints.

### 6.2 Build pipeline

- Trigger: PR validation and merge to `main`.
- Stages: checkout, Python setup, lint, type check, unit tests, SAST, dependency scan, secret scan, IaC scan, container build, image scan, SBOM, sign/digest, push to ACR, publish Helm chart/artifacts.
- No Azure deploy permission. No production credentials.
- Quality gates: coverage, no HIGH/CRITICAL, no secrets, SBOM present.
- Artifact traceability: commit SHA, build ID, image digest, SBOM hash.

### 6.3 Exit criteria

- [ ] Build is green from a clean agent.
- [ ] Tests include 401/403/404/manager-delete cases.
- [ ] Image in ACR has an immutable tag and digest.
- [ ] SBOM and scan reports are attached.
- [ ] Build identity cannot deploy (negative test).
- [ ] A deliberately introduced secret/vulnerability fails the build.

---

## 7. Day 5 - Release and operations (high-level)

**Outcome:** A gated release path, a working dev deployment, evidence, and a clean shutdown.

### 7.1 Release pipeline

- Trigger: tag `v*` or manual; artifact from the build.
- Stage `InfraPlan`: Terraform plan, policy check, publish plan.
- Stage `InfraApply` (dev): apply after approval or automatically in dev.
- Stage `Configure` (dev): Ansible baseline.
- Stage `Migrate` (dev): Alembic job.
- Stage `Deploy` (dev): Helm to AKS, App Service slot swap, Functions deploy.
- Stage `Verify` (dev): smoke tests, synthetic auth/RBAC, DAST baseline.
- Stage `Prod`: same with approval, business hours, exclusive lock, two approvers if available.
- Rollback: Helm rollback, App Service slot swap back, migration roll-forward plan.
- Drift detection: scheduled plan, alert on diff.

### 7.2 Operations

- Dashboards: API latency/error rate, APIM, AKS, SQL, Redis, Service Bus DLQ, WAF, firewall.
- Alerts: 5xx, p95, 401/403 spike, DLQ, pod restarts, SQL CPU, Redis evictions, certificate expiry, public IP creation, cost anomaly.
- Runbook: deploy, rollback, rotate cert, restore SQL, replay DLQ, scale AKS, incident response.
- Backup/restore test: SQL PITR to a new DB; blob soft-delete recovery.
- Cost review: budget vs actual, top resources, cleanup.
- Demo: authenticate, call inventory, call orders, show 403 for reader delete, show manager delete, show event in Service Bus/Function, show logs/trace.
- Teardown: `terraform destroy` for non-prod, or stop AKS/SQL/App Service and delete expensive resources. Verify no orphan public IPs/disks.

### 7.3 Exit criteria

- [ ] Dev endpoint works end to end behind WAF/APIM.
- [ ] Reader cannot delete; manager can; audit event exists.
- [ ] Event flows through Service Bus to Function.
- [ ] Prod stage requires approval and uses a separate identity.
- [ ] Rollback demonstrated or documented with a dry run.
- [ ] Alerts and runbook reviewed.
- [ ] Cost and cleanup recorded.

---

## 8. Cost plan

### 8.1 Indicative monthly cost

These are planning ranges, not quotes. Verify in the Azure Pricing Calculator for Australia East and your currency.

| Component | Lab profile | Production-shaped |
|---|---|---|
| App Gateway WAF_v2 | USD 250-450 | USD 250-450+ |
| DDoS Protection | Platform protection included; optional IP/Network plan extra | Optional plan; Network Protection is a significant fixed cost |
| Azure Firewall | Basic USD 300-400 | Premium USD 900-1,300 |
| AKS nodes | USD 150-300 | USD 300-700 |
| APIM | Standard v2 USD 250-400 | Standard v2/Premium v2 higher |
| App Service | B1/P1v3 USD 50-200 | P1v3+ USD 150-400 |
| Functions | USD 0-50 | USD 0-100 |
| Azure SQL | Serverless USD 50-250 | GP zone-redundant USD 250-600 |
| Managed Redis | B0/B1 USD 50-150 | B1/B3 USD 150-400 |
| Storage | USD 10-50 | USD 50-200 |
| Service Bus | Standard USD 10-50 | Premium USD 600+ |
| Key Vault | USD 5-20 | USD 20-50 |
| ACR | Premium USD 50 | Premium USD 50-100 |
| Bastion | Developer/Standard USD 0-200 | Standard USD 140-200 |
| Log Analytics | USD 50-200 | USD 200-600 |
| Defender/Sentinel | USD 0-200 | Usage-based |
| **Approx. total** | **USD 700-1,200/mo** | **USD 2,000-3,500+/mo** |

A five-day build that is destroyed nightly can cost roughly **USD 150-300**, depending on how many hours the full stack runs. The firewall and App Gateway are often the largest fixed costs.

### 8.2 Cost guardrails

- Create a subscription/resource-group budget with alerts at 50%, 80%, 100%.
- Tag every resource: `env`, `owner`, `costCenter`, `workload`, `dataClassification`, `managedBy`.
- Set Log Analytics daily cap in dev.
- Use SQL serverless auto-pause in dev.
- Use AKS cluster stop/start or destroy nightly.
- Use Basic firewall in dev; Premium only for the IDPS demonstration.
- Do not deploy prod until Day 5; use a plan-only prod stage for the approval demonstration.
- Delete orphan public IPs, disks, and NICs after `terraform destroy`.
- Review Cost Management every morning during the build.

### 8.3 What not to cut

- Private endpoints and private DNS.
- Terraform state locking and RBAC.
- Entra auth and RBAC tests.
- Build/release identity separation.
- Logging and alerts.
- Backups for SQL/Storage.

Cutting these saves a few dollars and creates a false sense of completion.

---

## 9. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Azure quota unavailable for AKS/App Service | Medium | Schedule slip | Check quota Day 1; request early; choose another region if needed |
| Entra P1/P2 unavailable | Medium | No PIM/Conditional Access | Document compensating controls; use time-bound RBAC and MFA |
| APIM Standard v2 feature mismatch | Medium | Rework | Confirm private endpoint + outbound integration before Terraform; prototype Day 2 |
| Private DNS misconfiguration | High | Everything looks broken | Link zones to every VNet; test with `nslookup` from each spoke |
| App Service worker IP overlap | Low/Medium | Silent routing failures | Avoid 10.70/10.71 and documented ranges; validate before deployment |
| Firewall FQDN blocks AKS/agents | High | Nodes NotReady, pipeline fails | Use AKS FQDN tag + required FQDNs; watch firewall deny logs |
| Ansible on Windows | Medium | Tooling delay | Use WSL2; do not try to run Ansible control node on Windows |
| Self-hosted agent cannot reach private endpoints | Medium | Release pipeline fails | Place agents in management VNet; peer; private DNS; test |
| Service connection permissions too broad | Medium | Security finding | Scoped roles, separate identities, approvals, review plan |
| Cost overrun | Medium | Budget surprise | Budget alerts, lab profile, nightly destroy, daily cost review |
| Time overrun on Day 3 | High | Day 4/5 compressed | Timebox; defer non-critical components; protect vertical slice |
| No Azure DevOps parallel job/minutes | High | Pipelines queue indefinitely | Check quota Day 1; use self-hosted agents in the management VNet |
| GitHub plan lacks private-repo branch protection | Medium | No enforced review | Use an org repo/paid plan, or make the course repo public with no secrets |
| Certificate/domain unavailable | Medium | Ingress blocked | Use self-signed cert for lab; document production CA path |
| WAF false positives | Medium | API blocked | Detection mode first; tune; log rule IDs |
| Secret accidentally committed | Medium | Credential leak | Gitleaks pre-commit + CI, push protection, rotate immediately |
| Single engineer, no reviewer | High | Blind spots | Use Copilot as a critic, checklists, ADRs, peer review if possible |

---

## 10. Definition of done for the week

The week is done when you can demonstrate:

- [ ] A user authenticates with Entra ID and receives a short-lived access token.
- [ ] The token is validated at APIM and in the API.
- [ ] A reader can read inventory but cannot delete it.
- [ ] A contributor can create/update but cannot delete.
- [ ] A manager can delete inventory and orders, with an audit record.
- [ ] A user cannot read another user's order.
- [ ] A partner can post a webhook but cannot call inventory/orders.
- [ ] Order creation writes to SQL and publishes an event via the outbox.
- [ ] A Function consumes the event and writes an audit record.
- [ ] The API is reachable only through WAF -> APIM; no public backend.
- [ ] Build pipeline produces a scanned, signed/digested image and SBOM.
- [ ] Release pipeline deploys dev and gates prod with approval.
- [ ] Rollback is documented and tested.
- [ ] Logs, traces, and alerts are visible.
- [ ] Cost and cleanup are recorded.
- [ ] The README/runbook lets another engineer repeat the deployment.

If you cannot demonstrate an item, it is not done. "It worked once in the portal" is not done.

---

## 11. If you fall behind

Protect the vertical slice:

**Must have**

- Hub + workload + data VNets, private DNS, firewall egress.
- AKS + APIM + SQL + Service Bus + ACR.
- One inventory endpoint and one order endpoint.
- Entra auth, RBAC, manager delete, own-order rule.
- Build pipeline and release pipeline with approvals.
- Logs and at least three alerts.
- Terraform state in Blob with locking.

**Defer, but document**

- App Service partner webhook.
- Functions event consumer (use a simple outbox relay log instead).
- Redis (use SQL only, note latency/cost).
- Blob audit archive.
- WAF custom rules beyond managed rules.
- Sentinel analytics (keep Defender and Log Analytics).
- Image signing enforcement (record digest and verify manually).
- DAST (run a local ZAP baseline).
- Multi-environment prod deployment (plan-only prod).

**Never defer**

- Private endpoints for data.
- Terraform state security.
- Entra auth/RBAC tests.
- Build/release identity separation.
- Secret scanning.
- Backups for SQL/Storage.
- Cost cleanup.

A smaller, honest vertical slice is better than a broad, insecure demo.

---

## 12. Production readiness gaps to close after the course

| Gap | Why it matters | Next action |
|---|---|---|
| Single region | Regional outage | Paired region, geo-redundant SQL/Storage, APIM backup, traffic manager/Front Door |
| No 24/7 on-call | Incident response | On-call rotation, escalation policy, paging |
| No external pen test | Unknown vulnerabilities | Pre-production pen test and remediation |
| WAF not fully tuned | False positives/negatives | Tune in detection, then prevention; review monthly |
| No load test at 2x peak | Capacity surprises | Azure Load Testing, k6, or JMeter |
| No chaos exercise | Untested failure modes | Pod/node/SQL failover, firewall outage, DNS failure |
| No automated restore test | Backup may not restore | Monthly SQL PITR and blob restore drill |
| Image signing not enforced | Supply-chain risk | Admission policy (Ratify/Notation), key management |
| No SBOM retention policy | Audit gap | Store SBOM with release, retain per policy |
| No data classification/DLP | Privacy risk | Classify order/customer data, apply DLP, retention |
| No FinOps chargeback | Cost accountability | Tags, budgets, showback per team |
| Manual certificate rotation | Expiry outage | Automate rotation and alert 30/14/7 days before |
| No incident response playbook | Slow containment | Runbooks, tabletop, contact tree |
| No access reviews | Privilege creep | Quarterly group/app role reviews |
| No DR runbook | Extended outage | Document RTO/RPO, test failover |

---

## 13. End-of-week handover package

- Architecture diagrams (logical + network).
- ADRs 0001-0010.
- Terraform modules and environment variables.
- Ansible playbooks and inventory.
- Build and release pipeline YAML.
- Runbook: deploy, rollback, rotate cert, restore SQL, replay DLQ, scale, incident.
- Security control matrix and residual risks.
- Cost estimate and cleanup steps.
- Demo script and test evidence.
- Known gaps and next sprint backlog.

If another engineer cannot repeat the deployment from the README, the handover is incomplete.

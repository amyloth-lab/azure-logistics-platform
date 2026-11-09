# Project State - Azure Logistics Platform

**Last updated:** 2026-11-09 (EOD Day 4)
**Purpose:** Canonical, compact project memory. Read this first instead of re-reading Day 1/Day 2 documents.
**Rule:** Update this file at the end of every day. Keep it under ~250 lines. Do not put real subscription IDs, tenant IDs, emails, secrets, or storage keys in it.

---

## 1. How to use this file

At the start of a session:

1. Read this file.
2. Read only the current day's guide.
3. Do not re-read all previous day guides unless a decision is ambiguous.

At the end of a day:

1. Add/update that day's section.
2. Record failures and the exact fix.
3. Record the current Terraform/Azure state.
4. Record the next action and any open decision.
5. Remove details that no longer matter.

This keeps context small and prevents re-solving old errors.

---

## 2. Project snapshot

**Goal:** A production-shaped logistics platform for inventory and order APIs, built over five working days with Azure, Terraform, Ansible, GitHub, and Azure DevOps.

**Business API:**

- `GET/POST/PATCH/DELETE /api/v1/inventory`
- `GET/POST/PATCH/DELETE /api/v1/orders`
- Manager-only deletes; normal users only see their own orders.
- Partner carrier webhook on App Service.
- Event-driven order processing with Service Bus and Functions.

**Core stack:**

- Microsoft Entra ID Free for authentication.
- Application Gateway WAF_v2 for public ingress.
- APIM Standard v2 for API governance.
- AKS private cluster for the core API.
- App Service for the partner webhook.
- Azure Functions for events.
- Azure SQL for transactions; Managed Redis for cache/idempotency.
- Blob Storage for documents/audit.
- Service Bus Premium for private-endpoint messaging.
- Key Vault, ACR Premium, Log Analytics, Defender, Azure Policy.
- Hub-and-spoke VNets with Azure Firewall Basic (lab) and Bastion.
- Terraform for infrastructure, Ansible for Linux/Kubernetes baseline.
- Separate build and release pipelines in Azure DevOps.

**Primary region:** `australiaeast`
**Public API hostname placeholder:** `api.logistics.example.com` (not a real TLS domain).

---

## 3. Non-negotiable decisions

| Area | Decision |
|---|---|
| Entra ID | **Free tier.** No Conditional Access, PIM, access reviews, ID Protection, or custom roles. Use security defaults, separate admin accounts, manual JIT, quarterly manual reviews. See ADR-0011. |
| APIM | Standard v2. Inbound private endpoint + outbound VNet integration. `snet-apim-outbound` is delegated to `Microsoft.Web/serverFarms`; this is correct for Standard v2 and must not be "fixed." |
| AKS/App Service | AKS hosts core API; App Service hosts partner webhook. Do not merge them without an ADR. |
| Network | Hub-and-spoke; no public data plane; App Gateway is the only public application entry point. |
| Firewall | Basic in lab. Basic requires a management NIC (management public IP + `AzureFirewallManagementSubnet`). Standard is a fallback; Premium adds IDPS/TLS inspection. |
| State | Terraform state in Blob, Entra-only auth, versioning, soft delete, lease lock. Key remains `dev/hub.tfstate` for continuity. Do not rename mid-week. |
| Pipelines | Build and release are separate identities and pipelines. Build cannot deploy; release cannot push images. |
| AuthN/AuthZ | Entra proves identity; app roles + APIM + API enforce permissions. APIM is not the only authorization point. |
| Secrets | No secrets in Git or YAML. Managed identities/workload identity federation. |
| Local notes | `docs/day-01/review-notes.local.md` is gitignored. Never commit real IDs/account details. |

---

## 4. Repository and environment

- Repo: `C:\Users\OEM\Documents\deepseek-harness\default-workspace`
- GitHub remote exists; `main` is the working branch.
- Terraform: `C:\Users\OEM\AppData\Local\Microsoft\WinGet\Packages\Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe\terraform.exe`
- Region: `australiaeast`
- State RG: `rg-logistics-tfstate`
- Platform RG: `rg-logistics-platform-dev`
- Workload RG: `rg-logistics-workload-dev`
- Data RG: `rg-logistics-data-dev`
- Management RG: `rg-logistics-management-dev`
- Firewall: Basic, private IP normally `10.0.0.4`
- Budget: user-local `terraform.tfvars`; currently low (USD 150) and will alert quickly with Premium services.

**Ignored and never committed:**

```text
terraform.tfstate*
*.tfplan
terraform.tfvars
backend.hcl
backend.tf
.terraform/
docs/day-01/review-notes.local.md
docs/day-01/evidence/
```

---

## 5. Day 1 - completed

**Outcome:** Architecture, network design, identity/RBAC, threat model, ADRs, repo, Azure Boards backlog.

Artifacts:

- `docs/day-01/README.md` - full Day 1 workbook.
- `docs/day-01/DO-THIS-FIRST.md` - simplified path.
- `docs/day-01/network-design.md` - CIDRs, subnets, routing, DNS, NSGs.
- `docs/day-01/identity-and-rbac.md` - app roles, scopes, endpoint matrix.
- `docs/day-01/zero-trust-threat-model.md` - STRIDE and controls.
- `docs/day-01/plan-of-action.md` - five-day plan, costs, risks.
- `docs/day-01/glossary.md`.
- `docs/day-01/azure-boards-import.csv`.
- `diagrams/logical-architecture.png` and `network-topology.png`.
- ADRs 0001-0011.

Key network plan:

| VNet | CIDR |
|---|---|
| Hub | `10.0.0.0/16` |
| Ingress | `10.1.0.0/16` |
| Workload | `10.2.0.0/16` |
| Data | `10.3.0.0/16` |
| Management | `10.4.0.0/16` |
| AKS pods | `100.64.0.0/16` |
| AKS services | `10.60.0.0/16` |

Key identity roles:

- `Inventory.Reader`, `Inventory.Contributor`
- `Order.Reader`, `Order.Contributor`
- `Logistics.Manager` (only role allowed to delete inventory/orders)
- `Partner.Webhook`

Entra Free change:

- Security defaults provide MFA; no Conditional Access/device compliance.
- No PIM; use separate admin account + manual JIT + remove assignment after task.
- No access reviews; manual quarterly review.
- Managed identities and workload identity federation are still supported and free.
- No ID Protection risk policies; use sign-in logs/alerts.

---

## 6. Day 2 - completed

**Outcome:** Terraform state in Blob + secure hub network.

Implemented:

- `infra/terraform/bootstrap/` - state storage bootstrap.
- `infra/terraform/envs/dev/` - hub stack.
- Hub VNet, 7 subnets.
- Azure Firewall Basic + policy + public IP + management public IP + management NIC.
- Azure Bastion Basic.
- Log Analytics workspace.
- 9 private DNS zones linked to hub.
- Subscription-scope policy denying public IPs outside platform/edge RGs.
- Budget.
- State key `dev/hub.tfstate`.

Important fixes during Day 2:

1. `threshold_type` must be `Actual` or `Forecasted`, not `Percentage`.
2. Diagnostic setting `count` cannot depend on an unknown workspace ID; diagnostics are now always enabled.
3. Basic Firewall does not support `AzureFirewallThreatIntelLog`; category is included only for Standard/Premium.
4. Basic Firewall requires a management NIC:
   - `AzureFirewallManagementSubnet`
   - management public IP
   - `management_ip_configuration`
5. The Basic public IP count is **3**: firewall data, firewall management, Bastion.

State backend caveat:

- Azure CLI session corruption under `C:\Users\OEM\.azure` caused `PermissionError`; fix with:
  ```powershell
  icacls "$env:USERPROFILE\.azure" /grant "$($env:USERNAME):(OI)(CI)F" /T
  ```
  then `az login`.
- Terraform backend uses `use_azuread_auth = true`; no storage keys.

---

## 7. Day 3A - completed

**Goal:** Spokes + private DNS + ACR + Key Vault + SQL + Storage + Service Bus + Managed Redis.

New modules:

- `infra/terraform/modules/network-spokes/`
- `infra/terraform/modules/acr/`
- `infra/terraform/modules/keyvault/`
- `infra/terraform/modules/data/`

Network:

- 4 spoke VNets, 12 subnets, 8 peerings.
- Route tables to firewall; NSGs.
- 36 private DNS links (9 zones x 4 spokes).

Private services:

- ACR Premium + private endpoint (management VNet).
- Key Vault + private endpoint (data VNet).
- Azure SQL server/database + private endpoint.
- Storage account + `documents`/`audit` containers + private endpoint; shared keys disabled; containers created with `azapi`.
- Service Bus Premium + topics/subscriptions + private endpoint.
- Managed Redis Balanced_B0 + private endpoint; access keys disabled.

**Completion:**

- User marked Day 3A complete and committed `15660a1 feat(day-3a): spoke network, private endpoints, and data services`.
- Service Bus was changed to **Premium, capacity 1, 1 partition** because Standard cannot use Private Link.
- Six private endpoints are expected: ACR, Key Vault, SQL, Storage, Service Bus, Managed Redis.
- If the six endpoints are not all `Approved`, re-run the validation before starting Day 3B.

**Open decision:** Service Bus Premium is expensive (roughly USD 600-800/month). If the budget cannot support it, the alternative is a Standard namespace with service endpoints and a deny-by-default network rule set, and the private endpoint removed. That is a documented security deviation, not a like-for-like swap.

**Documentation pending commit:** `docs/PROJECT-STATE.md`, ADR-0006, `plan-of-action.md`, and the Day 2/3 guide updates are in the working tree.

---

## 8. Error/fix log (do not re-solve)

| Symptom | Cause | Fix |
|---|---|---|
| APIM subnet delegation challenged | Confused classic injection with Standard v2 outbound integration | Keep `Microsoft.Web/serverFarms` for `snet-apim-outbound`; Standard v2 docs require it. |
| Budget `threshold_type` invalid | `Percentage` is not a valid enum | Use `Actual` or `Forecasted`; `threshold` remains 50/80/100. |
| Diagnostic `count` unknown | Count depended on workspace ID created in same apply | Diagnostics always on; no conditional count. |
| `AzureFirewallThreatIntelLog` unsupported | Basic SKU limitation | Include category only when `sku_tier != "Basic"`. |
| Basic firewall missing management IP | Basic always has a management NIC | Add management subnet ID, management public IP, `management_ip_configuration`. |
| Service Bus private endpoint 400 | Standard SKU does not support Private Link | Use Premium, or documented service-endpoint fallback. |
| AKS `Forbidden: nodes is forbidden` | Entra auth works, but no Kubernetes RBAC role | Assign `Azure Kubernetes Service RBAC Cluster Admin` to the current user at the AKS scope; wait for propagation. |
| APIM private endpoint group ID error | APIM Private Link group ID is case-sensitive | Use `subresource_names = ["Gateway"]`, not `gateway`. |
| APIM Standard v2 provider gap | `azurerm_api_management` lacks v2 outbound/public-disable support | Use `azapi_update_resource` after the private endpoint; do not use classic `virtual_network_configuration`. |
| APIM `virtualNetworkType` cannot be `none` | A subnet config requires a type; Standard v2 uses external integration | Set `virtualNetworkType = "External"` for Standard v2. |
| App Service `WEBSITE_VNET_ROUTE_ALL` rejected in `app_settings` | Provider manages it through a first-class property | Use `site_config.vnet_route_all_enabled = true`; do not put it in `app_settings`. |
| App Service plan 401 `Additional quota` / `S1 VMs: 0` | Subscription has zero App Service VM quota in region | Request quota for the chosen SKU (B1 or S1) in `australiaeast`; upgrade Free/Trial to Pay-As-You-Go if needed. Changing SKU alone does not help. |
| App Service quota request ineligible | Subscription offer does not permit App Service quota | Keep App Service disabled; use AKS for the partner webhook temporarily or move to a subscription with quota. Record the deviation. |
| Flex Function VNet integration 401 / `Microsoft.App` not registered | Flex Consumption uses Microsoft.App; provider missing | `az provider register --namespace Microsoft.App --wait`; verify `Registered`; retry plan/apply. |
| Flex Function `SubnetMissingRequiredDelegation` | Flex requires `Microsoft.App/environments`, not `Microsoft.Web/serverFarms` | Change `snet-functions-outbound` delegation to `Microsoft.App/environments`; apply subnet update, then Function App. |
| App Gateway `filebase64` cannot find `cert.pfx` | Certificate generated in repo root, but Terraform runs from `envs/dev` | Copy the PFX into `infra/terraform/envs/dev` or run `terraform` from the directory containing the PFX. |
| App Gateway `PublicIPCountLimitReached` | Subscription public IP quota is 3 and all three are used | Request a public IP quota increase in `australiaeast` (to at least 4), or remove a public IP safely; do not delete firewall/Bastion IPs. |
| Terraform init `az.sess` / `commands` PermissionError | Azure CLI cannot write its session/log directory | `icacls "$env:USERPROFILE\.azure" /grant "$($env:USERNAME):(OI)(CI)F" /T`, then `az login`. |
| Ansible VM `Total Regional Cores` 4/4 | No free vCPU quota in `australiaeast` | Deferred per ADR-0014; if quota is later available, request 6–8 and set `enable_ansible_vm = true`. |
| Azure CLI `AADSTS65001` / `AADSTS650057` for `api://logistics-api` | Azure CLI cannot request tokens for an arbitrary custom API; its app registration lacks the resource | Use the Terraform-created `logistics-cli` public client and `scripts/get_token.py` (MSAL device code), not `az login --scope`. |
| Device sign-in “You don't have access to this” | User has no app-role assignment on `logistics-api`, or consent is missing | Set `entra_role_assignment_object_id` to the signing-in user's object ID, re-apply `-target=module.entra`, and grant `logistics-cli` consent. |
| `AADSTS530035` for `whrsoft@gmail.com` or `manager@...` | Personal/Gmail account is not a member/guest, or a Conditional Access policy blocks the unregistered device | Check the sign-in log's Conditional Access tab by request/correlation ID. If a policy requires a compliant/Entra-joined device, exclude the lab user from that specific policy or use a compliant device. Also verify the user is assigned to `logistics-api` if assignment is required. |
| `Permission being assigned already exists on the object` | App role assignment already exists outside Terraform state, often from portal or a partial apply | Remove all app-role assignments for that user on `logistics-api`, then re-apply; or import the existing assignment. Do not create duplicates. |
| Build `pip-audit`: `logistics-api Dependency not found on PyPI` | `pip-audit` audits the editable local project as a PyPI dependency; `--skip-editable` can still exit non-zero | Generate a requirements file with `pip freeze --exclude-editable` and audit that file; do not skip the audit. |
| `PYSEC-2026-1845` pytest 8.4.2 | Dev dependency pinned below the fixed release | Pin `pytest>=9.0.3,<10`; remove unused `pytest-asyncio`. |
| ACR `TasksOperationsNotAllowed` | ACR Tasks is disabled/not permitted for this subscription | Build locally with `docker build` + `docker push`; do not request ACR Tasks. |
| ACR `az acr login` 403 / `CONNECTIVITY_REFRESH_TOKEN_ERROR` | Hosted agent cannot reach a private-only ACR, `azureADAuthenticationAsArmPolicy` is disabled, or identity lacks AcrPush | Check `publicNetworkAccess`, AAD-ARM policy, and AcrPush. Decision for this lab: temporary public ACR access (ADR-0015); private endpoint remains. |
| Trivy zlib1g CVE-2026-76844 / CVE-2026-85091 | Base image OS package is older than the Debian security update | Runtime Dockerfile upgrades `zlib1g` after the base image; rebuild and rescan. Do not add a blanket Trivy ignore. |
| AKS image pull `EOF` from private ACR | AKS nodes route 0.0.0.0/0 to firewall; no network rule allowed 10.2/16 → ACR private endpoint in 10.4.2.0/24:443 | Add `acr-private-endpoint` firewall network rule, apply it, restart the pod. Verify private DNS resolves ACR to the private IP and kubelet has AcrPull. |
| Pod `CreateContainerConfigError` | Common cause: `runAsNonRoot` with a non-numeric image user (`USER app`), or a missing Secret/ConfigMap/ServiceAccount | Build the image with numeric UID/GID `10001:10001` and set matching `runAsUser`/`runAsGroup`/`fsGroup`; inspect `kubectl describe pod` for the exact event. |
| Terraform backend auth failure | Azure CLI `.azure` ACL | `icacls` fix + `az login`. |
| State plan file stale after errors | Failed plan/apply | Delete plan, re-run `terraform plan`, apply new plan. |

---

## 9. Current checkpoint and next action

Current checkpoint: **Day 5 checkpoint 5B - deploy AKS chart and wire APIM.** 5A and 5B-0 are complete. The Helm chart and APIM API resources are added; deploy and smoke-test pending.

### Day 4 completed

- 4A: FastAPI `app/` package, inventory/orders, SQLAlchemy, Pydantic; root `tests/`, `pipelines/`, `pyproject.toml`.
- 4B: Entra JWT validation, `logistics-cli` public client, device-code token script, Terraform app roles/assignments.
- 4C: 18 tests pass; Ruff passes.
- 4D code: Dockerfile, build pipeline, pip-audit, Bandit, Gitleaks, local Docker build/push, Trivy.
- `pytest>=9.0.3` fixes PYSEC-2026-1845.
- ACR public access is a temporary lab exception (ADR-0015); private endpoint and admin-disabled remain.
- Cost scripts: `scripts/stop-lab.ps1`, `scripts/start-lab.ps1`; guide `docs/cost-control.md`.

### Day 4 open item

Closed: the first green Azure DevOps build is complete; zlib1g CVEs were fixed in the Dockerfile.

### Day 5 blocker

5B-0 code/Terraform added:

- `pyodbc`, `azure-identity`, ODBC driver 18 in the runtime image.
- `app/db.py` uses `DefaultAzureCredential` for `mssql+pyodbc`.
- `infra/terraform/modules/api-identity/` creates UAMI + AKS federated credential + Blob/Service Bus roles.
- `deploy/helm/logistics-api/` has Deployment, ServiceAccount, internal LoadBalancer Service, schema-init Job, and `values-dev.example.yaml`.
- Helm `lint` and `template` pass; default image tag `0.1.0` prevents an empty-tag YAML parse error. Override with the immutable build tag or digest.
- Service uses internal LoadBalancer IP `10.2.12.10` in `snet-aks-ingress`.
- APIM module creates API `logistics-api`, path `logistics`, backend `http://10.2.12.10:80`, and GET operations for health/inventory/orders.
- SQL schema init is currently `Base.metadata.create_all`; Alembic is still a production gap.
- Managed Redis is `Encrypted` with Entra-only auth, port `10000`; `REDIS_HOST` is hostname only and `REDIS_PORT=10000`. The app does not yet use `redis-entraid` or a Redis user assignment.

5B-0 manual step: apply `module.api_identity`, then create the contained Azure SQL user for the API workload identity and grant `db_datareader`, `db_datawriter`, and migration schema rights. SQL has no public access, so use a temporary VNet jumpbox/pod or a temporary firewall exception that is reverted immediately.

### Day 3B deferred gaps

- App Service: zero App Service VM quota, ineligible. ADR-0012.
- Public WAF edge: 3 public IP limit; APIM private-only. ADR-0013.
- Ansible control VM: 4/4 Total Regional Cores. ADR-0014.

No public API endpoint; demo from AKS or a Bastion-connected VM. Do not weaken the private design to compensate.

### Day 5 scope

1. **5A:** green build, immutable digest, scans clean.
2. **5B:** Helm chart/manifests for AKS, APIM backend, migration job.
3. **5C:** release pipeline, dev deployment, smoke tests.
4. **5D:** prod approval gate, observability, runbook, cleanup.

Guide: `docs/day-05/README.md`.

---

## 10. End-of-day update template

Append/update a section like this at EOD:

```markdown
## Day X - completed|partial

**Outcome:**
**Applied/created:**
**Validated:**
**Errors and fixes:**
**Current state / resources:**
**Open decisions:**
**Next action:**
**Commit/tag:**
```

Then update:

- `Last updated`
- Current checkpoint
- Immediate next action
- Error/fix log (only new, durable fixes)
- Remove stale details that no longer matter.

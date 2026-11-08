# Project State - Azure Logistics Platform

**Last updated:** 2026-11-08 (AKS checkpoint complete)
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
| Terraform backend auth failure | Azure CLI `.azure` ACL | `icacls` fix + `az login`. |
| State plan file stale after errors | Failed plan/apply | Delete plan, re-run `terraform plan`, apply new plan. |

---

## 9. Current checkpoint and next action

Current checkpoint: **Day 3B checkpoint 3C - App Service blocked; continue with Functions, App Gateway, and Ansible.** APIM is complete.

AKS is complete:

- Private cluster applied.
- System + user node pools Ready.
- Existing `privatelink.australiaeast.azmk8s.io` zone with UAI, `Private DNS Zone Contributor`, `Network Contributor`.
- `Azure Kubernetes Service RBAC Cluster Admin` applied; `kubectl get nodes` works through `az aks command invoke`.
- Firewall `aks-egress` rule collection group applied.
- Do not change AKS unless a specific error requires it.

APIM is complete:

- `infra/terraform/modules/apim/` - StandardV2_1, system-assigned identity, inbound private endpoint, `Gateway` group ID, private DNS.
- `azapi_update_resource` sets `publicNetworkAccess=Disabled`, `virtualNetworkType=External`, outbound subnet.
- Private endpoint approved; public access disabled.
- The `virtualNetworkType=None` error was fixed by using `External`.

App Service status: **blocked; subscription is ineligible for a quota increase.**

- `infra/terraform/modules/app-service/` exists and validates, but is disabled with `enable_app_service = false`.
- `site_config.vnet_route_all_enabled = true`; do not set `WEBSITE_VNET_ROUTE_ALL` in `app_settings`.
- `app_service_sku` is parameterized; default B1.
- App Service VM quota is 0 in `australiaeast`; changing B1/S1 does not help.
- No App Service resources were created.
- Recommended: keep App Service disabled, host the partner webhook on AKS as a documented deviation, and revisit if a subscription with quota becomes available.
- Do not enable `enable_app_service` until quota exists.

Day 3B next: implement Functions, App Gateway, and Ansible. App Service is recorded as a production gap, not silently dropped.

Day 3B is deliberately split into three checkpoints because it is too large for one sitting. Guide: `docs/day-03b/README.md`.

1. **3B-1 - AKS:** private cluster, system/user node pools, Azure CNI Overlay, workload identity, OIDC issuer, internal ingress, ACR pull, Entra RBAC. Validate nodes and private API.
   - **Decided:** use the existing `privatelink.australiaeast.azmk8s.io` zone with a user-assigned identity + `Private DNS Zone Contributor` and `Network Contributor`. Code is added; apply pending.
2. **3B-2 - APIM:** Standard v2, inbound private endpoint, outbound VNet integration, backend/health policy. Validate private access and 401/403 behavior.
3. **3B-3 - Edge/PaaS/Ansible:** App Service, Functions, App Gateway WAF_v2, Ansible control/agent VMs, Kubernetes baseline.

Day 4 adds the FastAPI app, Entra auth/RBAC, tests, and build pipeline.
Day 5 adds release pipeline, dev deployment, prod approval gate, observability, runbook, and cleanup.

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

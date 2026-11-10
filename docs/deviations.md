# Deviations from the original design

This project was built in a constrained lab subscription with **Microsoft Entra ID Free**. Some deviations are licence limits; others are subscription quotas, regional capacity, or cost decisions. They are not equivalent.

## Summary

| # | Original design | Actual implementation | Cause | ADR |
|---|---|---|---|---|
| 1 | Entra ID with Conditional Access, PIM, access reviews, ID Protection | Entra ID Free; Security Defaults, separate admin accounts, manual JIT, quarterly manual reviews | Entra ID Free licence | [0011](adr/0011-entra-id-free-license.md) |
| 2 | App Service hosts the partner webhook | App Service not deployed; module exists but disabled | App Service VM quota is 0 and the subscription is ineligible for an increase | [0012](adr/0012-app-service-quota-deferral.md) |
| 3 | Application Gateway WAF_v2 is the public entry point | App Gateway module exists but is disabled; APIM is private-only; no public API | Public IP quota is 3; firewall data, firewall management, and Bastion already use all three | [0013](adr/0013-defer-edge-private-only.md) |
| 4 | Ansible control VM applies configuration and Kubernetes baseline | Ansible VM module and playbook exist but are disabled; no Ansible execution | Total Regional Cores is 4/4; the VM needs 2 vCPUs | [0014](adr/0014-defer-ansible-vm.md) |
| 5 | Build uses ACR Tasks or a private build path | Local `docker build` + `docker push` from a Microsoft-hosted agent | ACR Tasks returns `TasksOperationsNotAllowed` for this subscription | [0015](adr/0015-acr-public-access-for-hosted-build.md) |
| 6 | ACR is private-only | ACR private endpoint retained, but public network access temporarily enabled for hosted build agents | Hosted agents cannot reach a private endpoint | [0015](adr/0015-acr-public-access-for-hosted-build.md) |
| 7 | Partner webhook runs on App Service | Partner webhook is not deployed; the API currently exposes inventory and orders only | Follow-on effect of the App Service deferral | [0012](adr/0012-app-service-quota-deferral.md) |
| 8 | Separate prod stack and prod deployment | Dev stack exists; `prod` approval environment is configured, but no prod AKS/SQL stack or prod deployment | Lab scope and quota constraints | — |
| 9 | Public API endpoint for demos | No public endpoint; smoke tests run from AKS through APIM's private endpoint | Public IP quota and private-only design | [0013](adr/0013-defer-edge-private-only.md) |

## 1. Entra ID Free

Entra ID Free provides:

- App registrations and app roles
- Groups
- Managed identities and workload identity federation
- Security Defaults
- Sign-in and audit logs

It does **not** provide:

- Conditional Access
- PIM
- Access reviews
- ID Protection
- Custom Entra roles

Compensating controls used:

- Security Defaults
- Separate admin accounts
- Manual just-in-time elevation
- Quarterly manual access reviews
- App roles and least-privilege assignments
- Workload identity instead of stored credentials

The application still validates JWTs and enforces RBAC. The missing controls are governance controls, not application authentication.

## 2. App Service and partner webhook

App Service was not deployed because the subscription has zero App Service VM quota and the quota increase was rejected as ineligible.

Effects:

- No `partner-webhook` App Service.
- No App Service deployment slots or slot swaps.
- The partner webhook route is not implemented.

The AKS-hosted fallback mentioned in ADR-0012 was **not built**. Do not claim the webhook is deployed.

## 3. Public edge and WAF

The subscription allows 3 public IPs. They are allocated to:

- Azure Firewall data IP
- Azure Firewall management IP
- Azure Bastion IP

App Gateway needed a fourth. It was deferred.

Effects:

- No public API endpoint.
- No WAF inspection and no edge TLS termination.
- No external partner callback endpoint.
- APIM remains reachable only through its private endpoint and private DNS.
- Demos run from AKS or a Bastion-connected host.

Do not expose APIM publicly to compensate. That discards the private-by-design control.

## 4. Ansible

The Ansible VM was deferred because the region has 4/4 Total Regional Cores in use by AKS. A smaller VM does not help when zero cores are free.

Effects:

- No persistent Ansible control host.
- No VM SSH-hardening or idempotence demonstration.
- Kubernetes deployment uses Helm through `az aks command invoke`.
- Database schema initialization uses a Helm Job, not an Ansible playbook.

The playbook and module remain in the repo for a subscription with vCPU quota. Do not shrink AKS just to fit Ansible.

## 5. ACR build and network

ACR Tasks is not permitted for this subscription. The build pipeline was changed to:

```text
docker build
docker push
```

Microsoft-hosted agents cannot reach the private ACR endpoint, so ACR public access was temporarily enabled.

Effects:

- ACR is no longer private-only while the exception is active.
- Admin user remains disabled; authentication is Entra-based.
- The private endpoint remains for AKS.
- Production remediation is a self-hosted agent inside the VNet, then disable public access.

## 6. Cost-driven choices, not free-tier limits

These were chosen for cost or architecture reasons and should not be attributed to Entra Free:

- Service Bus **Premium** required for private endpoints.
- ACR **Premium** for private endpoint support.
- APIM **Standard v2** for private endpoint + outbound integration.
- Azure Firewall **Basic** and Bastion **Basic** for lab cost.
- AKS **Free** control plane and small node pools.

## 7. What was delivered despite the constraints

- Hub-and-spoke network with firewall and private DNS
- Private AKS and private APIM
- ACR, Key Vault, SQL, Storage, Service Bus, Managed Redis
- Entra JWT validation, manager-only delete, own-order isolation
- 18 tests passing
- Terraform infrastructure and remote state
- Build and release pipelines
- Helm deployment, migration Job, APIM private path
- Runbook, cost-control scripts, and ADRs

## 8. What must not be claimed

Do not claim:

- App Service is deployed.
- The partner webhook exists.
- WAF/App Gateway protects a public endpoint.
- Ansible was executed.
- There is a separate production deployment.
- APIM is publicly reachable.
- ACR is private-only while the public-access exception is active.

Those are documented gaps, not completed requirements.

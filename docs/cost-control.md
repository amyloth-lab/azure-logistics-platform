# Overnight cost control

**Goal:** stop what can be stopped without deleting the platform.

## Use the scripts

```powershell
# Stop AKS and pause serverless SQL
.\scripts\stop-lab.ps1

# Resume the next day
.\scripts\start-lab.ps1
```

`stop-lab.ps1` asks you to type `STOP` unless you pass `-Force`.

The scripts do **not** delete resources and do **not** touch Terraform state.

## What can actually be stopped

| Service | Can pause? | Command / behavior |
|---|---|---|
| AKS cluster and nodes | **Yes** | `az aks stop` / `az aks start`; nodes are stopped |
| Azure SQL serverless database | **Yes** | `az sql db pause` / `az sql db resume` |
| Flex Consumption Function App | No fixed compute | Idle cost is effectively zero; no stop needed |
| Storage, Key Vault, Log Analytics | No | Consumption/operation charges continue |
| Public IP addresses | No | Billed while allocated; delete only |
| APIM Standard v2 | **No** | Fixed gateway cost continues |
| Azure Firewall Basic | **No** | Fixed cost continues |
| Azure Bastion Basic | **No** | Fixed cost continues |
| Service Bus Premium | **No** | Fixed namespace cost continues |
| ACR Premium | **No** | Fixed registry cost continues |
| Managed Redis | **No** | Fixed cache cost continues |
| App Service / App Gateway | Deferred | Not deployed in this lab |

Stopping AKS and SQL saves compute cost, but the fixed platform services above still bill overnight.

## Should you use `terraform destroy`?

Only if you are finished with the lab or need to eliminate **all** spend.

`terraform destroy` deletes:

- AKS and node pools
- APIM and its private endpoint
- Firewall, Bastion, VNet peerings, private DNS
- SQL, Storage, Service Bus, Redis
- ACR, Key Vault
- Private endpoints and role assignments

It does **not** delete the Terraform state storage account, which is bootstrapped separately.

Why not use it overnight:

- Rebuilding can take 1–2 hours.
- It may hit the same public IP, vCPU, and App Service quota limits.
- ACR/Key Vault deletion can be slow or protected by purge protection.
- Private DNS and endpoint recreation can fail halfway.
- It destroys data and audit history, not just compute.

Use `terraform destroy` only with a reviewed plan and a clear decision to rebuild. For a normal overnight pause, use the scripts.

## Check what remains

```powershell
az resource list `
  --resource-group rg-logistics-platform-dev `
  --query "[].{name:name,type:type}" `
  --output table

az resource list `
  --resource-group rg-logistics-workload-dev `
  --query "[].{name:name,type:type}" `
  --output table

az resource list `
  --resource-group rg-logistics-data-dev `
  --query "[].{name:name,type:type}" `
  --output table
```

## Budget guardrail

Keep the budget alert active. A budget alert does not stop spending; it only notifies you.

If you need a hard stop, the real options are:

1. Delete the fixed-cost services you do not need.
2. Destroy the environment.
3. Move the lab to a subscription with a spending cap.

# Logistics platform runbook

## 1. Access

AKS is private. Use:

```powershell
az aks command invoke `
  --resource-group rg-logistics-workload-dev `
  --name aks-logistics-dev `
  --command "kubectl get pods -n logistics"
```

Do not add a public API server or public IP for access.

## 2. Health checks

```powershell
az aks command invoke -g rg-logistics-workload-dev -n aks-logistics-dev `
  --command "helm list -n logistics; kubectl get pods,deploy,svc -n logistics"
```

APIM health:

```powershell
az aks command invoke -g rg-logistics-workload-dev -n aks-logistics-dev `
  --command "kubectl exec -n logistics deploy/logistics-api-logistics-api -- curl -fsS https://<apim-hostname>/logistics/health"
```

Expected:

```json
{"status":"ok"}
```

## 3. Roll back an image

Use the previous immutable digest:

```powershell
az aks command invoke -g rg-logistics-workload-dev -n aks-logistics-dev `
  --command "helm upgrade logistics-api oci://<acr>/helm/logistics-api --version <version> -n logistics --set image.digest=sha256:<previous> --atomic"
```

If using a local chart archive:

```powershell
az aks command invoke -g rg-logistics-workload-dev -n aks-logistics-dev `
  --file logistics-api-0.1.0.tgz --file values-dev.yaml `
  --command "helm upgrade logistics-api ./logistics-api-0.1.0.tgz -n logistics -f ./values-dev.yaml --set-string image.digest=sha256:<previous> --atomic"
```

Never roll back with `latest`.

## 4. Migration failure

```powershell
az aks command invoke -g rg-logistics-workload-dev -n aks-logistics-dev `
  --command "kubectl get jobs -n logistics; kubectl logs -n logistics job/logistics-api-logistics-api-migrate --tail=150"
```

Common causes:

- SQL firewall rule missing (`sql-private-endpoint`)
- SQL contained user missing
- wrong `DATABASE_URL`
- workload identity annotation missing

Migration rollback is not automated. Restore from a SQL point-in-time backup if a migration is destructive.

## 5. APIM backend failure

1. Confirm the AKS Service has IP `10.2.12.10`.
2. Test the API directly from a pod.
3. Confirm APIM API path `logistics` and backend `http://10.2.12.10:80`.
4. Check APIM outbound integration and private DNS.

Do not enable APIM public access.

## 6. AKS node failure

```powershell
az aks command invoke -g rg-logistics-workload-dev -n aks-logistics-dev `
  --command "kubectl get nodes; kubectl get pods -n logistics -o wide"
```

If a node is unhealthy, cordon/drain and let the node pool replace it. Do not manually delete node pool VMs unless instructed.

## 7. SQL restore

Azure SQL is serverless with point-in-time restore. Restore to a new database first, validate, then repoint the app.

Do not overwrite the production database during a restore test.

## 8. Key/secret rotation

- Entra app registration: rotate client credentials only if a client secret exists; the API uses JWT validation and has no client secret.
- Workload identity: rotate by recreating the federated credential; no static secret.
- ACR: no admin user; use Entra identities.

## 9. Cost control

```powershell
.\scripts\stop-lab.ps1
.\scripts\start-lab.ps1
```

See [cost-control.md](cost-control.md).

Fixed-cost services remain while stopped: APIM, Firewall, Bastion, Service Bus Premium, ACR Premium, Redis, public IPs.

## 10. Cleanup before handoff

- Remove the ACR public-access exception after the final build.
- Delete non-production resources.
- Verify no orphan public IPs, disks, or private endpoints.
- Check the budget.
- Remove local certificates, `.env`, and private keys.
- Keep Terraform state and the state storage account until the environment is retired.

## 11. Incident contacts

| Role | Contact |
|---|---|
| Platform owner | TODO |
| Security owner | TODO |
| Azure support | Azure portal support request |

Do not put real phone numbers or personal emails in the repository.

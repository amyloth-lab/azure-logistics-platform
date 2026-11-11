# Day 5 - Release, deployment, observability, cleanup

**Status:** Complete. Dev build, release, Helm deployment, migration, APIM smoke test, runbook, and cost controls are in place. Production gaps are documented in PROJECT-STATE.
**Goal:** promote the immutable image to dev AKS, prove the private path, add an approval gate, and leave a runbook.

> Read [PROJECT-STATE.md](../PROJECT-STATE.md) first.

---

## Checkpoint 5A - Green build

The build pipeline is blocked on Trivy zlib1g CVEs. The Dockerfile now upgrades `zlib1g` after pulling `python:3.12-slim-bookworm`.

1. Commit and push the Dockerfile fix.
2. Rerun the build pipeline.
3. Confirm:

```text
image: <acr>.azurecr.io/logistics-api:<BuildId>-<SourceVersion>
digest: sha256:...
Trivy: no HIGH/CRITICAL findings
```

Do not deploy an image that failed scanning.

Stop after 5A and reply `5A done`.

---

## Checkpoint 5B-0 - Production data path

Do not package the current SQLite app as if it uses Azure SQL.

Implemented:

1. `pyodbc` and `azure-identity` added; `msodbcsql18` installed in the runtime image.
2. `app/db.py` acquires an Azure SQL access token with `DefaultAzureCredential` when `DATABASE_URL` starts with `mssql+pyodbc`.
3. `infra/terraform/modules/api-identity/` creates the API user-assigned identity and AKS federated credential.
4. Blob and Service Bus role assignments are attached to that identity.
5. `deploy/helm/logistics-api/` includes the Deployment, ServiceAccount, internal LoadBalancer Service, and schema-init Job.

Still manual:

- Create the SQL contained user and grant `db_datareader`, `db_datawriter`, and the migration schema rights.
- Apply the identity Terraform.
- Build the image with the ODBC driver.
- Run the schema Job/Helm deployment and smoke test.

The app does not have Alembic migrations yet. The Helm hook uses `Base.metadata.create_all` as a temporary schema bootstrap; replace it with Alembic before production.

Only after the SQL user is created and the identity is federated should Helm deploy the API.

### Manual vs automated

| Task | Owner |
|---|---|
| Add `pyodbc`, `azure-identity`, ODBC driver | Code/Terraform |
| Token-based SQLAlchemy connection | Code |
| API user-assigned identity + AKS federation | Terraform |
| Role assignments for SQL/Redis/Blob/Service Bus | Terraform |
| Alembic/init job | Code/Terraform |
| Helm chart and APIM backend | Code/Terraform |
| **Create the contained SQL user and grant DB roles** | **Manual T-SQL** |
| **Provide SQL admin access to run that T-SQL** | **Manual** |
| Build image, run pipeline, deploy | Manual trigger |
| Smoke test from inside the VNet | Manual |

The contained SQL user is the main unavoidable manual step: `azurerm` does not create database principals inside Azure SQL. It must be run as the SQL Entra administrator.

Because SQL has no public access, you need one of:

- a temporary jumpbox/pod inside the VNet with `sqlcmd`, or
- a temporary SQL firewall/public-access exception for your client IP, reverted immediately after creating the user.

Do not enable SQL authentication. Keep Entra-only authentication.

Stop after 5B-0 and reply `5B-0 done`.

---

## Checkpoint 5B - AKS deployment assets

Create:

```text
deploy/helm/logistics-api/
  Chart.yaml
  values.yaml
  templates/
    deployment.yaml
    service.yaml
    serviceaccount.yaml
    ingress.yaml
    migration-job.yaml
```

Requirements:

- Namespace `logistics`.
- Non-root container, read-only root filesystem where possible.
- Probes: `/health` for liveness/readiness.
- Resources requests/limits.
- Workload identity annotation for the API service account.
- SQL/Redis/Service Bus/Blob access via managed identity; no connection-string secrets.
- Internal-only ingress or internal load balancer. No public Service.
- Migration job runs `alembic upgrade head` with a separate service account.

### Deploy the chart

The AKS API server is private, so use `az aks command invoke`, which runs `helm` inside the cluster.

Package the chart:

```powershell
helm package deploy\helm\logistics-api -d .tmp-chart
```

Prepare `values-dev.yaml`, then deploy:

```powershell
az aks command invoke `
  --resource-group rg-logistics-workload-dev `
  --name aks-logistics-dev `
  --file .tmp-chart\logistics-api-0.1.0.tgz `
  --file deploy\helm\logistics-api\values-dev.yaml `
  --command "helm upgrade --install logistics-api ./logistics-api-0.1.0.tgz -n logistics --create-namespace -f ./values-dev.yaml --atomic"
```

The chart creates:

- `logistics` namespace
- Deployment with 2 replicas
- ServiceAccount with workload identity
- Internal LoadBalancer Service at `10.2.12.10:80`
- Schema-init Job

Check:

```powershell
az aks command invoke `
  --resource-group rg-logistics-workload-dev `
  --name aks-logistics-dev `
  --command "kubectl get pods,svc -n logistics; kubectl logs -n logistics -l app.kubernetes.io/name=logistics-api --tail=50"
```

If the LoadBalancer stays `Pending`, check the AKS cluster identity has Network Contributor on the workload VNet and that `snet-aks-ingress` has a free address.

If the pod fails to pull from ACR with `EOF`, AKS is routing to the firewall but the private ACR endpoint is not allowed. The ACR private endpoint is in the management VNet `10.4.2.0/24`; add and apply the `acr-private-endpoint` network rule, then restart the pod.

If the pod reports `CreateContainerConfigError`, inspect the exact event:

```powershell
az aks command invoke `
  --resource-group rg-logistics-workload-dev `
  --name aks-logistics-dev `
  --command "kubectl describe pod -n logistics -l app.kubernetes.io/name=logistics-api | tail -40"
```

The image must use a numeric UID/GID because `runAsNonRoot: true` cannot verify a non-numeric `USER app`. Rebuild with UID/GID `10001:10001`.

If the migration Job fails with `ModuleNotFoundError: No module named 'pyodbc'`, the deployed image is older than the Dockerfile change. Rebuild, update the digest in `values-dev.yaml`, and verify:

```bash
docker run --rm <image> python -c "import pyodbc, azure.identity; print('ok')"
```

The Dockerfile now fails the build if either module is missing.

If pyodbc returns `FA005` about Access Token with Authentication/Integrated Security/User/Password, the SQLAlchemy URL path is adding `Trusted_Connection=Yes`. The app now builds the ODBC connection string explicitly and uses a connection creator with only the access-token attribute.

If SQL returns `HYT00 Login timeout expired`, the pod is not reaching the SQL private endpoint. AKS traffic goes through the firewall; add the `sql-private-endpoint` rule for `10.2.0.0/16` → `10.3.1.0/24:1433`, apply it, then delete and retry the migration Job. Confirm `sqldb-logistics` resolves to a `10.3.1.x` private IP from the pod.

Verify the ACR private IP and DNS:

```powershell
az network private-endpoint list `
  --resource-group rg-logistics-management-dev `
  --query "[?contains(name, 'acr')].{name:name,ip:customDnsConfigs[0].ipAddresses[0],state:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" `
  --output table
```

The pod must resolve the ACR hostname to that private IP, not a public address.

### APIM backend

The APIM module now creates:

- API `logistics-api`
- Path `logistics`
- Backend service URL `http://10.2.12.10:80`
- Operations for `/health`, `/api/v1/inventory`, and `/api/v1/orders` GET

Apply only the APIM module:

```powershell
cd infra\terraform\envs\dev
terraform plan "-target=module.apim" "-out=apim-api.tfplan"
terraform apply "apim-api.tfplan"
```

Smoke test from inside the cluster:

```powershell
az aks command invoke `
  --resource-group rg-logistics-workload-dev `
  --name aks-logistics-dev `
  --command "kubectl run curl --rm -it --image=curlimages/curl --restart=Never -- curl -s http://10.2.12.10/health"
```

Then test through APIM from the same pod:

```powershell
az aks command invoke `
  --resource-group rg-logistics-workload-dev `
  --name aks-logistics-dev `
  --command "kubectl run curl --rm -it --image=curlimages/curl --restart=Never -- curl -k https://<apim-hostname>/logistics/health"
```

Expected: `{"status":"ok"}`.

APIM JWT policy is not added yet; this checkpoint validates the private network path only. The API itself still enforces JWT on protected routes.

Stop after 5B and reply `5B done`.

---

## Checkpoint 5C - Release pipeline

`pipelines/release.yml` is added.

Trigger: tag `v*` or manual.

It consumes the **build pipeline artifact** `image-ref` and does not rebuild the image.

Pipeline resource name must match the **build pipeline display name** in Azure DevOps. It is normally the repository name:

```text
azure-logistics-platform
```

The name is not defined in `build.yml`; it is the UI display name. If your build pipeline was renamed, change `resources.pipelines[].source` to the exact name shown under **Pipelines → Pipelines**.

Variable group:

```text
vg-logistics-release
```

Required variables:

```text
AKS_RESOURCE_GROUP=rg-logistics-workload-dev
AKS_CLUSTER_NAME=aks-logistics-dev
AKS_RELEASE_SERVICE_CONNECTION=<release service connection>
APIM_HOST=<apim-hostname-without-https>
VALUES_DEV_SECURE_FILE=values-dev.yaml
```

Upload the real `values-dev.yaml` as a **secure file** in Azure DevOps Library. Do not commit it.

The release identity needs permission to run `az aks command invoke` on the cluster and to deploy the namespace. Give it only the required AKS scope, not subscription Owner.

The pipeline:

1. Downloads `image-ref`.
2. Extracts `sha256:...`.
3. Packages the Helm chart.
4. Runs `helm upgrade --install ... --atomic`.
5. Smoke tests `/logistics/health` through APIM.

The migration Job runs as a Helm `pre-upgrade` hook.

No production secrets in YAML. Use workload identity federation.

Stop after 5C and reply `5C done`.

---

## Checkpoint 5D - Approval, observability, runbook, cleanup

### Prod gate

Create an Azure DevOps environment `prod` with an approval check.

This lab does not provision a separate prod AKS/SQL stack, so do not fake a prod deployment. Configure the approval gate now; add the prod deployment stage only when a real prod environment and separate prod identity exist.

The dev release is complete and verified.

### Observability

- AKS Container Insights / Log Analytics.
- API structured logs with correlation ID.
- Alerts:
  - API 5xx rate
  - pod restart loop
  - SQL CPU/connection failures
  - Service Bus DLQ depth
  - ACR pull failures
- One trace from APIM to API to SQL, if OpenTelemetry is enabled.

### Runbook

Completed in [runbook.md](../runbook.md):

- access and health checks
- stop/start cost procedure
- image rollback by digest
- migration failure
- APIM backend failure
- AKS node failure
- SQL restore
- key rotation
- cleanup and incident contacts

### Cleanup

- Delete non-prod resources.
- Remove ACR public access exception.
- Verify no orphan public IPs, disks, or private endpoints.
- Check the budget.

---

## Day 5 acceptance

- [ ] Green build with immutable digest.
- [ ] API deployed to AKS.
- [ ] APIM reaches the internal service privately.
- [ ] Migration job succeeds.
- [ ] Smoke tests pass from inside the VNet.
- [ ] Prod approval gate exists.
- [ ] Alerts and runbook exist.
- [ ] ACR public exception removed.
- [ ] Cost cleanup documented.

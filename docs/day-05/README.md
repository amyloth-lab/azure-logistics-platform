# Day 5 - Release, deployment, observability, cleanup

**Status:** Day 4 closed with one open item: the first green Azure DevOps build.
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

### APIM backend

APIM already exists and is private. Configure its backend to the internal AKS service:

- Install an internal ingress controller or use an internal load balancer.
- Use a private DNS name such as `api.logistics.internal`.
- Do not expose a public AKS endpoint.
- Keep APIM public access disabled.

Smoke test from inside the cluster:

```powershell
az aks command invoke `
  --resource-group rg-logistics-workload-dev `
  --name aks-logistics-dev `
  --command "kubectl run curl --rm -it --image=curlimages/curl --restart=Never -- curl -k https://<internal-host>/health"
```

Stop after 5B and reply `5B done`.

---

## Checkpoint 5C - Release pipeline

Create `pipelines/release.yml`.

Trigger: tag `v*` or manual.

Input: the image digest artifact from the build pipeline. Do not rebuild.

Stages:

1. Download and verify the image digest.
2. Helm lint/template.
3. Apply the migration job.
4. Helm upgrade with `--atomic`.
5. Smoke tests from inside the VNet.
6. Publish release evidence.

Identities:

- Build pipeline: AcrPush only.
- Dev release: AKS deploy + SQL migration rights.
- Prod release: separate identity and approval.

No production secrets in YAML. Use workload identity federation.

Stop after 5C and reply `5C done`.

---

## Checkpoint 5D - Approval, observability, runbook, cleanup

### Prod gate

Create an Azure DevOps environment `prod` with an approval check. The release must pause before prod.

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

Document:

- stop/start cost procedure
- image rollback by digest
- migration rollback
- APIM backend failure
- AKS node failure
- SQL failover/restore
- key rotation
- incident contacts

### Cleanup

- Delete non-prod resources.
- Remove ACR public access exception.
- Verify no orphan public IPs, disks, or private endpoints.
- Check the budget.

Stop after 5D and reply `EOD`.

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

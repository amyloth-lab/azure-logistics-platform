# Day 4 - FastAPI, Entra auth, tests, build pipeline

**Status:** 4A, 4B, and 4C complete; 4D build pipeline added, Azure DevOps run pending.
**Time:** 4-5 hours
**Goal:** Build the Python logistics API, enforce Entra authentication and RBAC, prove it with tests, and produce an immutable build artifact.

> Read [PROJECT-STATE.md](../PROJECT-STATE.md) first. Day 3B is complete with documented gaps: App Service, public WAF edge, and Ansible VM are deferred. APIM is private-only.

---

## What exists before Day 4

- Private AKS cluster with system and user node pools.
- Private APIM Standard v2, public access disabled.
- Private ACR, Key Vault, Azure SQL, Blob Storage, Service Bus Premium, Managed Redis.
- Flex Consumption Function App with private storage and Service Bus receiver.
- No public API endpoint.

The Day 4 app is built and tested locally, then containerized and pushed to ACR. Deployment is Day 5.

---

## API contract

Two resources:

```text
GET    /health
GET    /api/v1/inventory
GET    /api/v1/inventory/{sku}
POST   /api/v1/inventory
PATCH  /api/v1/inventory/{sku}
DELETE /api/v1/inventory/{sku}        manager only

GET    /api/v1/orders
GET    /api/v1/orders/{id}
POST   /api/v1/orders
PATCH  /api/v1/orders/{id}
DELETE /api/v1/orders/{id}            manager only

POST   /api/v1/partner/webhooks/carrier
```

Authorization matrix:

| Action | Required role | Normal user | Manager |
|---|---|---|---|
| Read inventory | `Inventory.Reader` | Yes | Yes |
| Create/update inventory | `Inventory.Contributor` | Yes | Yes |
| Delete inventory | `Logistics.Manager` | No | Yes |
| Read own order | `Order.Reader` | Yes | Yes |
| Read another user's order | `Order.Reader` + manager | No | Yes |
| Create order | `Order.Contributor` | Yes, for self | Yes, for self |
| Update own order | `Order.Contributor` | Yes | Yes |
| Delete order | `Logistics.Manager` | No | Yes |

Authentication and authorization are separate:

- **Authentication:** valid Entra access token.
- **Authorization:** app role plus ownership rule.

---

# Checkpoint 4A - FastAPI skeleton

## Step 1 - Use the existing app layout

The repository already has the canonical directories. Do **not** create `apps/api`.

```text
app/
  README.md              # existing API contract; do not overwrite
  __init__.py
  main.py
  config.py
  db.py
  models.py
  schemas.py
  security.py
  dependencies.py
  routers/
    __init__.py
    inventory.py
    orders.py
tests/
  conftest.py
  test_health.py
  test_inventory.py
  test_orders.py
pyproject.toml           # repository root
Dockerfile               # repository root
alembic.ini              # repository root
migrations/
  env.py
  versions/
```

The Python package is `app`; the filesystem directory is the existing `app/` at the repository root. Tests stay in the existing root `tests/` directory. Pipelines stay in `pipelines/`.

All commands below run from the repository root, not from inside `app/`.

## Step 2 - Add dependencies

Use:

- `fastapi`
- `uvicorn[standard]`
- `pydantic-settings`
- `sqlalchemy`
- `alembic`
- `pyjwt[crypto]`
- `httpx2>=2.0` (Starlette TestClient dependency; `httpx` alone triggers a deprecation warning)
- `redis`
- `pytest>=9.0.3` (PYSEC-2026-1845 fix)
- `ruff`

Pin versions in `pyproject.toml`. Do not use floating ranges for the final build.

## Step 3 - Configuration

`config.py` reads environment variables, never hard-coded secrets:

```text
SQL_SERVER_FQDN
SQL_DATABASE
REDIS_HOST
REDIS_PORT
SERVICEBUS_NAMESPACE
SERVICEBUS_TOPIC
BLOB_ACCOUNT_URL
BLOB_CONTAINER
ENTRA_TENANT_ID
ENTRA_AUDIENCE
ENTRA_ISSUER
ENTRA_JWKS_URL
LOG_LEVEL
```

For local tests, use SQLite and a fake token verifier. For Azure, use managed identity where possible; do not put SQL passwords in the image.

## Step 4 - Models

`InventoryItem`:

- `id` UUID
- `sku` unique
- `name`
- `quantity`
- `unit_price`
- `created_at`, `updated_at`

`Order`:

- `id` UUID
- `owner_oid` (Entra object ID)
- `items` JSON or order-lines table
- `status`
- `total`
- `created_at`, `updated_at`

Do not use the user's email as the ownership key. Use the immutable Entra object ID (`oid`) or `sub`.

## Step 5 - Health and CRUD

Implement:

- `/health` returns `{"status":"ok"}` without auth.
- Inventory and orders routers behind auth.
- Validation with Pydantic.
- Pagination with `limit`/`offset`.
- No raw SQL string concatenation.

## Step 6 - Local test run

Use **Python 3.12 or 3.13**, not 3.15. The DSH bundled interpreter is 3.12:

```text
C:\Users\OEM\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe
```

```powershell
cd "C:\Users\OEM\Documents\deepseek-harness\default-workspace"
& "C:\Users\OEM\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe" -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e ".[dev]"
pytest -q
```

Acceptance:

- [ ] `/health` tests pass.
- [ ] Inventory CRUD tests pass.
- [ ] Order ownership tests pass.
- [ ] No database or Redis required for unit tests.

4A is complete when the skeleton tests are green; continue with 4B.

---

# Checkpoint 4B - Entra authentication and RBAC

## Step 1 - App registration with Terraform

The registration is managed by `infra/terraform/modules/entra/`. It creates:

- API app registration `logistics-api`.
- Application ID URI `api://logistics-api`.
- v2 access tokens.
- `access_as_user` scope.
- App roles:
  - `Inventory.Reader`
  - `Inventory.Contributor`
  - `Order.Reader`
  - `Order.Contributor`
  - `Logistics.Manager`
  - `Partner.Webhook`
- Service principal.
- Five user roles assigned to the Terraform caller.

Prerequisites:

- Terraform caller has **Application Administrator** or **Cloud Application Administrator**.
- Graph permission to assign app roles, or assign the roles in the portal after the app is created.
- `azuread` provider authenticated through Azure CLI.

Apply only the Entra module:

```powershell
cd "C:\Users\OEM\Documents\deepseek-harness\default-workspace\infra\terraform\envs\dev"

terraform init -backend-config=backend.hcl
terraform validate
terraform plan -target=module.entra -out=entra.tfplan
terraform apply entra.tfplan
```

If init fails with the `.azure` permission error:

```powershell
icacls "$env:USERPROFILE\.azure" /grant "$($env:USERNAME):(OI)(CI)F" /T
az login
```

Get the values:

```powershell
terraform output -raw entra_tenant_id
terraform output -raw entra_audience
terraform output -raw entra_issuer
terraform output -raw entra_jwks_url
terraform output -raw entra_client_id
```

Set them in `.env`:

```text
ENTRA_TENANT_ID=<output>
ENTRA_AUDIENCE=api://logistics-api
ENTRA_ISSUER=<output>
ENTRA_JWKS_URL=<output>
ENTRA_CLIENT_ID=<entra_cli_client_id>
ENTRA_SCOPE=api://logistics-api/access_as_user
```

`assign_roles_to_current_user = true` assigns the five human roles to whoever runs Terraform. If Terraform runs as a service principal, set it to `false` and assign roles to your user/group in Entra.

Do not use client secrets in the API. The API validates tokens; it does not call Graph.

`ENTRA_AUDIENCE` must match the token's `aud` claim. Decode a token at `jwt.ms` and confirm `aud`, `iss`, `tid`, `oid`, and `roles`.

### Why Azure CLI fails

Azure CLI is the client app `04b07795-...` (Microsoft Azure CLI). It cannot request a token for an arbitrary custom API:

```text
AADSTS650057 Invalid resource
```

That is not fixed by `az login --scope` or by admin consent. The CLI app registration does not list your API as a resource. Do not keep retrying it.

The module creates a dedicated public client `logistics-cli` with:

- redirect URI `http://localhost`
- delegated permission `access_as_user` on `logistics-api`
- a delegated permission grant

### Get a user token with the device-code flow

After applying the Entra module:

```powershell
terraform output -raw entra_cli_client_id
```

Save `.env` at the repository root:

```text
C:\Users\OEM\Documents\deepseek-harness\default-workspace\.env
```

Set:

```text
ENTRA_CLIENT_ID=<entra_cli_client_id>
ENTRA_SCOPE=api://logistics-api/access_as_user
```

`scripts/get_token.py` calls `load_dotenv()` and reads this root `.env`.

Install dev dependencies and run:

```powershell
.\.venv\Scripts\Activate.ps1
pip install -e ".[dev]"

$token = python scripts\get_token.py
```

The script prints a device-login message to stderr and the access token to stdout.

1. Open the printed URL.
2. Enter the code.
3. Sign in as the user with the app roles.
4. Accept the `logistics-api` consent.

Then:

```powershell
curl.exe -H "Authorization: Bearer $token" `
  http://127.0.0.1:8000/api/v1/inventory
```

If the tenant blocks consent, an Entra admin must grant consent to the `logistics-cli` app, not to Azure CLI. The Terraform delegated permission grant may itself require admin rights.

### If sign-in says “You don't have access to this”

The user authenticated successfully but is not assigned to the `logistics-api` enterprise application, or has no app role.

Check the signed-in user object ID:

```powershell
az ad signed-in-user show `
  --query "{id:id,upn:userPrincipalName}" `
  --output table
```

If that ID differs from the Terraform caller, set it explicitly:

```hcl
entra_role_assignment_object_id = "<signed-in-user-object-id>"
```

Then apply only the Entra module:

```powershell
terraform plan "-target=module.entra" "-out=entra.tfplan"
terraform apply "entra.tfplan"
```

Alternatively assign the user in the portal:

**Entra ID → Enterprise applications → logistics-api → Users and groups → Add user/group**

Assign at least `Logistics.Manager` for the delete test, plus the reader/contributor roles.

Also confirm **logistics-cli → API permissions → Grant admin consent** has been completed.

### If sign-in fails with AADSTS530035

`whrsoft@gmail.com` is a personal/Gmail account. Error `530035` means the account is not authorized in the resource tenant, even though authentication succeeded. It is not an API problem.

Choose one:

1. **Use a tenant member account** — create a cloud-only member user such as `lab-user@<tenant>.onmicrosoft.com`, assign the app roles to that object ID, and sign in with it.
2. **Invite the Gmail account as a guest** — Entra ID → Users → Invite external user; accept the invitation; then assign the app roles to the guest object ID.

After either change, update `entra_role_assignment_object_id` and re-apply `-target=module.entra`.

If Terraform returns `Permission being assigned already exists on the object`, the role assignment exists outside Terraform state. Remove the user's assignments on `logistics-api` in **Enterprise applications → Users and groups**, then re-apply. For a clean lab state, remove all five assignments for that user and let Terraform recreate them.

If the sign-in log shows a Conditional Access policy, exclude the lab user or use a compliant device. Entra ID Free normally does not include Conditional Access; if a policy exists, the tenant may have a trial or add-on. Do not disable tenant-wide security controls just to make the lab work.

The error page showing **Device state: Unregistered** is a strong signal of a policy requiring a compliant or Entra-joined device. Open:

**Entra ID → Monitoring & health → Sign-in logs → filter by the Request ID or Correlation ID → Conditional Access tab**

Read the policy name and result. If it requires a compliant device, either:

- exclude `manager@whrsoftgmail.onmicrosoft.com` from that one policy, or
- use a compliant/Entra-joined device.

A targeted user exclusion is safer than disabling the policy tenant-wide. If no Conditional Access policy exists, check **Enterprise applications → logistics-api → Properties → Assignment required?** and assign the user if needed.

A test-only confidential client with `Logistics.Manager` and client credentials can prove manager authorization, but it does not prove user own-order behavior. Record that gap if you use it.

## Step 2 - JWT validation

`app/security.py` now:

- Requires `Authorization: Bearer <token>`.
- Fetches JWKS from Entra with `PyJWKClient` and caches signing keys.
- Verifies signature, `iss`, `aud`, `exp`, and `iat`.
- Restricts algorithms to `RS256` (no `none`, no algorithm confusion).
- Checks `tid` against `ENTRA_TENANT_ID`.
- Requires an immutable user object ID (`oid`, falling back to `sub`).
- Reads app roles from the `roles` claim.

Configuration is read from:

```text
ENTRA_TENANT_ID
ENTRA_AUDIENCE
ENTRA_ISSUER
ENTRA_JWKS_URL
```

Use [.env.example](../../.env.example) as the template. Never commit `.env`.

The local `DEV_AUTH_ENABLED` shim remains available for manual UI work, but defaults to `false`. It is not an Azure authentication path.

## Step 3 - Dependencies

Create:

```python
require_token()
require_role("Logistics.Manager")
current_user_oid()
```

Rules:

- Missing/invalid token -> `401`.
- Valid token, insufficient role -> `403`.
- Normal user reading another user's order -> `404`, not `403`, to avoid leaking existence.

## Step 4 - Manager delete

Only `Logistics.Manager` can call:

```text
DELETE /api/v1/inventory/{sku}
DELETE /api/v1/orders/{id}
```

Normal users can create/update their own orders but cannot delete.

## Step 5 - APIM validation

APIM must also validate the JWT before forwarding. The API validates again. Two layers:

- APIM rejects unauthenticated traffic at the edge.
- FastAPI enforces resource-level authorization.

Do not rely on APIM alone for ownership checks.

Stop after 4B and reply `4B done`.

---

# Checkpoint 4C - Tests

Tests are in place and cover:

- No token / query-string token -> 401.
- Expired token -> 401.
- Wrong audience / tenant -> 401.
- Missing `oid`, missing header, malformed header -> 401.
- Missing app role -> 403.
- Normal user and contributor cannot delete inventory -> 403.
- Manager can delete inventory -> 204.
- Non-order role cannot list orders -> 403.
- Normal user cannot read/update another user's order -> 404.
- Manager can read all orders.
- Normal user can read own order.

Expected count: **18 passed**.

Run:

```powershell
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\ruff.exe check .
```

Do not call Entra in unit tests; the JWT tests use a local RSA key and fake JWKS client.

Stop after 4C and reply `4C done`.

---

# Checkpoint 4D - Build pipeline

**Added:** `pipelines/build.yml` and `Dockerfile`.

Stages:

1. **Test**
   - Python 3.12
   - `pip install -e ".[dev]"`
   - `pytest` with JUnit results
   - `ruff`
2. **Security**
   - `pip freeze --exclude-editable` → `pip-audit -r requirements-audit.txt`
   - Bandit
   - Gitleaks
3. **Build**
   - local `docker build` + `docker push` to ACR with immutable tag `$(Build.BuildId)-$(Build.SourceVersion)`
   - Trivy image scan on the local image
   - publish image digest

ACR Tasks is intentionally not used. This subscription returns `TasksOperationsNotAllowed` for `az acr build`; local Docker build avoids that restriction while keeping the AcrPush-only identity.
4. **No deploy**

Azure DevOps prerequisites:

- Variable group `vg-logistics-build` with:
  - `ACR_NAME`
  - `azureServiceConnection`
- Service connection using an identity with **AcrPush**, not Contributor/Owner.
- ACR Premium and ACR Tasks enabled.

Run the pipeline from Azure DevOps after committing. The build must not deploy.

Rules:

- Build pipeline has **AcrPush**, not deployment rights.
- Release pipeline has deployment rights, not ACR admin.
- No secrets in YAML; use variable groups/Key Vault.
- Image tag is immutable; do not use `latest` for deployment.

Stop after 4D and reply `4D done`.

---

## Day 4 acceptance

- [ ] API runs locally.
- [ ] Authentication and RBAC tests pass.
- [ ] Manager-only delete works.
- [ ] Own-order isolation works.
- [ ] Build pipeline produces an image in ACR.
- [ ] No public endpoint is required.

At EOD, update `PROJECT-STATE.md` and reply `EOD`. Day 5 is release and deployment.

# Copilot Instructions for This Repository

You are assisting with a production-shaped Azure logistics platform. Optimize for security, operability, and clarity, not for the shortest possible code.

## Architecture rules

- Hub-and-spoke network. App Gateway is the only public application entry point.
- No public IP on AKS nodes, App Service, Functions, SQL, Redis, Storage, Key Vault, Service Bus, or ACR.
- Private endpoints and private DNS for all PaaS data services.
- AKS hosts the core FastAPI API. App Service hosts the partner webhook. Functions handle events.
- APIM Standard v2 uses an inbound private endpoint and a separate outbound VNet integration subnet. Do not suggest classic VNet injection.
- App Service VNet integration is outbound only; inbound private access uses a private endpoint.

## Identity rules

- Microsoft Entra ID is the identity provider.
- Authentication and authorization are separate. A valid token is not permission.
- App roles: `Inventory.Reader`, `Inventory.Contributor`, `Order.Reader`, `Order.Contributor`, `Logistics.Manager`, `Partner.Webhook`.
- Managers are the only business role allowed to delete inventory/orders.
- Normal users can only access their own orders.
- Use managed identities / workload identity federation. No connection strings, keys, or PATs in code or YAML.
- Do not log tokens, cookies, authorization headers, or full request bodies.

## Infrastructure rules

- Terraform provisions infrastructure; Ansible configures Linux VMs and the Kubernetes baseline. Do not use Ansible to configure AKS node OS components.
- Terraform state is in Azure Blob with Entra-only auth, private endpoint, versioning, soft delete, and lease locking.
- Pin provider and module versions. Commit `.terraform.lock.hcl`.
- No `latest` tags. No public storage. No SQL authentication. No shared keys.
- Every resource needs tags: `env`, `owner`, `costCenter`, `workload`, `dataClassification`, `managedBy`.
- Prefer small modules with explicit inputs/outputs over one giant root module.

## Python rules

- Python 3.12, FastAPI, Pydantic v2, SQLAlchemy 2, Alembic.
- Type hints on public functions. `ruff` and `mypy` clean.
- Parameterized queries/ORM only. No string-built SQL.
- Validate all input. Return generic 500 errors; keep details in structured logs.
- Tests must include 401, 403, 404, ownership, and manager-delete cases.
- Use dependency injection for auth, database, cache, and clock so tests are deterministic.

## CI/CD rules

- Build and release are separate pipelines and identities.
- Build can push to ACR; it cannot deploy.
- Release can deploy; it cannot push images.
- Pin actions/tasks and base images. Generate an SBOM. Scan dependencies and images.
- Prod requires environment approval and a reviewed Terraform plan.
- Never put secrets in pipeline YAML. Use workload identity federation.

## How to respond

- When reviewing, list concrete security or correctness problems first, then style.
- When generating code, include tests and error handling.
- When a request conflicts with these rules, say so and propose the compliant alternative.
- Do not invent Azure features or SKU capabilities. If unsure, state the assumption and ask for verification.

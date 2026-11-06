# Identity, Authentication, Authorization, and RBAC

**Status:** Accepted with the Entra ID Free constraint (ADR-0011)
**Scope:** Users, partners, workloads, pipelines, and platform administrators

---

## 1. The separation that matters

| Layer | Question | Owner | Mechanism |
|---|---|---|---|
| Authentication (authN) | Who are you? | Microsoft Entra ID | OIDC/OAuth 2.0, MFA via security defaults, token signature |
| Authorization (authZ) | What may you do? | API and APIM | App roles, scopes, route policy, resource ownership |
| Workload identity | What may this service do? | Platform | Managed identity / workload identity federation |
| Cloud RBAC | What may this principal change in Azure? | Platform | Azure RBAC, manual JIT, scoped role assignments |
| Data authorization | Which rows may this user see? | Application + database | Ownership predicate, row-level security if needed |

**Authentication must not be treated as authorization.** A valid token proves identity. It does not prove permission. A logged-in user with no role must receive `403`, not a default allow.

**A token is not a session.** The API should not create a server-side session from a JWT, should not accept ID tokens as API credentials, and should not put tokens in URLs or logs. Interactive clients use authorization code + PKCE and keep refresh tokens on the client. Service clients use client credentials or, better, workload identity federation.

### 1.1 Entra ID Free is a project constraint

This tenant has **Microsoft Entra ID Free**, not P1/P2. (Entra editions are Free, P1, and P2; "Premium v2" is an APIM tier, not an Entra license.) The design must not assume Conditional Access or PIM.

| Capability | Entra ID Free | Replacement in this project |
|---|---|---|
| OIDC/OAuth 2.0, app registrations, app roles, groups | Yes | Use as designed |
| Managed identities | Yes | Use as designed |
| Workload identity federation | Yes | Use as designed |
| Security defaults / MFA | Yes (all-or-nothing, Authenticator app) | Enable security defaults; no per-group Conditional Access |
| Conditional Access | No (P1) | Security defaults + admin discipline; document the gap |
| PIM / time-bound role activation | No (P2) | Manual JIT request/approval, separate admin account, remove after task |
| Access reviews | No (P2/Governance) | Manual quarterly review with exported assignments |
| Risk-based policies / ID Protection | No (P2) | Sign-in log alerts; no automated risk remediation |
| Custom Entra roles | No (P1) | Built-in roles only |
| Sign-in and audit logs | Yes | Export to Log Analytics; alert on identity changes |

Read [ADR-0011](../adr/0011-entra-id-free-license.md) for the full decision and compensating controls. The rest of this document describes the target design; where it says "PIM" or "Conditional Access" in a historical context, the Free-tier control above applies.

**Immediate action:** in the Entra admin center, verify that **security defaults** are enabled. If they are disabled, either enable them or document the existing MFA enforcement and the reason it is equivalent. Do not leave the tenant with password-only sign-in and call it zero trust.

---

## 2. Entra ID objects

### 2.1 App registrations

| Registration | Type | Purpose | Key configuration |
|---|---|---|---|
| `logistics-api` | API | Resource/audience for access tokens | Application ID URI `api://logistics-api`; scopes; app roles; v2 access tokens |
| `logistics-cli` | Public client | Interactive user/CLI sign-in | Authorization code + PKCE; redirect URI; no client secret |
| `logistics-partner` | Confidential client | Partner service-to-service | Client credentials; certificate or federated credential preferred; app role assignment |
| `logistics-pipeline-build` | Workload identity | Build pipeline | Federated credential to Azure DevOps; AcrPush only |
| `logistics-pipeline-release-dev` | Workload identity | Dev release | Federated credential; scoped deploy rights |
| `logistics-pipeline-release-prod` | Workload identity | Prod release | Separate identity; approval-gated environment |

### 2.2 Security groups

| Group | Members | Assigned app role(s) |
|---|---|---|
| `grp-log-inventory-readers` | Warehouse operators | `Inventory.Reader` |
| `grp-log-inventory-contributors` | Senior warehouse staff | `Inventory.Reader`, `Inventory.Contributor` |
| `grp-log-order-readers` | Customer service | `Order.Reader` |
| `grp-log-order-contributors` | Customer service | `Order.Reader`, `Order.Contributor` |
| `grp-log-managers` | Logistics managers | `Inventory.Reader`, `Inventory.Contributor`, `Order.Reader`, `Order.Contributor`, `Logistics.Manager` |
| `grp-log-platform-admins` | Platform team | No app role; manual JIT platform administration |
| `grp-log-security-auditors` | Security | No app role; read-only Azure/Log Analytics |

Use groups, not individual assignments, for business roles. Group membership changes are auditable and reviewable. Keep group owners accountable.

### 2.3 App roles

| Value | Display name | Allowed member types | Meaning |
|---|---|---|---|
| `Inventory.Reader` | Inventory Reader | Users/Groups, Applications | Read inventory |
| `Inventory.Contributor` | Inventory Contributor | Users/Groups | Read and write inventory; no delete |
| `Order.Reader` | Order Reader | Users/Groups, Applications | Read own orders; manager reads all |
| `Order.Contributor` | Order Contributor | Users/Groups | Create/update own orders; no delete |
| `Logistics.Manager` | Logistics Manager | Users/Groups | Read all; delete inventory/orders; approve cancellation |
| `Partner.Webhook` | Partner Webhook | Applications | Post carrier webhook events only |

Set `allowedMemberTypes` deliberately. Do not allow applications to receive `Logistics.Manager`.

### 2.4 Delegated scopes

| Scope | Admin consent | Used by |
|---|---|---|
| `api://logistics-api/Inventory.Read` | No (user consent may be allowed) | `logistics-cli` |
| `api://logistics-api/Inventory.Write` | Yes | `logistics-cli` |
| `api://logistics-api/Orders.Read` | No | `logistics-cli` |
| `api://logistics-api/Orders.Write` | Yes | `logistics-cli` |
| `api://logistics-api/.default` | N/A | Client credentials |

Scopes are **requested access**. Roles are **granted capability**. A delegated token can contain `scp=Orders.Write` and still lack `roles=Order.Contributor`; the API must deny the write.

---

## 3. Endpoint authorization matrix

| Endpoint | Method | APIM check | API check | Resource rule |
|---|---|---|---|---|
| `/health` | GET | None | None | Internal only; no data |
| `/api/v1/inventory` | GET | `Inventory.Reader` | `require_role("Inventory.Reader")` | None |
| `/api/v1/inventory/{sku}` | GET | `Inventory.Reader` | `require_role("Inventory.Reader")` | None |
| `/api/v1/inventory` | POST | `Inventory.Contributor` | `require_role("Inventory.Contributor")` | Validate SKU/location |
| `/api/v1/inventory/{sku}` | PATCH | `Inventory.Contributor` | `require_role("Inventory.Contributor")` | Optimistic concurrency |
| `/api/v1/inventory/{sku}` | DELETE | `Logistics.Manager` | `require_role("Logistics.Manager")` | Audit before/after |
| `/api/v1/orders` | GET | `Order.Reader` | `require_role("Order.Reader")` | Filter by `customer_id = token.oid` unless manager |
| `/api/v1/orders/{id}` | GET | `Order.Reader` | `require_role("Order.Reader")` | Own order or manager |
| `/api/v1/orders` | POST | `Order.Contributor` | `require_role("Order.Contributor")` | `customer_id` must match token |
| `/api/v1/orders/{id}` | PATCH | `Order.Contributor` | `require_role("Order.Contributor")` | Own draft or manager |
| `/api/v1/orders/{id}` | DELETE | `Logistics.Manager` | `require_role("Logistics.Manager")` | Audit + soft delete |
| `/api/v1/orders/{id}/cancel` | POST | `Order.Contributor` | `require_role("Order.Contributor")` | Own order or manager |
| `/api/v1/partner/webhooks/carrier` | POST | `Partner.Webhook` | `require_role("Partner.Webhook")` | `carrier_id` must match token |

### 3.1 Manager-only delete

Deletes are business operations, not cloud administration. The manager role is enforced in the API. APIM can pre-check the role to fail fast and reduce load, but APIM is not the only enforcement point.

Every delete must write an immutable audit record:

```json
{
  "event": "inventory.deleted",
  "actor_oid": "user-object-id",
  "actor_roles": ["Logistics.Manager"],
  "resource_id": "SKU-123",
  "before_hash": "sha256:...",
  "correlation_id": "b7c1...",
  "timestamp_utc": "2026-11-03T04:12:00Z"
}
```

### 3.2 Own-order rule

Use the token's `oid` (stable user object ID) to resolve the application's customer/user record. Do not use `sub` as a database key because it is pairwise per application; it is stable only within the app, but `oid` is easier to reconcile with directory data. Document the mapping.

```text
if "Logistics.Manager" in roles:
    allow read/update/delete according to endpoint
elif order.customer_id == principal.customer_id:
    allow read/update/cancel
else:
    return 404
```

Returning `404` for another user's order avoids leaking existence. Use the same behavior consistently and test it.

---

## 4. Token validation contract

### 4.1 Claims to validate

| Claim | Expected | Why |
|---|---|---|
| `iss` | `https://login.microsoftonline.com/<tenant-id>/v2.0` | Token from your tenant |
| `aud` | `api://logistics-api` | Token intended for this API |
| `exp` / `nbf` | Valid with <= 2 minutes skew | Reject expired/not-yet-valid tokens |
| `tid` | Your tenant ID | Defense against issuer confusion |
| `scp` or `roles` | Required scope/role | Authorization |
| `azp` / `appid` | Approved client | Partner/client allow-list |
| `oid` | Present for user tokens | Ownership mapping |
| `ver` | `2.0` | Consistent claim semantics |

### 4.2 Validation sequence

```text
1. Extract Bearer token from Authorization header.
2. Reject missing/malformed/oversized tokens.
3. Fetch JWKS (cached, refreshed on unknown kid).
4. Verify signature and algorithm allow-list (RS256).
5. Verify issuer, audience, tenant, lifetime.
6. Verify scope/role for the route.
7. Resolve principal and ownership.
8. Authorize the action.
9. Emit audit/correlation log without the token.
```

Do not implement JWT cryptography by hand. Use a maintained library such as `PyJWT` with `PyJWKClient` or `fastapi-azure-auth`, pinned and scanned.

### 4.3 Error behavior

| Condition | Status | Body |
|---|---|---|
| Missing header | 401 | `{"error":"unauthorized"}` + `WWW-Authenticate: Bearer` |
| Invalid signature/issuer/audience | 401 | Do not reveal which check failed |
| Expired token | 401 | `invalid_token` |
| Valid token, missing role | 403 | `{"error":"forbidden"}` |
| Valid token, other user's order | 404 | Avoid existence leak |
| Valid token, unsupported method | 405 | Standard |

Never log `Authorization`, `Cookie`, `Set-Cookie`, full request bodies, or token query parameters. Log `correlation_id`, `oid`, `azp`, route, status, and latency.

---

## 5. Azure RBAC and separation of duties

### 5.1 Human access

| Principal | Permanent | Just-in-time | Approval |
|---|---|---|---|
| Platform engineer | Reader at subscription | Contributor on platform RG | Manual JIT request, 4-hour window, remove after task |
| Platform engineer | Reader at subscription | Contributor on workload RG (prod) | Manual JIT, 2-hour window, peer approval |
| Security auditor | Reader + Log Analytics Reader | None | Manual quarterly access review |
| Developer | Reader on workload RG | None for prod; dev Contributor by named request | Team lead approval |
| Break-glass | None | Owner at subscription | Hardware key/MFA, alerting, post-use review |

No standing `Owner` at subscription scope. No standing `User Access Administrator`. Without PIM, there is **no native time-bound activation**: the ticket, the separate admin account, the short window, and the post-use removal are the controls. Remove the assignment when the task is done and verify it is gone.

Every manual JIT record includes: requester, role, scope, reason, start/end time, approver, and change ticket. Do not store these records in Git if they contain account identifiers.

### 5.2 Pipeline identities

| Identity | Scope | Permissions | Cannot do |
|---|---|---|---|
| `id-build-logistics` | ACR | `AcrPush` | Deploy, read Key Vault, change RBAC |
| `id-release-dev` | `rg-logistics-dev` | `Contributor`, `Role Based Access Control Administrator`, `Storage Blob Data Contributor` on state | Push images, access prod |
| `id-release-prod` | `rg-logistics-prod` | Same, prod scope | Push images, access dev state |
| `id-agent` (VM) | Key Vault | `Key Vault Secrets User` for agent registration token | Deploy without pipeline identity |
| `id-ansible` (VM) | Management RG | `Reader`, `Key Vault Secrets User` | Change Azure resources outside Ansible scope |

`Role Based Access Control Administrator` is still a powerful role. Scope it to the workload resource group, require environment approval, and review role assignments in the Terraform plan. In a larger organization, split infrastructure and application pipelines and give the application pipeline no RBAC-write permission at all.

### 5.3 Managed identities

| Identity | Attached to | Permissions |
|---|---|---|
| `id-logistics-api` | AKS workload identity | SQL `db_datareader`, `db_datawriter`; Redis data access; Blob `Storage Blob Data Contributor` on documents container; Service Bus Data Sender |
| `id-logistics-migrator` | AKS migration job | SQL `db_ddladmin`; no runtime access |
| `id-partner-webhook` | App Service | Service Bus Data Sender; Key Vault Secrets User (if a third-party secret is unavoidable) |
| `id-order-events` | Function App | Service Bus Data Receiver; SQL `db_datawriter`, `db_datareader`; Blob Data Contributor; Key Vault Secrets User |
| `id-apim` | APIM | Key Vault Secrets User (mTLS cert) |
| `id-appgw` | App Gateway | Key Vault Secrets User (TLS cert) |
| `id-ansible` | Ansible VM | Key Vault Secrets User; Reader on relevant RGs |
| `id-agent` | Agent VM | Key Vault Secrets User for registration token |

Use separate identities per workload. Do not give the API identity permission to send to every Service Bus topic or read every Key Vault secret.

### 5.4 Database authorization

Azure SQL uses Entra-only authentication:

- Create a contained database user for each managed identity.
- Add the API identity to `db_datareader` and `db_datawriter`.
- Add the migration identity to `db_ddladmin` only during migrations.
- Do not use `db_owner` for the runtime.
- Do not enable SQL authentication.
- Use T-SQL firewall rules only as a break-glass exception; private endpoint is the normal path.
- Enable auditing to Log Analytics and storage.
- Use row-level security only if the ownership predicate cannot be enforced safely in the application; it adds complexity and can hide bugs.

### 5.5 Key Vault authorization

- Use Azure RBAC, not access policies.
- App Gateway and APIM: `Key Vault Secrets User`.
- Release identity: `Key Vault Certificates Officer` if it imports the TLS certificate; otherwise no data-plane access.
- Humans: no permanent secret read. Use a manual JIT request for `Key Vault Secrets User`, time-boxed to the troubleshooting window, then remove it.
- Enable purge protection and soft delete. Do not let a pipeline purge the vault.
- Rotate certificates and CMKs on a schedule; alert before expiry.

---

## 6. Pipeline identity design

### 6.1 GitHub to Azure DevOps

- Use a **GitHub App** service connection in Azure DevOps, scoped to the single repository.
- Do not use a personal PAT for the repository connection.
- Protect the service connection: only the build and release pipelines may use it.
- Require PR reviews and branch protection on `main`.

### 6.2 Azure service connections

- Use **workload identity federation** for Azure Resource Manager service connections.
- No client secrets, no certificate files in the pipeline.
- Separate service connections for dev and prod.
- Production service connection is restricted to the release pipeline and requires environment approval.

### 6.3 Pipeline permissions

| Resource | Build pipeline | Release pipeline |
|---|---|---|
| GitHub repo | Read | Read |
| ACR | Push | Read |
| Key Vault | None | Certificate read via managed identity only |
| Terraform state | None | Read/write |
| AKS | None | Deploy to `logistics` namespace |
| App Service | None | Deploy to staging slot |
| Azure RBAC | None | Scoped role assignments in dev/prod RG |
| Environments | None | Dev auto; prod approval |

### 6.4 Secretless flow

```text
Azure DevOps job
  -> federated credential (OIDC)
  -> short-lived Azure access token
  -> Terraform/az/helm
  -> resource
```

No secret is stored in the pipeline. If a tool cannot use OIDC, use a managed identity on a self-hosted agent instead of a PAT.

---

## 7. Authentication flow examples

### 7.1 Interactive user

```text
1. User opens the client app.
2. Client redirects to Entra ID with authorization code + PKCE.
3. User completes MFA (security defaults; no Conditional Access on Free).
4. Client receives an authorization code and exchanges it for:
   - access token (audience api://logistics-api)
   - ID token (client only; never sent to the API)
   - refresh token (client only)
5. Client calls https://api.logistics.example.com with Authorization: Bearer <access token>.
6. App Gateway/WAF forwards to APIM.
7. APIM validates the token and required role/scope.
8. API validates again and enforces ownership.
```

### 7.2 Partner service

```text
1. Partner authenticates with client credentials or federated credential.
2. Entra returns an app-only token with roles=["Partner.Webhook"].
3. Partner posts to /api/v1/partner/webhooks/carrier.
4. APIM validates audience/role.
5. API validates again and checks carrier_id.
6. API publishes shipment.updated to Service Bus.
```

Client credentials use a secret or certificate today. Prefer certificate or federated identity for the partner. If a secret is unavoidable, store it in the partner's vault, rotate it, and never commit it.

### 7.3 Workload-to-workload

```text
AKS pod
  -> projected service account token
  -> Entra workload identity federation
  -> short-lived access token for SQL/Redis/Service Bus/Key Vault
```

No connection strings with keys. No secrets mounted into pods unless the service does not support Entra auth.

---

## 8. Negative tests and abuse cases

| Case | Expected |
|---|---|
| No Authorization header | 401 |
| `Basic` auth instead of Bearer | 401 |
| Token signed by a different tenant | 401 |
| Token for a different API audience | 401 |
| Expired token | 401 |
| Token with `Inventory.Reader`, DELETE inventory | 403 |
| Token with `Order.Reader`, GET another user's order | 404 |
| Token with `Order.Contributor`, POST order for another customer | 403 |
| Partner token, GET inventory | 403 |
| Manager token, DELETE order | 204 + audit event |
| Manager token, DELETE 10,000 records in one request | 400/413 + rate limit |
| Token in query string | 401 + security log |
| JWT with `alg=none` | 401 |
| JWT with huge header | 431/400 |
| Replay after expiry | 401 |

Add these to the Day 4 test suite. A positive-only test suite is not a security test.

---

## 9. Operational identity controls

- Enable Entra sign-in logs and audit logs; export to Log Analytics and Sentinel.
- Alert on:
  - Sign-ins from unusual locations or impossible travel.
  - Repeated 401/403 spikes for a single principal.
  - New app role assignments.
  - New service principals or federated credentials.
  - Key Vault secret/certificate reads outside deployment windows.
  - Privileged role assignments created outside the JIT process.
  - Changes to security defaults, app credentials, or federated credentials.
- Run a **manual quarterly access review** for groups, app roles, and Azure role assignments. Export the current state, review with the owner, remove stale access, and keep the sign-off.
- Remove departed users/groups within the joiner-mover-leaver SLA.
- Keep two break-glass accounts, cloud-only, hardware-key/MFA protected, monitored, and tested. Security defaults cannot exclude them, so plan for MFA on those accounts.
- Test restore of the audit logs and the Key Vault soft-delete recovery.

---

## 10. Common identity mistakes

| Mistake | Why it is dangerous | Correct approach |
|---|---|---|
| Using ID tokens for API auth | Wrong audience, wrong semantics | Use access tokens |
| Checking only `scp` | Scopes do not encode business role | Check roles and resource ownership |
| Putting all logic in APIM | A direct backend path bypasses it | Enforce in API too |
| Using `sub` as a database key | Pairwise per app; hard to reconcile | Use `oid` or an internal mapping |
| Giving the API `db_owner` | A SQL injection becomes a full database compromise | `db_datareader`/`db_datawriter` |
| Sharing one managed identity across services | No blast-radius containment | One identity per workload |
| Permanent Owner for engineers | One phishing click owns the subscription | Separate admin account, manual JIT, remove after task, quarterly review |
| PATs in service connections | Long-lived secrets sprawl | Workload identity federation |
| Logging tokens | Credential leakage | Redact headers; log correlation ID |
| Trusting the network | Any compromised pod can call any service | Identity + network policy + least privilege |
| No negative tests | Authorization bugs ship silently | Test 401/403/404 paths |
| One role for "admin" and "manager" | Business and platform duties conflated | Separate app role and Azure RBAC |

---

## 11. Day 4 implementation checklist

- [ ] `logistics-api` app registration with v2 access tokens.
- [ ] App roles and scopes defined exactly as above.
- [ ] Security groups created and assigned.
- [ ] API validates issuer, audience, tenant, lifetime, signature, roles/scopes.
- [ ] APIM policy validates JWT and checks role for each operation.
- [ ] Manager-only delete enforced in code.
- [ ] Own-order filter enforced in query and object-level check.
- [ ] Partner role restricted to webhook route.
- [ ] Managed identities created and role assignments applied by Terraform.
- [ ] No secrets in code, app settings, or pipeline YAML.
- [ ] Negative tests pass in CI.
- [ ] Sign-in and audit logs flow to Log Analytics.

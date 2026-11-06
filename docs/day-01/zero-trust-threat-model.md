# Zero-Trust Threat Model and DevSecOps Controls

**Status:** Proposed for Day 1 review
**Framing:** NIST SP 800-207 zero-trust principles, mapped to concrete Azure controls
**Not a certification:** This document is an engineering control map, not a claim of compliance with any regulatory standard.

---

## 1. The working definition

Zero trust is not "buy a firewall." It is a set of operating assumptions:

1. **Assume the network is hostile.** Private IP addresses do not grant trust.
2. **Verify explicitly.** Every request is authenticated and authorized using identity, device, and policy signals.
3. **Use least privilege.** Every human, workload, and pipeline gets the minimum permissions for the minimum time.
4. **Assume breach.** Segment, log, detect, contain, and rehearse recovery.
5. **Make authorization continuous.** A token issued once is not a permanent permission; short lifetimes and resource-level checks matter.

For this project, the most important consequence is:

> **A request from inside the VNet is still untrusted.** AKS pods, App Service, and Functions must authenticate to SQL, Redis, Storage, Service Bus, and Key Vault with managed identity, and must be authorized by network policy and RBAC. The private network is a control, not a substitute for identity.

---

## 2. Control map by pillar

| Pillar | Control | Implementation | Evidence |
|---|---|---|---|
| Identity | MFA | Entra ID Free security defaults (Authenticator app); not a hardware-key guarantee | Sign-in logs, security-defaults state |
| Identity | Least-privilege app roles | `Inventory.Reader`, `Order.Contributor`, `Logistics.Manager` | App registration export, RBAC matrix |
| Identity | Just-in-time admin | Manual JIT request, separate admin account, remove after task | Ticket/approval record, role-assignment export |
| Identity | Workload identity | AKS workload identity, App Service/Functions managed identity | Federated credential list, role assignments |
| Device | Compliant device for admin | **Not available on Free.** Compensate with a dedicated admin workstation, no standing roles, and MFA | Manual evidence; documented gap |
| Network | Segmentation | Hub-and-spoke, NSGs, network policy | VNet/subnet/NSG export |
| Network | Private data plane | Private endpoints, public access disabled | `az resource list`, PE list, DNS tests |
| Network | Controlled egress | Azure Firewall FQDN/network rules | Firewall logs, policy export |
| Network | Public edge protection | App Gateway WAF_v2, platform DDoS, APIM quotas | WAF logs, DDoS metrics/plan, APIM policy |
| Application | Strong authN | JWT signature/issuer/audience/lifetime | API tests |
| Application | Resource authZ | Role + ownership check | Unit/integration tests |
| Application | Input validation | Pydantic schemas, request size limits | OpenAPI, tests |
| Data | Encryption at rest | TDE/CMK, storage encryption, Redis TLS | Config export, Key Vault keys |
| Data | Encryption in transit | TLS 1.2+, HTTPS backends, mTLS | Listener/backend config |
| Data | Backup and recovery | SQL PITR/LTR, blob versioning/soft delete | Restore test evidence |
| Supply chain | Trusted source | GitHub branch protection, CODEOWNERS | Branch protection export |
| Supply chain | Secure build | SAST, dependency scan, secret scan, image scan, SBOM | Pipeline artifacts |
| Supply chain | Signed artifacts | Image signing / digest pinning | Signature verification, SBOM |
| Deployment | Plan review | Terraform plan artifact, approval | Pipeline logs |
| Deployment | Least-privilege pipeline | Separate build/release identities | Service connection/RBAC export |
| Monitoring | Central telemetry | Log Analytics, App Insights, diagnostic settings | Workspace queries |
| Detection | Threat detection | Defender for Cloud, Sentinel analytics | Alerts, incidents |
| Response | Runbooks | Rollback, key rotation, incident response | Runbook, tabletop notes |

---

## 3. STRIDE threat model

### 3.1 Spoofing

| ID | Threat | Impact | Preventive controls | Detective controls |
|---|---|---|---|---|
| S1 | Stolen user access token replayed | Impersonate a user | Short token lifetime, security-defaults MFA, mTLS for backends, anomaly detection; **no device-compliance gate on Free** | Entra sign-in logs, impossible travel, 401/403 spikes |
| S2 | Fake partner calls webhook | Inject false shipment events | Partner app role, client credential/certificate, `carrier_id` check, APIM subscription, rate limit | Partner token `azp` mismatch, event anomaly |
| S3 | Rogue workload uses another service identity | Lateral movement | One managed identity per workload, federated credential subject restriction, network policy | Entra workload identity sign-in logs, Key Vault access logs |
| S4 | Forged JWT with `alg=none` or wrong key | Bypass auth | Algorithm allow-list, signature verification, issuer/audience validation | APIM/API 401 metrics, WAF logs |

### 3.2 Tampering

| ID | Threat | Impact | Preventive controls | Detective controls |
|---|---|---|---|---|
| T1 | Modified order payload | Fraudulent order | Schema validation, business rules, idempotency, audit trail | SQL audit, order event anomaly |
| T2 | Malicious container image | Backdoor in production | Private ACR, image scan, digest pinning, signed images, admission policy | Defender for Containers, image integrity alerts |
| T3 | Malicious Terraform change | Public database or open firewall | PR review, `terraform plan`, Checkov/tfsec, policy-as-code, approval | Drift detection, Azure Policy compliance |
| T4 | Pipeline YAML tampering | Deploy attacker code | Branch protection, CODEOWNERS, protected pipelines, environment approvals | Pipeline audit log, deployment diff |
| T5 | Log tampering | Hide an attack | Immutable/retained logs, separate Log Analytics workspace, RBAC | Sentinel integrity alerts, retention policy |

### 3.3 Repudiation

| ID | Threat | Impact | Preventive controls | Detective controls |
|---|---|---|---|---|
| R1 | Manager denies deleting inventory | No accountability | Authenticated delete, immutable audit event, correlation ID | SQL audit, blob audit archive |
| R2 | Partner denies sending an event | Disputed delivery | Signed request, message ID, Service Bus duplicate detection, audit | Service Bus logs, event store |
| R3 | Engineer denies a portal change | Shadow configuration | Policy deny, activity log export, change approval | Azure Activity Log, drift detection |

### 3.4 Information disclosure

| ID | Threat | Impact | Preventive controls | Detective controls |
|---|---|---|---|---|
| I1 | Public blob container exposes documents | Data breach | `allow_nested_items_to_be_public=false`, public access disabled, private endpoint, policy deny | Defender for Storage, access logs |
| I2 | SQL reachable from internet | Data breach | Private endpoint, public access disabled, Entra-only auth, no SQL auth | Defender for SQL, failed login alerts |
| I3 | Verbose error returns stack trace/connection string | Information leak | Generic 500 response, structured internal logs | Log review, API tests |
| I4 | Token or PII in logs | Credential/PII leak | Redaction middleware, no body logging, retention policy | Log queries for token patterns, DLP |
| I5 | Over-broad read model | Users see other customers' orders | Ownership predicate, tests, row-level security if needed | Access anomaly, 404/403 metrics |
| I6 | Key Vault secret read by workload | Credential theft | Managed identity, narrow role, private endpoint, audit | Key Vault access alerts |

### 3.5 Denial of service

| ID | Threat | Impact | Preventive controls | Detective controls |
|---|---|---|---|---|
| D1 | Volumetric DDoS on App Gateway | Outage | DDoS Protection, App Gateway autoscale, WAF | DDoS metrics, Azure status |
| D2 | Application-layer flood | Cost/latency | WAF rate limit, APIM quota, per-user rate limit | APIM metrics, WAF logs |
| D3 | Expensive inventory query | SQL saturation | Pagination, indexes, query limits, Redis cache | SQL DTU/CPU, slow query logs |
| D4 | Service Bus poison message loop | Function cost/latency | Max delivery count, DLQ, exponential backoff, idempotency | DLQ depth alert |
| D5 | Runaway AKS autoscale | Cost | HPA max replicas, node pool max, budget alert | Cost anomaly, pod count |

### 3.6 Elevation of privilege

| ID | Threat | Impact | Preventive controls | Detective controls |
|---|---|---|---|---|
| E1 | Over-privileged pipeline identity | Full subscription compromise | Scoped custom roles, separate build/release identities, approvals | Role assignment changes, pipeline audit |
| E2 | Container escape / privileged pod | Node/cluster compromise | PSS restricted, no privileged pods, seccomp, read-only root FS, network policy | Defender for Containers, pod security alerts |
| E3 | SSRF to IMDS | Managed identity token theft | Egress allow-list, network policy, block link-local metadata from app pods if possible, minimal identity permissions | Anomalous token use, firewall logs |
| E4 | SQL injection | Data modification | Parameterized queries/ORM, input validation, least-privilege DB user | WAF, SQL audit, anomaly alerts |
| E5 | Role assignment abuse | Persistence | Manual JIT, approval, deny assignments, quarterly review; no PIM on Free | Entra audit logs, Azure Activity Log |
| E6 | Compromised developer account | Code/pipeline takeover | MFA (security defaults), branch protection, CODEOWNERS, signed commits | GitHub audit log, impossible travel |

### 3.7 Additional supply-chain and configuration threats

| ID | Threat | Impact | Preventive controls | Detective controls |
|---|---|---|---|---|
| SC1 | Dependency confusion / typosquatting | Malicious package | Lockfile, hashes, private index allow-list, `pip-audit` | Dependency scan, SBOM diff |
| SC2 | Compromised base image | Backdoor | Pin digest, minimal image, rebuild regularly, scan | Trivy, Defender, image digest alert |
| SC3 | Secrets in Git history | Credential leak | Gitleaks pre-commit + CI, GitHub push protection, rotate | Secret scanning alert, Key Vault access anomaly |
| SC4 | Unpinned Terraform provider/module | Unexpected change | Version constraints, lock file, private registry/module review | `terraform init -upgrade` review, plan diff |
| SC5 | Public IP or public PaaS accidentally enabled | Exposure | Azure Policy deny, Checkov, deployment gate | Daily exposure query, Defender |
| SC6 | Missing diagnostic settings | Blind spots | Policy `DeployIfNotExists`, Terraform module | Policy compliance, log coverage report |

---

## 4. Attack-path analysis

### 4.1 Stolen manager token

**Path:** Phishing -> token theft -> call delete endpoint -> destroy inventory records.

**Controls:**

- Security defaults require MFA for managers, but the Free tier has **no device-compliance or location-based Conditional Access**. A stolen token can be replayed from another device until it expires or is revoked.
- Token lifetime is short; continuous access evaluation (CAE) can revoke faster.
- Delete requires `Logistics.Manager` and writes an immutable audit event.
- APIM rate limit and anomaly alert on high-volume deletes.
- Soft delete and backup allow recovery.

**Residual risk:** A token used before revocation can perform actions allowed by its role. Minimize token lifetime and require step-up auth for destructive operations if the business accepts the friction.

### 4.2 Compromised AKS pod

**Path:** RCE in API -> read service account token -> call IMDS -> use workload identity -> read SQL/Storage.

**Controls:**

- Workload identity federated to a specific namespace/service account, not cluster-wide.
- API identity has only `db_datareader`/`db_datawriter` and scoped blob/Service Bus roles.
- Network policy restricts egress to required private endpoints and firewall.
- PSS restricted, no privileged pods, read-only root FS.
- Defender for Containers detects crypto mining, suspicious processes, and image anomalies.
- Key Vault access is audited; no broad `Key Vault Secrets User` for the API identity unless required.

**Residual risk:** The pod can read data the API is allowed to read. Data minimization and query-level authorization reduce the blast radius.

### 4.3 Compromised build pipeline

**Path:** Malicious PR or dependency -> build agent -> push image -> release.

**Controls:**

- Build identity can only push to ACR; it cannot deploy.
- Branch protection, CODEOWNERS, required review.
- SAST, dependency scan, secret scan, image scan, SBOM.
- Image digest pinned in the release artifact; release verifies signature/digest.
- Production release requires approval and uses a separate identity.
- Build agents are ephemeral or rebuilt regularly; no long-lived credentials on the host.

**Residual risk:** A malicious image that passes scans can still be deployed. Runtime detection and admission policy (signature verification) are the next layer.

### 4.4 Public storage misconfiguration

**Path:** Developer enables public blob access for a test -> document leak.

**Controls:**

- Storage account `allow_nested_items_to_be_public=false`, public network access disabled, private endpoint.
- Azure Policy denies public blob access and public network access for storage.
- Checkov/Terraform plan gate.
- Defender for Storage alerts on anomalous access.
- Blob immutability and audit logs.

### 4.5 Compromised release identity

**Path:** Pipeline identity token theft -> modify production resources.

**Controls:**

- Separate dev/prod identities, scoped to resource groups.
- Production environment approval, branch control, business hours.
- No standing Owner; `Role Based Access Control Administrator` scoped and reviewed.
- Terraform plan artifact reviewed before apply.
- Activity Log alert on role assignment, firewall, public IP, and Key Vault changes.
- Break-glass and incident response runbook.

**Residual risk:** A compromised release identity can deploy malicious code within its scope. Deployment diff approval, runtime alerts, and rapid rollback are essential.

### 4.6 Data exfiltration through egress

**Path:** Compromised workload sends data to an attacker-controlled domain.

**Controls:**

- Azure Firewall FQDN allow-list, default deny.
- Private endpoints for data services; no public data plane.
- DNS resolution through controlled resolvers; log DNS.
- DLP/Defender for Cloud anomaly detection.
- Egress alert on unusual volume or new destinations.

**Residual risk:** Allowed destinations (e.g., GitHub, PyPI) can be abused. Restrict to required FQDNs, use TLS inspection where feasible, and monitor volume.

---

## 5. DevSecOps gates

### 5.1 Pull request gates

- [ ] At least one reviewer; CODEOWNERS for infrastructure/security paths.
- [ ] `ruff`, `mypy`, `pytest` with coverage threshold.
- [ ] `bandit`, `semgrep`, `pip-audit`, `gitleaks`.
- [ ] `terraform fmt -check`, `terraform validate`, `tflint`, `checkov`.
- [ ] `ansible-lint`, `yamllint`.
- [ ] No new public IP or public data-plane resource without an approved exception.
- [ ] ADR updated for architecture changes.

### 5.2 Build pipeline gates

- [ ] Tests and coverage pass.
- [ ] No HIGH/CRITICAL vulnerabilities in dependencies or image.
- [ ] No secrets detected.
- [ ] SBOM generated and attached.
- [ ] Image built from a pinned base digest, non-root, minimal.
- [ ] Image signed or digest recorded.
- [ ] Build artifact immutable and traceable to commit.

### 5.3 Release pipeline gates

- [ ] Terraform plan reviewed; no unexpected destroy/replace.
- [ ] Policy compliance pass.
- [ ] Environment approval for prod.
- [ ] Database migration is backward compatible.
- [ ] Smoke tests pass.
- [ ] DAST baseline pass (dev only; passive in prod).
- [ ] Rollback plan and previous artifact available.
- [ ] Change ticket linked (if required by the organization).

### 5.4 Runtime gates

- [ ] No public IPs on workload/data resources.
- [ ] No public network access on PaaS data services.
- [ ] No secrets in app settings; managed identity only.
- [ ] Diagnostic settings enabled on every resource.
- [ ] Defender plans enabled for the services in scope.
- [ ] Backup/PITR configured and restore tested.
- [ ] Alerts for 5xx, latency, DLQ, failed auth, public exposure, and cost anomaly.

---

## 6. Detection and response

### 6.1 High-value alerts

| Alert | Source | Threshold | Runbook |
|---|---|---|---|
| API 5xx rate | App Insights | > 2% for 5 min | Check APIM/backend, rollback |
| p95 latency | App Insights | > 1s for 10 min | Check SQL/Redis/AKS, scale |
| Failed auth spike | APIM/Entra | > 50 401s/min per principal | Block client, investigate token |
| 403 spike | APIM/API | > 20/min per principal | Check role assignment/attack |
| DLQ depth | Service Bus | > 0 for 15 min | Inspect message, replay/repair |
| Public IP created | Activity Log | Any | Verify change, remove |
| Public access enabled | Activity Log/Policy | Any | Revert, investigate |
| Key Vault access anomaly | Key Vault logs | Outside deployment window | Check identity, rotate |
| Role assignment change | Activity Log | Any prod | Verify change ticket |
| Firewall deny spike | Firewall logs | > baseline | Check workload/attack |
| Container threat | Defender | Medium+ | Isolate pod, collect forensics |
| Cost anomaly | Cost Management | > 20% day-over-day | Identify resource, scale down |

### 6.2 Incident response outline

1. **Detect and triage:** confirm the alert, identify the affected identity/resource, assign severity.
2. **Contain:** revoke sessions/tokens, disable the identity, isolate the pod/node, block the IP/domain, disable the service connection.
3. **Eradicate:** remove malicious code/config, rotate credentials/certificates, patch the vulnerability.
4. **Recover:** restore from backup, redeploy from a known-good signed artifact, verify smoke tests.
5. **Learn:** blameless post-incident review, update threat model, add a detection or guardrail, close the loop.

### 6.3 Break-glass procedure

- Two cloud-only break-glass accounts, hardware-key/MFA protected.
- On Entra ID Free, security defaults cannot be scoped to exclude these accounts; they must still complete MFA. Monitor them with a separate alert instead of relying on a Conditional Access exclusion.
- Stored credentials in a physical safe or sealed envelope, not in the repo.
- Any use triggers a high-priority alert and a post-use review.
- Test the procedure quarterly.

---

## 7. Residual risks accepted for the five-day lab

| Risk | Why accepted | Production action |
|---|---|---|
| Single region | Time and cost | Add paired-region DR, geo-redundant SQL/Storage, APIM backup |
| No 24/7 SOC | Course scope | Managed detection/response or on-call rotation |
| Self-signed certificate in lab | No domain | CA-issued certificate, automated rotation |
| WAF initially in detection mode | Avoid blocking the build | Tune and switch to prevention before go-live |
| No external penetration test | Time | Pre-production pen test and remediation |
| Basic/Standard firewall in lab | Cost | Premium with IDPS/TLS inspection in production |
| Limited load testing | Time | Load test at 2x expected peak, chaos exercise |
| Image signing may be a stretch goal | Tooling complexity | Enforce signature admission in production |
| Entra ID Free: no Conditional Access, PIM, access reviews, or risk policies | Licensing constraint | Buy P1/P2 or Entra ID Governance; until then use security defaults, manual JIT, quarterly reviews, and sign-in alerts |

Do not hide these. A mature DevOps engineer states the gap and the plan. See [ADR-0011](../adr/0011-entra-id-free-license.md).

---

## 8. Verification checklist

- [ ] Every threat in the STRIDE table has a preventive and a detective control.
- [ ] The attack-path exercise has a first control and a detection for each path.
- [ ] The RBAC matrix includes negative tests.
- [ ] Security defaults are enabled, and no control claims Conditional Access or PIM on the Free tier.
- [ ] The pipeline gates are implemented in YAML, not just documented.
- [ ] The alert table has an owner and a runbook.
- [ ] The break-glass procedure is documented and tested.
- [ ] Residual risks are accepted by a named owner.
- [ ] The threat model is reviewed when the architecture changes, not once a year.

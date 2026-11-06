# ADR-0011: Operate with Microsoft Entra ID Free

- **Status:** Accepted
- **Date:** 2026-11-06
- **Deciders:** Project owner, platform engineering, security
- **Related:** [Identity and RBAC](../day-01/identity-and-rbac.md), [Zero-trust threat model](../day-01/zero-trust-threat-model.md)

## Context

The project tenant has **Microsoft Entra ID Free**, not Entra ID P1 or P2. The original design assumed Conditional Access and Privileged Identity Management (PIM). Those are premium capabilities:

- Conditional Access requires Entra ID P1.
- PIM, access reviews, and risk-based policies require Entra ID P2 or Entra ID Governance.
- Custom Entra roles require P1.
- Entra ID Free does include security defaults, app registrations, app roles, groups, managed identities, workload identity federation, sign-in logs, and audit logs.

Terminology note: **Entra ID editions are Free, P1, and P2.** "Premium v2" is an Azure API Management tier, not an Entra ID license.

## Decision

Keep the project on **Entra ID Free** and replace the unavailable premium controls with documented compensating controls.

### What stays the same

- Microsoft Entra ID remains the identity provider.
- OIDC/OAuth 2.0 access tokens for users and services.
- App registrations, app roles, delegated scopes, and security groups.
- Managed identities and workload identity federation (free, including AKS workload identity).
- JWT validation at APIM and again in the API.
- Manager-only delete and own-order authorization.
- Sign-in logs and audit logs exported to Log Analytics.
- No long-lived secrets; no shared keys.

### What changes

| Original assumption | Free-tier replacement |
|---|---|
| Conditional Access with device compliance and location rules | **Security defaults** enabled: MFA for all users, block legacy authentication. No device-compliance gate. |
| PIM just-in-time activation for Azure/Entra roles | **Manual JIT process**: separate admin account, named request/approval, time-boxed task, remove assignment after use. No native activation history. |
| Access reviews | **Manual quarterly review** of group membership and Azure role assignments; export and sign off. |
| Entra ID Protection risk policies | Sign-in log review and Azure Monitor alerts on risky/failed sign-ins. No automated risk remediation. |
| Custom Entra roles | Built-in roles only. |
| Break-glass excluded from Conditional Access | Break-glass accounts remain, protected by MFA and monitored. Security defaults cannot be scoped to exclude them, so they must still complete MFA. |

### Required compensating controls

1. **Enable security defaults** in the Entra admin center unless the organization has a documented alternative MFA enforcement. Security defaults require the Microsoft Authenticator app for the Free tier; confirm this is acceptable for every user.
2. **Separate admin accounts.** Do not use a day-to-day account for subscription or tenant administration. Admin accounts have no mailbox/license dependency where possible.
3. **No standing Owner at subscription scope.** Use Contributor at a resource group, and remove the assignment after the task. Without PIM there is no native time-bound assignment; the ticket and the access review are the control.
4. **Manual JIT record.** Every elevation request includes requester, role, scope, reason, start/end time, and approver. Store it in the team's ticketing system, not in Git.
5. **Quarterly access review.** Export group members and Azure role assignments; review with the owner; remove stale access.
6. **Alert on identity changes.** Alert on new role assignments, new app credentials/federated credentials, new service principals, and unusual sign-in patterns.
7. **Protect the break-glass accounts.** Two cloud-only accounts, strong unique credentials, MFA, monitored, tested quarterly.
8. **Use workload identity federation** for pipelines and AKS; do not create client secrets as a workaround for missing PIM.
9. **Record the gap.** This is a lab/production-shaped project, not a claim that Free tier meets a regulated enterprise baseline.

## Consequences

### Positive

- No additional Entra license cost.
- Core OIDC, app roles, managed identities, and workload identity still work.
- The project remains buildable and realistic for a small organization.
- Forces explicit, documented access decisions instead of relying on tooling.

### Negative / trade-offs

- No device-compliance or location-based access control. A stolen token can be used from any device until it expires or is revoked.
- No PIM activation trail or automatic expiration. Admin access is more likely to become permanent through neglect.
- No access reviews. Privilege creep must be caught manually.
- No risk-based Conditional Access or automated remediation.
- Security defaults are all-or-nothing and cannot be scoped to a pilot group.
- Some MFA methods are limited on the Free tier.
- This is a **production gap** that must be closed before handling regulated or high-value data.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Buy Entra ID P1/P2 | Best control outcome, but the project constraint is Free; revisit if budget changes |
| Disable security defaults and rely on passwords | Unacceptable; removes the main free MFA control |
| Use another identity provider | Adds migration and integration complexity; Entra ID is the Azure-native choice |
| Ignore the gap | Would make the design dishonest and unsafe |

## Review trigger

- The tenant is upgraded to P1/P2 or Entra ID Governance.
- The project handles production customer PII or payment data.
- A security review requires device compliance, PIM, or access reviews.
- The number of administrators or external users grows beyond manual review capacity.

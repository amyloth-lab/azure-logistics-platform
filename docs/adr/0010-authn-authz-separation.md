# ADR-0010: Authentication and authorization are separate concerns

- **Status:** Proposed
- **Date:** 2026-11-03
- **Deciders:** Application and security
- **Related:** [Identity and RBAC](../day-01/identity-and-rbac.md), [Zero-trust threat model](../day-01/zero-trust-threat-model.md)

## Context

The brief requires users to authenticate and obtain a web token, with role-based permissions. A common failure is to treat a valid token or a successful login as permission, or to enforce authorization only at the gateway. The phrase "authentication should not interfere with web tokens (authorization)" is best interpreted as: keep identity proof separate from permission decisions, and use the token as the authorization artifact rather than as a session.

## Decision

- **Authentication:** Microsoft Entra ID, OIDC/OAuth 2.0, short-lived JWT access tokens. Users use authorization code + PKCE; services use client credentials or workload identity federation.
- **Authorization:** app roles + delegated scopes, enforced at APIM and again in the API. Resource ownership is enforced in the API and database query.
- **Token use:** access tokens only; never ID tokens for API calls. No server-side session, no token in URLs, no token logging.
- **Role model:** `Inventory.Reader`, `Inventory.Contributor`, `Order.Reader`, `Order.Contributor`, `Logistics.Manager`, `Partner.Webhook`.
- **Manager delete:** business-level permission, not Azure RBAC.
- **Defense in depth:** APIM validates and rate-limits; the API validates and authorizes; the database uses least-privilege identities.
- **Separation:** Azure RBAC controls who can change cloud resources; app roles control who can change business data. They are not interchangeable.

## Consequences

### Positive

- Clear mental model for developers and reviewers.
- Authorization bugs are caught by API tests, not hidden behind the gateway.
- Token theft has a limited blast radius and lifetime.
- Business permissions can evolve without changing Azure RBAC.
- Easier audit: app role assignments vs Azure role assignments.

### Negative / trade-offs

- Duplicate validation at APIM and API adds a small latency.
- Two policy surfaces to keep in sync.
- Role/scope confusion can cause bugs if not tested.
- Resource ownership checks add query complexity.
- Entra app role limits and token size can become constraints at scale.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| APIM-only authorization | A direct backend path or misconfiguration bypasses it |
| API-only authorization | Loses fast-fail, quotas, and centralized policy |
| Azure RBAC for business roles | Wrong tool; gives cloud permissions to business users |
| Session cookies for API | Stateful, CSRF complexity, poor fit for service clients |
| ID tokens for API | Wrong audience and semantics |

## Review trigger

- Introduction of a second API or resource server.
- Need for fine-grained ABAC or policy-as-code (for example, OPA).
- Entra app role or token size limits are reached.
- A regulatory requirement changes the authorization model.

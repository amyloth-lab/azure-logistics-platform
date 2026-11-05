# Tests - Planned Pyramid

Tests are written with the application on Day 4 and wired into the build pipeline.

## Layers

| Layer | What it proves | Tools |
|---|---|---|
| Unit | Pure business rules, validation, role checks | `pytest`, `pytest-asyncio` |
| Integration | API + SQL + Redis + Service Bus contracts | `pytest`, Testcontainers or Azure dev resources |
| Contract | OpenAPI schema and response shapes | `schemathesis` or `pytest` + `httpx` |
| Security | 401/403/404, ownership, manager delete, token validation | `pytest` + mocked JWKS |
| Infrastructure | Terraform format/validate/plan, policy, Checkov | `terraform`, `tflint`, `checkov` |
| End-to-end | Auth -> WAF -> APIM -> API -> SQL | `httpx` against dev |
| DAST | Common web/API issues | OWASP ZAP baseline |

## Required negative tests

- No token -> 401.
- Expired token -> 401.
- Wrong audience -> 401.
- Wrong tenant/issuer -> 401.
- Reader -> DELETE inventory -> 403.
- Contributor -> DELETE inventory -> 403.
- Manager -> DELETE inventory -> 204 and audit event.
- User A -> GET user B's order -> 404.
- Manager -> GET any order -> 200.
- Partner -> GET orders -> 403.
- Token in query string -> 401 and security log.
- Oversized body -> 413/400.

## Rules

- Tests must not depend on execution order.
- No real secrets in tests; use fake tokens with a test JWKS.
- Integration tests use a dedicated database/schema and clean up.
- A test that only proves the happy path is not enough for authorization.
- Coverage is a signal, not a goal; security paths must be covered explicitly.

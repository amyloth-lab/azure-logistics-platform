# Security Policy

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Contact the repository owner privately with:

- A description of the issue.
- Steps to reproduce.
- Affected commit, image, or environment.
- Any suggested remediation.

## Secrets

If a secret is committed:

1. Treat it as compromised immediately.
2. Revoke/rotate it in the issuing system.
3. Remove it from the working tree and, if necessary, rewrite history.
4. Add a detection rule or test that would catch the same mistake.
5. Record the incident and the follow-up actions.

Deleting the commit is not enough; assume the secret was read.

## Supported versions

This is a learning repository. Only the `main` branch is supported. Images and dependencies should be rebuilt at least monthly to pick up security fixes.

## Security expectations

- No long-lived credentials in code or pipelines.
- Managed identities / workload identity federation by default.
- Private data plane; no public PaaS access.
- Least-privilege Azure RBAC and app roles.
- Build and release separated.
- Security scans are gates, not suggestions.

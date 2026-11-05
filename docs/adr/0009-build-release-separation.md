# ADR-0009: Separate build and release pipelines and identities

- **Status:** Proposed
- **Date:** 2026-11-03
- **Deciders:** DevOps, security
- **Related:** [Identity and RBAC](../day-01/identity-and-rbac.md), [Plan of action](../day-01/plan-of-action.md)

## Context

A single pipeline that builds and deploys is convenient but gives the build step deployment credentials. A compromised dependency, build script, or pull request can then modify production. The brief explicitly asks for two pipelines: build and release.

## Decision

Use two Azure DevOps YAML pipelines:

1. **Build pipeline** (`pipelines/build.yml`)
   - Triggered by PR and merge to `main`.
   - Runs lint, tests, SAST, dependency/secret/IaC scans, container build, image scan, SBOM, signing/digest, push to ACR, publish Helm/artifacts.
   - Uses `id-build-logistics` with `AcrPush` only. No Azure deployment permission.
   - Produces an immutable artifact tied to commit SHA and build ID.

2. **Release pipeline** (`pipelines/release.yml`)
   - Triggered by tag `v*` or manual.
   - Consumes the build artifact, verifies digest/signature, runs Terraform plan/apply, Ansible, migrations, deploy, smoke/DAST.
   - Uses separate dev and prod identities, scoped to resource groups.
   - Prod stage requires environment approval, branch control, business hours, and exclusive lock.
   - Supports rollback (Helm rollback, App Service slot swap, migration roll-forward).

Terraform plan and apply may run in the release pipeline for this course. In a larger organization, split infrastructure and application releases into separate pipelines, but keep build separate from both.

## Consequences

### Positive

- Build compromise does not directly grant production deploy rights.
- Release approvals and audit are meaningful.
- Artifacts are promoted, not rebuilt per environment.
- Clear separation of duties and easier incident analysis.
- Supports reproducible deployments and rollback.

### Negative / trade-offs

- More YAML, service connections, and permissions to maintain.
- Artifact handoff must be reliable; losing the artifact blocks release.
- Two identities and two permission sets to review.
- Slower feedback than a single pipeline.
- Environment approvals can become a bottleneck if overused.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| One pipeline builds and deploys | Violates separation of duties; build credentials become deploy credentials |
| Build once, deploy from the same job | No approval boundary; no artifact promotion |
| GitHub Actions for build, Azure Pipelines for release | Viable, but adds a second CI system; the brief asks for Azure DevOps |
| Rebuild in each environment | Image drift; cannot prove what was tested |

## Review trigger

- The organization adopts a deployment orchestrator or GitOps.
- Build and release teams split ownership.
- Artifact promotion or approval requirements change.

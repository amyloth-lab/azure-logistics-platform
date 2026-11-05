# Pipelines - Build and Release Design

YAML is written on Day 4 and Day 5. This is the contract.

## Build pipeline (`build.yml`)

**Trigger:** pull request and merge to `main`
**Identity:** `id-build-logistics` with `AcrPush` only
**Output:** immutable container image, Helm chart, SBOM, scan reports, test results

```text
checkout
  -> install Python + dependencies
  -> ruff + mypy
  -> pytest (unit + integration with mocked Azure)
  -> bandit + semgrep
  -> pip-audit
  -> gitleaks
  -> terraform fmt/validate/tflint/checkov
  -> ansible-lint/yamllint
  -> docker build (multi-stage, non-root, pinned base digest)
  -> trivy image scan
  -> syft SBOM
  -> sign / record digest
  -> push to ACR with immutable tag
  -> publish Helm chart + reports
```

**Must not:** deploy, read production secrets, change Azure RBAC, or use a production service connection.

## Release pipeline (`release.yml`)

**Trigger:** tag `v*` or manual
**Identity:** separate dev and prod release identities
**Input:** build artifact from the same commit

```text
download artifact + verify digest
  -> Terraform plan (dev) -> publish plan
  -> approval/check -> Terraform apply (dev)
  -> Ansible baseline (dev)
  -> DB migration job (dev)
  -> Helm deploy AKS + App Service slot swap + Functions deploy (dev)
  -> smoke tests + synthetic auth/RBAC
  -> DAST baseline (dev)
  -> prod plan -> approval -> prod apply
  -> prod migration -> prod deploy -> smoke
  -> rollback on failure
```

## Environment checks

| Environment | Approval | Branch control | Business hours | Exclusive lock |
|---|---|---|---|---|
| dev | None or 1 reviewer | `main` | No | Yes |
| prod | 1-2 approvers | `main` + tag | Yes | Yes |

## Artifact rules

- Build once, promote the same digest. Do not rebuild per environment.
- Tag with `$(Build.BuildId)-$(Build.SourceVersion)` and record the digest.
- Keep the previous two production artifacts available for rollback.
- SBOM and scan reports are retained with the release.

## Security rules

- No secrets in YAML or variable groups. Use workload identity federation.
- Protect service connections and environments from unauthorized pipelines.
- Do not allow the build pipeline to use the production service connection.
- Do not print environment variables or tokens.
- Pin tasks and base images. Review third-party tasks before use.
- A failed security scan is a failed build, not a warning.

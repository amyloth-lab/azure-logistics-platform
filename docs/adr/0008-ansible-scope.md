# ADR-0008: Ansible for Linux/agent hardening and Kubernetes baseline

- **Status:** Proposed
- **Date:** 2026-11-03
- **Deciders:** Platform engineering, DevOps
- **Related:** [Plan of action](../day-01/plan-of-action.md)

## Context

Terraform provisions infrastructure but does not configure the inside of a Linux VM or apply a Kubernetes baseline. The brief requires Ansible for configuration management. AKS nodes are managed by Azure and must not be configured with SSH/Ansible; doing so is unsupported and creates drift.

## Decision

Use Ansible for:

- Hardening the self-hosted Azure DevOps agent VMs and the Ansible control node (CIS-aligned baseline, patching, auditd, SSH policy, time sync, logging agent).
- Installing and configuring tooling on those VMs (Azure CLI, kubectl, Helm, Terraform, Docker, scanners).
- Registering self-hosted agents with Azure DevOps using a short-lived token from Key Vault.
- Applying a Kubernetes baseline through `kubernetes.core.k8s`: namespaces, resource quotas, limit ranges, network policies, RBAC bindings, service accounts.
- Running idempotence checks in the release pipeline (`--check --diff`) and a second real run that must report no changes.

Do **not** use Ansible to configure AKS node operating systems, kubelet, or control-plane components. Use AKS node image upgrades, daemonsets, and Kubernetes manifests/Helm instead.

## Consequences

### Positive

- Clear boundary between provisioning (Terraform) and configuration (Ansible).
- Repeatable VM hardening and agent setup.
- Kubernetes baseline is reviewable and idempotent.
- No public SSH; Ansible runs from a private control node via Bastion or pipeline.
- Satisfies the configuration-management requirement without fighting AKS.

### Negative / trade-offs

- Another toolchain (Python, collections, inventory, SSH) to maintain.
- Ansible control node must be highly available for production use; a single VM is a lab compromise.
- Dynamic inventory and secrets handling add complexity.
- Kubernetes baseline can drift if someone applies manifests manually; GitOps would be better at scale.
- Windows control node is not supported; WSL2 is a lab workaround.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Terraform for everything | Terraform is not a configuration-management tool; VM inside-config drift is hard |
| Custom shell scripts | Not idempotent, no inventory, poor reporting |
| Azure DSC | Windows-centric; the workload is Linux |
| GitOps/Argo CD only | Excellent for Kubernetes, but does not cover VM hardening/agent setup |
| No Ansible | Fails the brief and leaves configuration undocumented |

## Review trigger

- Move to immutable VM images and cloud-init, reducing Ansible's VM role.
- Adopt GitOps for Kubernetes and reduce Ansible to bootstrap only.
- Ansible control node needs HA or enterprise support.

# ADR-0014: Defer the Ansible control VM due to vCPU quota

- **Status:** Accepted
- **Date:** 2026-11-09
- **Deciders:** Project owner
- **Related:** ADR-0012, ADR-0013, [Day 3B guide](../day-03b/README.md), [Project state](../PROJECT-STATE.md)

## Context

The design uses an Ansible control VM in the management spoke to install tooling, harden hosts, and apply the Kubernetes baseline.

The lab subscription has a **Total Regional Cores** quota of 4 in `australiaeast`, with all 4 in use by AKS. The Ansible VM needs 2 vCPUs. A smaller VM does not help because there are zero free cores.

The VM cannot be created without a quota increase.

## Decision

- Keep the Ansible VM module and playbooks in the repository.
- Disable the VM with `enable_ansible_vm = false`.
- Do not shrink AKS node pools, delete Bastion, or remove the firewall to free cores.
- Do not claim the Ansible control VM was completed.
- Use local Ansible syntax checks while the VM is deferred.
- Apply the Kubernetes baseline later from AKS run command or the release pipeline, and document that path.

## Consequences

### Positive

- AKS capacity and the private platform remain intact.
- No public IP or interactive SSH path is added.
- The Ansible code is preserved for a subscription with vCPU quota.
- The requirement gap is explicit rather than hidden.

### Negative / trade-offs

- No persistent Ansible control host.
- The VM-based hardening and idempotence demonstration is deferred.
- The “configuration via Ansible” objective is only partially demonstrated by the checked-in playbook.
- Kubernetes baseline execution moves to AKS run command or the pipeline.

## Production remediation

1. Request a Total Regional Cores increase to at least 6 (8 recommended), then set `enable_ansible_vm = true`.
2. Move to a subscription with vCPU quota and deploy the original management VM design.
3. Run Ansible as a Kubernetes Job in AKS, accepting that the control host is ephemeral.

Do not reduce AKS capacity to make room for the control VM.

## Review trigger

- Total Regional Cores quota becomes available.
- The project needs persistent configuration management.
- The lab moves to a subscription with sufficient vCPU quota.

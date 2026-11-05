# Ansible - Planned Layout and Scope

Ansible configuration work starts on Day 3. Terraform provisions the VMs, network, and identities; Ansible configures the inside of the Linux VMs and applies the Kubernetes baseline.

```text
infra/ansible/
├── ansible.cfg
├── requirements.yml
├── inventories/
│   └── dev/
│       ├── hosts.yml
│       └── group_vars/
├── playbooks/
│   ├── site.yml
│   ├── agents.yml
│   └── k8s-baseline.yml
└── roles/
    ├── common/                # CIS-aligned OS baseline, auditd, time, logging
    ├── devops_agent/          # Azure DevOps agent install and registration
    ├── ansible_control/       # tooling and hardening
    └── k8s_baseline/          # namespaces, quotas, network policies, RBAC
```

## Scope

**In scope**

- Linux VM hardening and patching.
- Install Azure CLI, kubectl, Helm, Terraform, Docker, and scanners on the agent/control VMs.
- Register self-hosted Azure DevOps agents with a short-lived token from Key Vault.
- Apply Kubernetes namespaces, resource quotas, limit ranges, network policies, and RBAC bindings.
- Enforce idempotence with `--check --diff` and a second real run.

**Out of scope**

- Configuring AKS node operating systems, kubelet, or control-plane components. AKS manages those; use node image upgrades and Kubernetes manifests instead.
- Provisioning Azure resources. That is Terraform's job.
- Storing secrets in inventory or group_vars. Use Key Vault and managed identity.

## Rules

- Pin collections in `requirements.yml`.
- Use `ansible-lint` and `yamllint`.
- No `shell`/`command` when a module exists.
- `changed_when` and `failed_when` must be explicit for commands.
- Run from a Linux control node (WSL2 in the lab, a private VM in production).
- Do not run as root unless required; use become with least privilege.
- The second run must report `changed=0`.

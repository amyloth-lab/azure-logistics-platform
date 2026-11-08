# Ansible baseline

The Ansible control VM is `vm-ansible-dev-*` in `rg-logistics-management-dev`, subnet `snet-ansible`.

It has no public IP. Access is through Bastion or `az vm run-command`.

## Run the baseline against the control host

The VM already has Ansible from cloud-init. From your workstation, use `az vm run-command` because Bastion Basic does not provide native SSH tunneling:

```powershell
$vm = az vm list `
  --resource-group rg-logistics-management-dev `
  --query "[?contains(name, 'vm-ansible')].name | [0]" `
  --output tsv

$playbook = Get-Content .\ansible\playbooks\baseline.yml -Raw
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($playbook))

az vm run-command invoke `
  --resource-group rg-logistics-management-dev `
  --name $vm `
  --command-id RunShellScript `
  --scripts "echo '$b64' | base64 -d > /tmp/baseline.yml; ansible-playbook -i localhost, -c local /tmp/baseline.yml"
```

Expected: `changed=0` on the second run.

## Why localhost

This checkpoint validates Ansible installation, syntax, privilege escalation, idempotence, and SSH hardening on the control host. The Kubernetes baseline is applied from the same control host on Day 4, once the application namespace and manifests exist.

## Bastion limitation

The lab uses Bastion Basic. Native `az network bastion ssh` / `tunnel` requires Bastion Standard, which needs another public IP. Do not delete Bastion or the firewall to free an IP. Use `az vm run-command` for this checkpoint.

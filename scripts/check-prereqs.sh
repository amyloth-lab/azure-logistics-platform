#!/usr/bin/env bash
# Day 1 prerequisite check for WSL2 / Linux.
# Usage: ./scripts/check-prereqs.sh
# This script does not install anything. It reports what is missing.

set -u

missing=0

check() {
  local name="$1"
  shift
  local cmd="$1"
  shift
  local version_args=("$@")

  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf '[MISSING] %-24s %s\n' "$name" "$cmd"
    missing=$((missing + 1))
    return
  fi

  local version
  version="$("$cmd" "${version_args[@]}" 2>&1 | head -n 1)"
  printf '[OK]      %-24s %s\n' "$name" "$version"
}

echo
echo "=== Core workstation tools ==="
check "Git" git --version
check "Azure CLI" az --version
check "Terraform" terraform version
check "kubectl" kubectl version --client
check "Helm" helm version --short
check "Docker" docker --version
check "GitHub CLI" gh --version
check "Python 3" python3 --version

echo
echo "=== Security and quality tools ==="
check "Ansible" ansible --version
check "ansible-lint" ansible-lint --version
check "tflint" tflint --version
check "Trivy" trivy --version
check "Gitleaks" gitleaks version
check "pre-commit" pre-commit --version
check "Checkov" checkov --version
check "yamllint" yamllint --version

echo
echo "=== Azure context ==="
if command -v az >/dev/null 2>&1; then
  if az account show >/dev/null 2>&1; then
    echo "[OK]      Azure CLI is signed in."
    az account show --query "{name:name,id:id,tenantId:tenantId}" -o tsv
  else
    echo "[WARN]    Azure CLI is installed but not signed in. Run: az login"
  fi
fi

echo
echo "=== Summary ==="
if [ "$missing" -eq 0 ]; then
  echo "All Day 1 prerequisites were found."
  exit 0
fi

echo "Missing $missing prerequisite(s). Install them and run this script again."
exit 1

#Requires -Version 7.0
<#
.SYNOPSIS
Checks the Day 1 workstation prerequisites for the Azure Logistics Platform course.

.DESCRIPTION
Prints the detected version of each tool. Missing tools are collected and the
script exits with code 1 so a setup failure is visible in a terminal or pipeline.

.NOTES
Run from the repository root:
    pwsh -File .\scripts\check-prereqs.ps1
#>

$ErrorActionPreference = "Continue"
$missing = [System.Collections.Generic.List[string]]::new()

function Test-Tool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$VersionArgs = @("--version")
    )

    $resolved = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $resolved) {
        Write-Host ("[MISSING] {0,-24} {1}" -f $Name, $Command) -ForegroundColor Red
        $missing.Add($Name)
        return
    }

    $version = "installed"
    try {
        $output = & $Command @VersionArgs 2>&1 | Select-Object -First 1
        if ($null -ne $output -and "$output".Trim().Length -gt 0) {
            $version = "$output".Trim()
            if ($version -match "Traceback|Access is denied|not recognized|is not recognized") {
                $version = "installed (version check failed)"
            }
        }
    }
    catch {
        $version = "installed (version check failed)"
    }

    Write-Host ("[OK]      {0,-24} {1}" -f $Name, $version) -ForegroundColor Green
}

Write-Host "`n=== Core workstation tools ===" -ForegroundColor Cyan
Test-Tool -Name "Git" -Command "git" -VersionArgs @("--version")
Test-Tool -Name "VS Code" -Command "code" -VersionArgs @("--version")
Test-Tool -Name "Azure CLI" -Command "az" -VersionArgs @("--version")
Test-Tool -Name "Terraform" -Command "terraform" -VersionArgs @("version")
Test-Tool -Name "kubectl" -Command "kubectl" -VersionArgs @("version", "--client")
Test-Tool -Name "Helm" -Command "helm" -VersionArgs @("version", "--short")
Test-Tool -Name "Docker" -Command "docker" -VersionArgs @("--version")
Test-Tool -Name "GitHub CLI" -Command "gh" -VersionArgs @("--version")
Test-Tool -Name "Python" -Command "python" -VersionArgs @("--version")
Test-Tool -Name "uv" -Command "uv" -VersionArgs @("--version")

Write-Host "`n=== Security and quality tools ===" -ForegroundColor Cyan
Test-Tool -Name "tflint" -Command "tflint" -VersionArgs @("--version")
Test-Tool -Name "Trivy" -Command "trivy" -VersionArgs @("--version")
Test-Tool -Name "Gitleaks" -Command "gitleaks" -VersionArgs @("version")
Test-Tool -Name "pre-commit" -Command "pre-commit" -VersionArgs @("--version")
Test-Tool -Name "Checkov" -Command "checkov" -VersionArgs @("--version")
Test-Tool -Name "yamllint" -Command "yamllint" -VersionArgs @("--version")

Write-Host "`n=== WSL / Ansible ===" -ForegroundColor Cyan
$wsl = Get-Command "wsl" -ErrorAction SilentlyContinue
if ($wsl) {
    $wslStatus = (& wsl --status 2>&1 | Select-Object -First 1)
    if ($LASTEXITCODE -eq 0 -and "$wslStatus" -notmatch "Access is denied") {
        Write-Host ("[OK]      {0,-24} {1}" -f "WSL", "$wslStatus") -ForegroundColor Green

        $ansibleVersion = (& wsl -- bash -lc "ansible --version 2>/dev/null | head -n 1" 2>$null)
        if ($LASTEXITCODE -eq 0 -and "$ansibleVersion".Trim().Length -gt 0) {
            Write-Host ("[OK]      {0,-24} {1}" -f "Ansible (WSL)", "$ansibleVersion".Trim()) -ForegroundColor Green
        }
        else {
            Write-Host ("[MISSING] {0,-24} Install ansible-core in WSL2" -f "Ansible (WSL)") -ForegroundColor Red
            $missing.Add("Ansible (WSL)")
        }
    }
    else {
        Write-Host ("[MISSING] {0,-24} WSL is installed but not usable" -f "WSL") -ForegroundColor Red
        $missing.Add("WSL")
    }
}
else {
    Write-Host ("[MISSING] {0,-24} Install WSL2 and Ubuntu" -f "WSL") -ForegroundColor Red
    $missing.Add("WSL")
}

Write-Host "`n=== Azure context ===" -ForegroundColor Cyan
$az = Get-Command "az" -ErrorAction SilentlyContinue
if ($az) {
    $account = (& az account show --query "{name:name,id:id,tenantId:tenantId}" -o tsv 2>$null)
    if ($LASTEXITCODE -eq 0 -and "$account".Trim().Length -gt 0) {
        Write-Host "[OK]      Azure CLI is signed in." -ForegroundColor Green
        Write-Host "          $account"
    }
    else {
        Write-Host "[WARN]    Azure CLI is installed but not signed in. Run: az login" -ForegroundColor Yellow
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
if ($missing.Count -eq 0) {
    Write-Host "All Day 1 prerequisites were found." -ForegroundColor Green
    exit 0
}

Write-Host ("Missing {0} prerequisite(s): {1}" -f $missing.Count, ($missing -join ", ")) -ForegroundColor Red
Write-Host "Install the missing tools, reopen the terminal, and run this script again." -ForegroundColor Yellow
exit 1

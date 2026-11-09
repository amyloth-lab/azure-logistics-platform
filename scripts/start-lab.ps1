<#
.SYNOPSIS
    Start the compute resources paused by stop-lab.ps1.

.DESCRIPTION
    Starts the AKS cluster and resumes paused serverless Azure SQL databases.
    This does not recreate any resources.

.EXAMPLE
    .\scripts\start-lab.ps1
#>
param(
    [string]$WorkloadResourceGroup = "rg-logistics-workload-dev",
    [string]$DataResourceGroup = "rg-logistics-data-dev"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

Write-Step "Checking Azure CLI login"
az account show --only-show-errors | Out-Null

Write-Step "Starting AKS cluster"
$aksName = az aks list `
    --resource-group $WorkloadResourceGroup `
    --query "[?contains(name, 'aks-logistics')].name | [0]" `
    --output tsv

if ([string]::IsNullOrWhiteSpace($aksName)) {
    Write-Warning "No AKS cluster found in $WorkloadResourceGroup."
} else {
    $aksState = az aks show `
        --resource-group $WorkloadResourceGroup `
        --name $aksName `
        --query provisioningState `
        --output tsv

    if ($aksState -eq "Stopped") {
        Write-Host "Starting AKS $aksName..."
        az aks start `
            --resource-group $WorkloadResourceGroup `
            --name $aksName `
            --no-wait `
            --only-show-errors
    } else {
        Write-Host "AKS $aksName is already $aksState."
    }
}

Write-Step "Resuming paused SQL databases"
$sqlServer = az sql server list `
    --resource-group $DataResourceGroup `
    --query "[0].name" `
    --output tsv

if ([string]::IsNullOrWhiteSpace($sqlServer)) {
    Write-Warning "No SQL server found in $DataResourceGroup."
} else {
    $databases = az sql db list `
        --resource-group $DataResourceGroup `
        --server $sqlServer `
        --query "[?name!='master'].{name:name,sku:sku.name,status:status}" `
        --output json | ConvertFrom-Json

    foreach ($db in $databases) {
        if ($db.status -eq "Paused") {
            Write-Host "Resuming SQL database $($db.name)..."
            az sql db resume `
                --resource-group $DataResourceGroup `
                --server $sqlServer `
                --name $db.name `
                --only-show-errors
        } else {
            Write-Host "SQL database $($db.name) is already $($db.status)."
        }
    }
}

Write-Host "`nStart operations submitted." -ForegroundColor Green
Write-Host "AKS can take 5-10 minutes to become Ready." -ForegroundColor Yellow
Write-Host "Check with: az aks command invoke -g $WorkloadResourceGroup -n $aksName --command 'kubectl get nodes'" -ForegroundColor Yellow

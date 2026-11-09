<#
.SYNOPSIS
    Stop the compute resources that can be paused in the logistics lab.

.DESCRIPTION
    Stops the AKS cluster and pauses serverless Azure SQL databases.
    It does not delete resources. APIM, Firewall, Bastion, Service Bus,
    ACR, Redis, public IPs, and storage continue to bill.

.EXAMPLE
    .\scripts\stop-lab.ps1

.EXAMPLE
    .\scripts\stop-lab.ps1 -Force
#>
param(
    [string]$WorkloadResourceGroup = "rg-logistics-workload-dev",
    [string]$DataResourceGroup = "rg-logistics-data-dev",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

if (-not $Force) {
    Write-Host "This will stop AKS and pause serverless SQL databases." -ForegroundColor Yellow
    Write-Host "APIM, Firewall, Bastion, Service Bus, ACR, Redis, and public IPs will keep billing."
    $answer = Read-Host "Type STOP to continue"
    if ($answer -ne "STOP") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Step "Checking Azure CLI login"
az account show --only-show-errors | Out-Null

Write-Step "Stopping AKS cluster"
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
        Write-Host "AKS $aksName is already stopped."
    } else {
        Write-Host "Stopping AKS $aksName..."
        az aks stop `
            --resource-group $WorkloadResourceGroup `
            --name $aksName `
            --no-wait `
            --only-show-errors
    }
}

Write-Step "Pausing serverless SQL databases"
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
        if ($db.sku -match "_S_") {
            if ($db.status -eq "Paused") {
                Write-Host "SQL database $($db.name) is already paused."
            } else {
                Write-Host "Pausing SQL database $($db.name)..."
                az sql db pause `
                    --resource-group $DataResourceGroup `
                    --server $sqlServer `
                    --name $db.name `
                    --only-show-errors
            }
        } else {
            Write-Warning "Skipping $($db.name): SKU $($db.sku) is not serverless."
        }
    }
}

Write-Host "`nStop operations submitted." -ForegroundColor Green
Write-Host "Still billing: APIM, Firewall, Bastion, Service Bus Premium, ACR Premium, Redis, public IPs, storage, Log Analytics." -ForegroundColor Yellow
Write-Host "Use .\scripts\start-lab.ps1 when you resume." -ForegroundColor Yellow

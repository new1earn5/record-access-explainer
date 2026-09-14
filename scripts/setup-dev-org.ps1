# One-command scratch org setup for trying out or developing Record Access Explainer.
# Creates a scratch org, deploys the app, assigns the permission set, seeds one sample
# record, and opens the app.
#
# Usage: .\scripts\setup-dev-org.ps1 [-Alias rae-dev] [-DevHub my-devhub]

param(
    [string]$Alias = "rae-dev",
    [string]$DevHub = ""
)

$ErrorActionPreference = "Stop"

Write-Host "==> Creating scratch org (alias: $Alias)..."
if ($DevHub -ne "") {
    sf org create scratch --definition-file config/project-scratch-def.json --alias $Alias --duration-days 7 --set-default --target-dev-hub $DevHub
} else {
    sf org create scratch --definition-file config/project-scratch-def.json --alias $Alias --duration-days 7 --set-default
}

Write-Host "==> Deploying source..."
sf project deploy start --source-dir force-app --target-org $Alias

Write-Host "==> Assigning the RAA_Record_Access_Auditor permission set..."
sf org assign permset --name RAA_Record_Access_Auditor --target-org $Alias

Write-Host "==> Creating a sample Account to scan..."
sf data create record --sobject Account --values "Name='Demo Account for Record Access Explainer'" --target-org $Alias

Write-Host "==> Opening the Record Access Explainer app..."
sf org open --target-org $Alias --path "lightning/n/raaRecordAccessExplainer"

Write-Host ""
Write-Host "Done. Scratch org '$Alias' is ready and expires in 7 days."
Write-Host "  - List orgs:   sf org list"
Write-Host "  - Delete now:  sf org delete scratch --target-org $Alias --no-prompt"

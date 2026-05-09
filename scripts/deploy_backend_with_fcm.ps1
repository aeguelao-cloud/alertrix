param(
  [Parameter(Mandatory = $true)]
  [string]$ServiceAccountJsonPath,
  [string]$StackName = "demo-backend",
  [string]$Region = "ap-southeast-5",
  [string]$AlertFromEmail = "",
  [int]$EmailCooldownSeconds = 60
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ServiceAccountJsonPath)) {
  throw "Service account JSON not found: $ServiceAccountJsonPath"
}

$jsonRaw = Get-Content $ServiceAccountJsonPath -Raw
$jsonB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($jsonRaw))

Set-Location "$PSScriptRoot\..\backend"

npm install

C:\Users\JUN\AppData\Roaming\Python\Python314\Scripts\sam.exe build

$parameterOverrides = @(
  "FirebaseServiceAccountJsonBase64=$jsonB64"
)
if ($AlertFromEmail -and $AlertFromEmail.Trim().Length -gt 0) {
  $parameterOverrides += "AlertFromEmail=$AlertFromEmail"
}
$parameterOverrides += "EmailCooldownSeconds=$EmailCooldownSeconds"

C:\Users\JUN\AppData\Roaming\Python\Python314\Scripts\sam.exe deploy `
  --stack-name $StackName `
  --region $Region `
  --capabilities CAPABILITY_IAM `
  --resolve-s3 `
  --no-confirm-changeset `
  --no-fail-on-empty-changeset `
  --parameter-overrides $parameterOverrides

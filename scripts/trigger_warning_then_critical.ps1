param(
  [string]$ApiBaseUrl = "https://b4sm23mlze.execute-api.ap-southeast-5.amazonaws.com/prod",
  [string[]]$Zones = @("Zone A - Pump Station", "Zone B - Valve Room", "Zone C - Storage Tank"),
  [int]$GapSeconds = 6
)

$ErrorActionPreference = "Stop"

function Send-Reading {
  param(
    [string]$SensorType,
    [double]$Value,
    [string]$Zone
  )

  $body = @{
    sensorType = $SensorType
    value = [math]::Round($Value, 2)
    zone = $Zone
    capturedAt = (Get-Date).ToUniversalTime().ToString("o")
  } | ConvertTo-Json -Compress

  return Invoke-RestMethod `
    -Method Post `
    -Uri "$ApiBaseUrl/api/sensors/ingest" `
    -ContentType "application/json" `
    -Body $body
}

function Pick-Zone {
  param([string[]]$ZonePool)
  if ($null -eq $ZonePool -or $ZonePool.Count -eq 0) {
    return "Zone A - Pump Station"
  }
  return $ZonePool[(Get-Random -Minimum 0 -Maximum $ZonePool.Count)]
}

$warningZone = Pick-Zone -ZonePool $Zones
$criticalZone = Pick-Zone -ZonePool $Zones

Write-Host "Step 1: Trigger WARNING (danger) by waterLevel=74 at $warningZone ..."
$warningResult = Send-Reading -SensorType "waterLevel" -Value 74 -Zone $warningZone
$warningResult | ConvertTo-Json -Depth 6

Write-Host "Waiting $GapSeconds seconds..."
Start-Sleep -Seconds $GapSeconds

Write-Host "Step 2: Trigger CRITICAL by waterLevel=90 at $criticalZone ..."
$criticalResult = Send-Reading -SensorType "waterLevel" -Value 90 -Zone $criticalZone
$criticalResult | ConvertTo-Json -Depth 6

Write-Host "Done. Refresh Dashboard / Alert Center."

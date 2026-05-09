param(
  [string]$ApiBaseUrl = "https://b4sm23mlze.execute-api.ap-southeast-5.amazonaws.com/prod",
  [string[]]$Zones = @("Zone A - Pump Station", "Zone B - Valve Room", "Zone C - Storage Tank")
)

$ErrorActionPreference = "Stop"

function Send-Critical {
  param(
    [string]$SensorType,
    [double]$Value,
    [string]$Zone
  )

  $body = @{
    sensorType = $SensorType
    value = $Value
    zone = $Zone
    capturedAt = (Get-Date).ToUniversalTime().ToString("o")
  } | ConvertTo-Json -Compress

  Invoke-RestMethod `
    -Method Post `
    -Uri "$ApiBaseUrl/api/sensors/ingest" `
    -ContentType "application/json" `
    -Body $body
}

Write-Host "Triggering CRITICAL alerts for all 3 sensors..."

$zoneWater = $Zones[0 % $Zones.Count]
$zoneVibration = $Zones[1 % $Zones.Count]
$zoneTemperature = $Zones[2 % $Zones.Count]

$r1 = Send-Critical -SensorType "waterLevel" -Value 90 -Zone $zoneWater
Start-Sleep -Milliseconds 300
$r2 = Send-Critical -SensorType "vibration" -Value 4.6 -Zone $zoneVibration
Start-Sleep -Milliseconds 300
$r3 = Send-Critical -SensorType "temperature" -Value 46 -Zone $zoneTemperature

Write-Host ""
Write-Host "Done. Results:"
Write-Host "Zones -> waterLevel: $zoneWater | vibration: $zoneVibration | temperature: $zoneTemperature"
$r1 | ConvertTo-Json -Depth 6
$r2 | ConvertTo-Json -Depth 6
$r3 | ConvertTo-Json -Depth 6

Write-Host ""
Write-Host "Now refresh Dashboard and Alert Center."

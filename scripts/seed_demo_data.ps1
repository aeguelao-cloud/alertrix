param(
  [string]$ApiBaseUrl = "https://b4sm23mlze.execute-api.ap-southeast-5.amazonaws.com/prod",
  [int]$Hours = 24,
  [int]$IntervalMinutes = 15,
  [switch]$GenerateCriticalNow = $true,
  [string[]]$Zones = @("Zone A - Pump Station", "Zone B - Valve Room", "Zone C - Storage Tank")
)

$ErrorActionPreference = "Stop"

function Send-Reading {
  param(
    [string]$SensorType,
    [double]$Value,
    [datetime]$CapturedAt,
    [string]$Zone
  )

  $body = @{
    sensorType = $SensorType
    value = [math]::Round($Value, 2)
    zone = $Zone
    capturedAt = $CapturedAt.ToUniversalTime().ToString("o")
  } | ConvertTo-Json -Compress

  Invoke-RestMethod `
    -Method Post `
    -Uri "$ApiBaseUrl/api/sensors/ingest" `
    -ContentType "application/json" `
    -Body $body | Out-Null
}

function Pick-Zone {
  param([string[]]$ZonePool)
  if ($null -eq $ZonePool -or $ZonePool.Count -eq 0) {
    return "Zone A - Pump Station"
  }
  return $ZonePool[(Get-Random -Minimum 0 -Maximum $ZonePool.Count)]
}

$start = (Get-Date).AddHours(-1 * $Hours)
$totalPoints = [int](($Hours * 60) / $IntervalMinutes)
if ($totalPoints -lt 1) { $totalPoints = 1 }

Write-Host "Seeding demo data to: $ApiBaseUrl"
Write-Host "Window: last $Hours hours, interval: $IntervalMinutes minutes, points per sensor: $totalPoints"

for ($i = 0; $i -lt $totalPoints; $i++) {
  $t = $start.AddMinutes($i * $IntervalMinutes)

  # Make three sensors visually distinct for demo charts:
  # - waterLevel: stepped trend with small waves
  # - vibration: low baseline + occasional spikes
  # - temperature: slow day-cycle curve
  $phase = ($i / [double][math]::Max($totalPoints, 1))

  $waterBase = 48 + ([math]::Floor($i / 3) % 8) * 2.1
  $waterWave = 1.6 * [math]::Sin($phase * [math]::PI * 3.2)
  $waterJitter = (($i % 4) - 1.5) * 0.45
  $waterLevel = $waterBase + $waterWave + $waterJitter

  $vibrationBase = 1.0 + 0.22 * [math]::Sin($phase * [math]::PI * 8.8)
  $vibrationNoise = (($i % 5) - 2) * 0.05
  $vibrationSpike = 0.0
  if (($i % 9) -eq 0) { $vibrationSpike = 0.85 }
  if (($i % 17) -eq 0) { $vibrationSpike = 1.35 }
  $vibration = $vibrationBase + $vibrationNoise + $vibrationSpike

  $temperatureBase = 29.4 + 3.1 * [math]::Sin($phase * [math]::PI * 1.15 - 0.6)
  $temperatureDrift = $phase * 0.8
  $temperatureRipple = 0.35 * [math]::Sin($phase * [math]::PI * 6.2)
  $temperature = $temperatureBase + $temperatureDrift + $temperatureRipple

  $zoneWater = Pick-Zone -ZonePool $Zones
  $zoneVibration = Pick-Zone -ZonePool $Zones
  $zoneTemperature = Pick-Zone -ZonePool $Zones

  Send-Reading -SensorType "waterLevel" -Value $waterLevel -CapturedAt $t -Zone $zoneWater
  Send-Reading -SensorType "vibration" -Value $vibration -CapturedAt $t -Zone $zoneVibration
  Send-Reading -SensorType "temperature" -Value $temperature -CapturedAt $t -Zone $zoneTemperature

  if (($i + 1) % 8 -eq 0) {
    Write-Host ("Progress: {0}/{1}" -f ($i + 1), $totalPoints)
  }
}

if ($GenerateCriticalNow) {
  # Force one fresh critical alert for demo walkthrough.
  Send-Reading -SensorType "waterLevel" -Value 90 -CapturedAt (Get-Date) -Zone (Pick-Zone -ZonePool $Zones)
  Write-Host "Injected one CRITICAL waterLevel reading (90%)."
}

Write-Host "Seed completed. Refresh Dashboard / Trends / Alert Center now."

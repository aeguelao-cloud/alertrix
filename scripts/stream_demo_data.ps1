param(
  [string]$ApiBaseUrl = "https://b4sm23mlze.execute-api.ap-southeast-5.amazonaws.com/prod",
  [int]$IntervalSeconds = 4,
  [string]$Zone = "Zone A - Pump Station",
  [switch]$InjectCriticalSpikes = $true
)

$ErrorActionPreference = "Stop"

function Send-Reading {
  param(
    [string]$SensorType,
    [double]$Value
  )

  $payload = @{
    sensorType = $SensorType
    value = [math]::Round($Value, 2)
    zone = $Zone
    capturedAt = (Get-Date).ToUniversalTime().ToString("o")
  } | ConvertTo-Json -Compress

  Invoke-RestMethod `
    -Method Post `
    -Uri "$ApiBaseUrl/api/sensors/ingest" `
    -ContentType "application/json" `
    -Body $payload | Out-Null
}

Write-Host "Streaming demo data to $ApiBaseUrl every $IntervalSeconds second(s)."
Write-Host "Press Ctrl+C to stop."

$tick = 0
while ($true) {
  $phase = $tick / 10.0

  # Normal-flow pattern (distinct per sensor).
  $waterLevel = 56 + 10 * [math]::Sin($phase * 0.9) + (($tick % 5) - 2) * 0.35
  $vibration = 1.15 + 0.45 * [math]::Sin($phase * 1.6) + (($tick % 3) - 1) * 0.07
  $temperature = 30.5 + 2.6 * [math]::Sin($phase * 0.55) + (($tick % 4) - 2) * 0.18

  # Optional periodic critical spikes for alert demo.
  if ($InjectCriticalSpikes -and ($tick % 30 -eq 0) -and $tick -gt 0) {
    $waterLevel = 90
  }
  if ($InjectCriticalSpikes -and ($tick % 45 -eq 0) -and $tick -gt 0) {
    $vibration = 4.6
  }
  if ($InjectCriticalSpikes -and ($tick % 60 -eq 0) -and $tick -gt 0) {
    $temperature = 46
  }

  Send-Reading -SensorType "waterLevel" -Value $waterLevel
  Send-Reading -SensorType "vibration" -Value $vibration
  Send-Reading -SensorType "temperature" -Value $temperature

  $tick++
  if ($tick % 5 -eq 0) {
    Write-Host ("Tick {0}: water={1}% vibration={2}mm/s temp={3}C" -f $tick, [math]::Round($waterLevel,1), [math]::Round($vibration,2), [math]::Round($temperature,1))
  }

  Start-Sleep -Seconds $IntervalSeconds
}

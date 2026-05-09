param(
  [string]$ApiBaseUrl = "https://b4sm23mlze.execute-api.ap-southeast-5.amazonaws.com/prod",
  [int]$IntervalSeconds = 4,
  [string]$Zone = ""
)

$ErrorActionPreference = "Stop"

function Send-Reading {
  param(
    [string]$SensorType,
    [double]$Value
  )

  $body = @{
    sensorType = $SensorType
    value = [math]::Round($Value, 2)
    zone = $Zone
    capturedAt = (Get-Date).ToUniversalTime().ToString("o")
  } | ConvertTo-Json -Compress

  Invoke-RestMethod `
    -Method Post `
    -Uri "$ApiBaseUrl/api/sensors/ingest" `
    -ContentType "application/json" `
    -Body $body | Out-Null
}

Write-Host "Starting NORMAL sensor stream..."
Write-Host "API: $ApiBaseUrl"
Write-Host "Interval: $IntervalSeconds s"

if ([string]::IsNullOrWhiteSpace($Zone)) {
  try {
    $locResp = Invoke-RestMethod -Method Get -Uri "$ApiBaseUrl/api/settings/device-location"
    $resolved = ($locResp.location | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($resolved)) {
      $Zone = $resolved
    }
  } catch {
    # Keep fallback when settings API is unavailable.
  }
}

if ([string]::IsNullOrWhiteSpace($Zone)) {
  $Zone = "Zone A - Pump Station"
}

Write-Host "Zone: $Zone"
Write-Host "Press Ctrl + C to stop."

while ($true) {
  # Keep values safely below warning thresholds:
  # waterLevel warning=70, vibration warning=2.8, temperature warning=35
  $waterLevel = 52 + (Get-Random -Minimum -2.5 -Maximum 2.5)
  $vibration = 1.4 + (Get-Random -Minimum -0.35 -Maximum 0.35)
  $temperature = 30.2 + (Get-Random -Minimum -1.2 -Maximum 1.2)

  Send-Reading -SensorType "waterLevel" -Value $waterLevel
  Send-Reading -SensorType "vibration" -Value $vibration
  Send-Reading -SensorType "temperature" -Value $temperature

  Write-Host ("[{0}] Normal stream -> water={1}%, vibration={2} mm/s, temperature={3} C" -f `
    (Get-Date -Format "HH:mm:ss"), `
    ([math]::Round($waterLevel, 1)), `
    ([math]::Round($vibration, 2)), `
    ([math]::Round($temperature, 1)))

  Start-Sleep -Seconds $IntervalSeconds
}

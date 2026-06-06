param(
  [string]$Port = "COM4",
  [int]$BaudRate = 115200,
  [string]$ApiBaseUrl = "https://b4sm23mlze.execute-api.ap-southeast-5.amazonaws.com/prod",
  [string]$Zone = "Zone A - Pump Station",
  [switch]$SendVibrationFallback,
  [double]$DefaultVibration = 0.0
)

$ErrorActionPreference = "Stop"

function Parse-Line {
  param([string]$Line)
  # Expected sample:
  # T=29.3,H=51.0,ADC=282,WL=0.00,VIB=1.23,VIB_RMS_ADC=18.3,ALARM=OFF,ADC_FAULT=0,OK
  $result = @{
    temperature = $null
    waterLevel = $null
    vibration = $null
  }

  if ($Line -match "T=([+-]?\d+(\.\d+)?)") {
    $result.temperature = [double]$Matches[1]
  }
  if ($Line -match "WL=([+-]?\d+(\.\d+)?)") {
    $result.waterLevel = [double]$Matches[1]
  }
  if ($Line -match "VIB=([+-]?\d+(\.\d+)?)") {
    $result.vibration = [double]$Matches[1]
  }

  return $result
}

function Post-Reading {
  param(
    [string]$SensorType,
    [double]$Value,
    [string]$CapturedAt
  )

  $body = @{
    sensorType = $SensorType
    value = $Value
    zone = $Zone
    capturedAt = $CapturedAt
  } | ConvertTo-Json -Compress

  Invoke-RestMethod `
    -Method Post `
    -Uri "$ApiBaseUrl/api/sensors/ingest" `
    -ContentType "application/json" `
    -Body $body | Out-Null
}

Write-Host "Opening serial port $Port @ $BaudRate ..." -ForegroundColor Cyan
$sp = New-Object System.IO.Ports.SerialPort $Port, $BaudRate, "None", 8, "One"
$sp.NewLine = "`n"
$sp.ReadTimeout = 1200
$sp.Open()

Write-Host "Arduino -> AWS stream started." -ForegroundColor Green
Write-Host "API: $ApiBaseUrl"
Write-Host "Zone: $Zone"
Write-Host "Press Ctrl+C to stop."
Write-Host ""

try {
  while ($true) {
    try {
      $line = $sp.ReadLine().Trim()
    } catch {
      continue
    }

    if (-not $line) { continue }
    $parsed = Parse-Line -Line $line
    $nowUtc = (Get-Date).ToUniversalTime().ToString("o")

    $posted = @()

    if ($null -ne $parsed.waterLevel) {
      Post-Reading -SensorType "waterLevel" -Value $parsed.waterLevel -CapturedAt $nowUtc
      $posted += "waterLevel=$($parsed.waterLevel)"
    }
    if ($null -ne $parsed.temperature) {
      Post-Reading -SensorType "temperature" -Value $parsed.temperature -CapturedAt $nowUtc
      $posted += "temperature=$($parsed.temperature)"
    }

    # Optional fallback for projects without vibration hardware.
    if ($null -ne $parsed.vibration) {
      Post-Reading -SensorType "vibration" -Value $parsed.vibration -CapturedAt $nowUtc
      $posted += "vibration=$($parsed.vibration)"
    } elseif ($SendVibrationFallback) {
      Post-Reading -SensorType "vibration" -Value $DefaultVibration -CapturedAt $nowUtc
      $posted += "vibration=$DefaultVibration"
    }

    if ($posted.Count -gt 0) {
      Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] " -NoNewline
      Write-Host ($posted -join ", ")
    } else {
      Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] skip: $line"
    }
  }
} finally {
  if ($sp -and $sp.IsOpen) {
    $sp.Close()
  }
}

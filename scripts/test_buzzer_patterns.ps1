param(
  [string]$FirmwarePath = "$PSScriptRoot\..\arduino\DHT11WaterLevelPractice\DHT11WaterLevelPractice.ino"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $FirmwarePath)) {
  throw "Firmware file not found: $FirmwarePath"
}

$source = Get-Content -LiteralPath $FirmwarePath -Raw

function Get-ConstNumber {
  param([string]$Name)
  $pattern = "const\s+(?:unsigned\s+long|float)\s+$Name\s*=\s*([0-9]+(?:\.[0-9]+)?)f?\s*;"
  $match = [regex]::Match($source, $pattern)
  if (-not $match.Success) {
    throw "Missing constant: $Name"
  }
  return [double]$match.Groups[1].Value
}

$warningPatternMs = Get-ConstNumber "BUZZER_WARNING_PATTERN_MS"
$warningOnMs = Get-ConstNumber "BUZZER_WARNING_ON_MS"
$criticalPatternMs = Get-ConstNumber "BUZZER_CRITICAL_PATTERN_MS"
$criticalOnMs = Get-ConstNumber "BUZZER_CRITICAL_ON_MS"
$criticalGapMs = Get-ConstNumber "BUZZER_CRITICAL_GAP_MS"

function Test-BuzzerPulse {
  param(
    [ValidateSet("WARNING", "CRITICAL")]
    [string]$Severity,
    [double]$ElapsedMs
  )

  if ($Severity -eq "WARNING") {
    return ($ElapsedMs % $warningPatternMs) -lt $warningOnMs
  }

  $phase = $ElapsedMs % $criticalPatternMs
  $secondStart = $criticalOnMs + $criticalGapMs
  $thirdStart = $secondStart + $criticalOnMs + $criticalGapMs
  return $phase -lt $criticalOnMs -or
    ($phase -ge $secondStart -and $phase -lt ($secondStart + $criticalOnMs)) -or
    ($phase -ge $thirdStart -and $phase -lt ($thirdStart + $criticalOnMs))
}

$sampleStepMs = 100
$windowMs = 10000
$warning = New-Object System.Collections.Generic.List[bool]
$critical = New-Object System.Collections.Generic.List[bool]

for ($elapsed = 0; $elapsed -lt $windowMs; $elapsed += $sampleStepMs) {
  $warning.Add((Test-BuzzerPulse -Severity WARNING -ElapsedMs $elapsed))
  $critical.Add((Test-BuzzerPulse -Severity CRITICAL -ElapsedMs $elapsed))
}

$warningSignature = ($warning | ForEach-Object { if ($_) { "1" } else { "0" } }) -join ""
$criticalSignature = ($critical | ForEach-Object { if ($_) { "1" } else { "0" } }) -join ""
$warningOnSamples = ($warning | Where-Object { $_ }).Count
$criticalOnSamples = ($critical | Where-Object { $_ }).Count

if ($warningSignature -eq $criticalSignature) {
  throw "Buzzer patterns are identical."
}

if ($criticalOnSamples -le $warningOnSamples) {
  throw "Critical pattern should be more urgent than warning. warning=$warningOnSamples critical=$criticalOnSamples"
}

if ($source -notmatch "severityForValue\(tempC,\s*TEMP_WARNING_C,\s*TEMP_CRITICAL_C\)" -or
    $source -notmatch "severityForValue\(waterLevelPercent,\s*WATER_LEVEL_WARNING_PERCENT,\s*WATER_LEVEL_CRITICAL_PERCENT\)" -or
    $source -notmatch "severityForValue\(vibrationLevel,\s*VIBRATION_WARNING_LEVEL,\s*VIBRATION_CRITICAL_LEVEL\)") {
  throw "Sensor severity mapping is incomplete."
}

Write-Host "PASS: warning and critical buzzer patterns are different."
Write-Host "warning on-samples=$warningOnSamples signature=$warningSignature"
Write-Host "critical on-samples=$criticalOnSamples signature=$criticalSignature"

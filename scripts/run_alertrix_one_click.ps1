$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
Set-Location $repoRoot

$configPath = Join-Path $PSScriptRoot "launch_config.ps1"
if (-not (Test-Path $configPath)) {
  throw "Missing config file: $configPath"
}

$cfg = & $configPath
if (-not $cfg.ApiBaseUrl) {
  throw "ApiBaseUrl is empty in scripts/launch_config.ps1"
}

function Test-PortInUse {
  param([int]$Port)

  $listener = $null
  try {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    $listener.Start()
    return $false
  } catch {
    return $true
  } finally {
    if ($listener -ne $null) {
      try { $listener.Stop() } catch {}
    }
  }
}

function Get-FreeWebPort {
  param(
    [int]$PreferredPort,
    [int]$MaxTries = 50
  )

  for ($i = 0; $i -le $MaxTries; $i++) {
    $candidate = $PreferredPort + $i
    if (-not (Test-PortInUse -Port $candidate)) {
      return $candidate
    }
  }

  throw "No free web port found near $PreferredPort."
}

function Sync-FirebaseMessagingServiceWorker {
  param([hashtable]$Config)

  $swPath = Join-Path $repoRoot "web\\firebase-messaging-sw.js"
  if (-not (Test-Path $swPath)) {
    return
  }

  $sw = Get-Content -Raw $swPath
  if ($Config.FirebaseApiKey) {
    $sw = $sw -replace "apiKey:\s*'[^']*'", "apiKey: '$($Config.FirebaseApiKey)'"
  }
  if ($Config.FirebaseAuthDomain) {
    $sw = $sw -replace "authDomain:\s*'[^']*'", "authDomain: '$($Config.FirebaseAuthDomain)'"
  }
  if ($Config.FirebaseProjectId) {
    $sw = $sw -replace "projectId:\s*'[^']*'", "projectId: '$($Config.FirebaseProjectId)'"
  }
  if ($Config.FirebaseStorageBucket) {
    $sw = $sw -replace "storageBucket:\s*'[^']*'", "storageBucket: '$($Config.FirebaseStorageBucket)'"
  }
  if ($Config.FirebaseMessagingSenderId) {
    $sw = $sw -replace "messagingSenderId:\s*'[^']*'", "messagingSenderId: '$($Config.FirebaseMessagingSenderId)'"
  }
  if ($Config.FirebaseAppId) {
    $sw = $sw -replace "appId:\s*'[^']*'", "appId: '$($Config.FirebaseAppId)'"
  }

  Set-Content -Path $swPath -Value $sw -NoNewline
}

Write-Host "Alertrix one-click startup" -ForegroundColor Cyan
Write-Host "Project: $repoRoot"
Write-Host "API: $($cfg.ApiBaseUrl)"

$selectedPort = Get-FreeWebPort -PreferredPort ([int]$cfg.WebPort)
if ($selectedPort -ne [int]$cfg.WebPort) {
  Write-Host "Preferred port $($cfg.WebPort) is busy, switching to $selectedPort." -ForegroundColor Yellow
}
Write-Host "Device: $($cfg.Device)  Port: $selectedPort"
Write-Host ""

try {
  $healthUrl = "$($cfg.ApiBaseUrl)/api/readings/latest"
  $null = Invoke-WebRequest -Uri $healthUrl -Method Get -TimeoutSec 8
  Write-Host "Backend check: OK" -ForegroundColor Green
} catch {
  Write-Host "Backend check: failed (still continuing to launch frontend)" -ForegroundColor Yellow
}

Sync-FirebaseMessagingServiceWorker -Config $cfg

flutter pub get

$args = @(
  "run",
  "-d", "$($cfg.Device)",
  "--web-port", "$selectedPort",
  "--dart-define=API_BASE_URL=$($cfg.ApiBaseUrl)"
)

if ($cfg.Device -in @("chrome", "edge")) {
  if ($cfg.UseFreshChromeProfile -and $cfg.ChromeUserDataDir) {
    $profilePathEscaped = [Regex]::Escape($cfg.ChromeUserDataDir)
    $lockedBrowserProcs = Get-CimInstance Win32_Process | Where-Object {
      ($_.Name -in @('chrome.exe', 'msedge.exe')) -and
      $_.CommandLine -and
      ($_.CommandLine -match $profilePathEscaped)
    }
    foreach ($proc in $lockedBrowserProcs) {
      try {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
      } catch {}
    }
    if ($lockedBrowserProcs.Count -gt 0) {
      Start-Sleep -Milliseconds 600
    }

    if (Test-Path $cfg.ChromeUserDataDir) {
      try {
        Remove-Item -LiteralPath $cfg.ChromeUserDataDir -Recurse -Force -ErrorAction Stop
      } catch {
        Write-Host "Fresh profile cleanup skipped: $($_.Exception.Message)" -ForegroundColor Yellow
      }
    }
    try {
      New-Item -ItemType Directory -Path $cfg.ChromeUserDataDir -Force | Out-Null
    } catch {}
    $args += "--web-browser-flag=--user-data-dir=$($cfg.ChromeUserDataDir)"
  }
  if ($cfg.DisableChromeExtensions) {
    $args += "--web-browser-flag=--disable-extensions"
  }
}

if ($cfg.FirebaseApiKey) { $args += "--dart-define=FIREBASE_API_KEY=$($cfg.FirebaseApiKey)" }
if ($cfg.FirebaseAppId) { $args += "--dart-define=FIREBASE_APP_ID=$($cfg.FirebaseAppId)" }
if ($cfg.FirebaseMessagingSenderId) { $args += "--dart-define=FIREBASE_MESSAGING_SENDER_ID=$($cfg.FirebaseMessagingSenderId)" }
if ($cfg.FirebaseProjectId) { $args += "--dart-define=FIREBASE_PROJECT_ID=$($cfg.FirebaseProjectId)" }
if ($cfg.FirebaseStorageBucket) { $args += "--dart-define=FIREBASE_STORAGE_BUCKET=$($cfg.FirebaseStorageBucket)" }
if ($cfg.FirebaseAuthDomain) { $args += "--dart-define=FIREBASE_AUTH_DOMAIN=$($cfg.FirebaseAuthDomain)" }
if ($cfg.FcmWebVapidKey) { $args += "--dart-define=FCM_WEB_VAPID_KEY=$($cfg.FcmWebVapidKey)" }
if ($null -ne $cfg.EnableWebFcm) {
  $enableWebFcm = [System.Convert]::ToBoolean($cfg.EnableWebFcm).ToString().ToLower()
  $args += "--dart-define=ENABLE_WEB_FCM=$enableWebFcm"
}

flutter @args

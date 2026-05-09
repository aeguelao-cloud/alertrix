param(
  [Parameter(Mandatory = $true)]
  [string]$ApiBaseUrl,
  [Parameter(Mandatory = $true)]
  [string]$FirebaseApiKey,
  [Parameter(Mandatory = $true)]
  [string]$FirebaseAppId,
  [Parameter(Mandatory = $true)]
  [string]$FirebaseMessagingSenderId,
  [Parameter(Mandatory = $true)]
  [string]$FirebaseProjectId,
  [string]$FirebaseStorageBucket = "",
  [string]$FirebaseAuthDomain = "",
  [string]$FcmWebVapidKey = "",
  [string]$ChromeUserDataDir = "F:\\403\\demo\\.chrome_fcm_profile",
  [switch]$DisableChromeExtensions
)

$ErrorActionPreference = "Stop"

Set-Location "$PSScriptRoot\.."

$swPath = Join-Path (Get-Location) "web\\firebase-messaging-sw.js"
if (Test-Path $swPath) {
  $sw = Get-Content -Raw $swPath
  if ($FirebaseApiKey) {
    $sw = $sw -replace "apiKey:\s*'[^']*'", "apiKey: '$FirebaseApiKey'"
  }
  if ($FirebaseAuthDomain) {
    $sw = $sw -replace "authDomain:\s*'[^']*'", "authDomain: '$FirebaseAuthDomain'"
  }
  if ($FirebaseProjectId) {
    $sw = $sw -replace "projectId:\s*'[^']*'", "projectId: '$FirebaseProjectId'"
  }
  if ($FirebaseStorageBucket) {
    $sw = $sw -replace "storageBucket:\s*'[^']*'", "storageBucket: '$FirebaseStorageBucket'"
  }
  if ($FirebaseMessagingSenderId) {
    $sw = $sw -replace "messagingSenderId:\s*'[^']*'", "messagingSenderId: '$FirebaseMessagingSenderId'"
  }
  if ($FirebaseAppId) {
    $sw = $sw -replace "appId:\s*'[^']*'", "appId: '$FirebaseAppId'"
  }
  Set-Content -Path $swPath -Value $sw -NoNewline
}

flutter pub get

$args = @(
  "run",
  "-d", "chrome",
  "--web-browser-flag=--user-data-dir=$ChromeUserDataDir",
  "--dart-define=API_BASE_URL=$ApiBaseUrl",
  "--dart-define=FIREBASE_API_KEY=$FirebaseApiKey",
  "--dart-define=FIREBASE_APP_ID=$FirebaseAppId",
  "--dart-define=FIREBASE_MESSAGING_SENDER_ID=$FirebaseMessagingSenderId",
  "--dart-define=FIREBASE_PROJECT_ID=$FirebaseProjectId",
  "--dart-define=FIREBASE_STORAGE_BUCKET=$FirebaseStorageBucket",
  "--dart-define=FIREBASE_AUTH_DOMAIN=$FirebaseAuthDomain",
  "--dart-define=FCM_WEB_VAPID_KEY=$FcmWebVapidKey"
)

if ($DisableChromeExtensions) {
  $args += "--web-browser-flag=--disable-extensions"
}

flutter @args

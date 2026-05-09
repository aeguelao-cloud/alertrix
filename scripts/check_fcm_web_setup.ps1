param(
  [string]$ApiKey = "AIzaSyCdaebCdME_g0QDjFYhysnQUpvEqlcmW3w",
  [string]$ProjectId = "alertrix-eb014",
  [string]$ProjectNumber = "509883742045",
  [string]$AppId = "1:509883742045:web:a755fe97ce4aa0c5c99ab4"
)

$ErrorActionPreference = "Stop"

Write-Host "Checking Firebase Installations API..." -ForegroundColor Cyan
$installBody = @{
  appId = $AppId
  authVersion = "FIS_v2"
  sdkVersion = "w:0.6.6"
} | ConvertTo-Json -Compress

$installResp = Invoke-RestMethod `
  -Method Post `
  -Uri "https://firebaseinstallations.googleapis.com/v1/projects/$ProjectId/installations" `
  -Headers @{
    "Content-Type" = "application/json"
    "x-goog-api-key" = $ApiKey
  } `
  -Body $installBody

if (-not $installResp.authToken.token) {
  throw "Installations API failed: no authToken returned."
}

Write-Host "Installations API: OK" -ForegroundColor Green

Write-Host "Checking FCM Registration API..." -ForegroundColor Cyan
$regBody = @{
  web = @{
    endpoint = "https://fcm.googleapis.com/fcm/send/fake-endpoint-for-healthcheck"
    auth = "fake-auth"
    p256dh = "fake-p256dh"
  }
} | ConvertTo-Json -Compress

$regResp = Invoke-RestMethod `
  -Method Post `
  -Uri "https://fcmregistrations.googleapis.com/v1/projects/$ProjectNumber/registrations" `
  -Headers @{
    "Content-Type" = "application/json"
    "x-goog-api-key" = $ApiKey
    "x-goog-firebase-installations-auth" = "$($installResp.authToken.token)"
  } `
  -Body $regBody

if (-not $regResp.token) {
  throw "FCM Registration API failed: no token returned."
}

Write-Host "FCM Registration API: OK" -ForegroundColor Green
Write-Host ""
Write-Host "Result: Cloud-side FCM setup is valid." -ForegroundColor Green
Write-Host "If app still shows 'FCM OFF', issue is browser profile/service worker state." -ForegroundColor Yellow

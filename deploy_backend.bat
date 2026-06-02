@echo off
setlocal EnableExtensions

set "ROOT_DIR=%~dp0"
set "BACKEND_DIR=%ROOT_DIR%backend"

cd /d "%BACKEND_DIR%"
if errorlevel 1 (
  echo Failed to enter backend directory.
  exit /b 1
)

set "AWS_EXE=C:\Program Files\Amazon\AWSCLIV2\aws.exe"
if not exist "%AWS_EXE%" set "AWS_EXE=aws"

set "SAM_CMD=C:\Program Files\Amazon\AWSSAMCLI\bin\sam.cmd"
if not exist "%SAM_CMD%" set "SAM_CMD=sam"

set "FIREBASE_SA_FILE="
for %%F in ("%ROOT_DIR%*-firebase-adminsdk-*.json") do (
  if not defined FIREBASE_SA_FILE set "FIREBASE_SA_FILE=%%~fF"
)

set "FIREBASE_JSON_B64="
if defined FIREBASE_SA_FILE (
  echo Using Firebase service account file: %FIREBASE_SA_FILE%
  for /f "usebackq delims=" %%B in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$raw=Get-Content -Raw -Path '%FIREBASE_SA_FILE%';$json=($raw | ConvertFrom-Json | ConvertTo-Json -Compress);[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))"`) do (
    if not defined FIREBASE_JSON_B64 set "FIREBASE_JSON_B64=%%B"
  )
  if not defined FIREBASE_JSON_B64 (
    echo Failed to encode Firebase service account JSON.
    exit /b 1
  )
) else (
  echo Firebase service account JSON not found in repo root. Deploy will continue without parameter override.
)

echo Checking AWS login status...
call "%AWS_EXE%" sts get-caller-identity >nul 2>&1
if errorlevel 1 (
  echo AWS session is missing or expired. Starting aws login...
  call "%AWS_EXE%" login
  if errorlevel 1 (
    echo aws login failed.
    exit /b 1
  )
)

echo Cleaning previous SAM build output...
if exist ".aws-sam\build" (
  rmdir /s /q ".aws-sam\build" >nul 2>&1
)

for /d %%D in (".aws-sam-build-*") do (
  rmdir /s /q "%%~fD" >nul 2>&1
)

for /d %%D in (".sam_build*") do (
  rmdir /s /q "%%~fD" >nul 2>&1
)

set "BUILD_DIR=%BACKEND_DIR%\.aws-sam-build-%RANDOM%%RANDOM%%RANDOM%"

echo Building backend with SAM...
call "%SAM_CMD%" build --build-dir "%BUILD_DIR%"
if errorlevel 1 (
  echo SAM build failed.
  exit /b 1
)

echo Verifying build artifacts are not empty...
if not exist "%BUILD_DIR%\template.yaml" (
  echo Build template not found: %BUILD_DIR%\template.yaml
  exit /b 1
)

echo Deploying backend stack...
if defined FIREBASE_JSON_B64 (
  call "%SAM_CMD%" deploy --template-file "%BUILD_DIR%\template.yaml" --stack-name demo-backend --region ap-southeast-5 --capabilities CAPABILITY_IAM --resolve-s3 --parameter-overrides "FirebaseServiceAccountJsonBase64=%FIREBASE_JSON_B64%" --no-confirm-changeset --no-fail-on-empty-changeset
) else (
  call "%SAM_CMD%" deploy --template-file "%BUILD_DIR%\template.yaml" --stack-name demo-backend --region ap-southeast-5 --capabilities CAPABILITY_IAM --resolve-s3 --no-confirm-changeset --no-fail-on-empty-changeset
)
if errorlevel 1 (
  echo SAM deploy failed.
  exit /b 1
)

echo.
echo Backend deploy finished.
exit /b 0

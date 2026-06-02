@echo off
setlocal EnableExtensions

cd /d "%~dp0.."
call ".\deploy_backend.bat"
exit /b %errorlevel%

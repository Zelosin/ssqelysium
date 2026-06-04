@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve_web.ps1" %*
pause

@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0run-client.ps1" %*

@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0run-server.ps1" %*

@echo off
setlocal

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0launch_stl_viewer.ps1' @args" %*
if exist "%~dp0logs\latest_port.txt" type "%~dp0logs\latest_port.txt"

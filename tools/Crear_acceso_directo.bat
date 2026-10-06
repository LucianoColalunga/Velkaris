@echo off
rem Crea el acceso directo "Velkaris" en el Escritorio (para quien descarga el .zip).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0crear_acceso_directo.ps1" -ExePath "%~dp0Velkaris.exe"
pause

@echo off
rem Compila Velkaris (cliente + servidor) y crea los accesos directos en el Escritorio.
rem Opciones: compilar.bat -Zip   |   compilar.bat -GodotPath "C:\Godot\Godot_v4.3-stable_win64.exe"
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build_windows.ps1" %*
pause

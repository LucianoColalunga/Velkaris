@echo off
setlocal
title Velkaris - Servidor dedicado
cd /d "%~dp0"

set "EXE=VelkarisServer.console.exe"
if not exist "%EXE%" set "EXE=VelkarisServer.exe"
if not exist "%EXE%" (
    echo No se encuentra VelkarisServer.exe en esta carpeta.
    pause
    exit /b 1
)

echo ============================================================
echo  Servidor de Velkaris
echo  Configuracion: server.cfg (puerto, contrasena, jugadores)
echo  Para apagarlo, cierra esta ventana o pulsa Ctrl+C.
echo ============================================================
"%EXE%" --headless -- --server %*
echo.
echo El servidor se ha detenido.
pause

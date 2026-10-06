<#
.SYNOPSIS
  Compila Velkaris para Windows (cliente + servidor dedicado) y crea los accesos directos.

.DESCRIPTION
  1. Localiza Godot 4.3+ (parametro -GodotPath, variable GODOT, PATH o carpetas habituales).
  2. Comprueba que las plantillas de exportacion estan instaladas.
  3. Importa el proyecto y exporta:
       build\windows\Velkaris.exe              (juego para todos los jugadores)
       build\server\VelkarisServer.exe         (servidor dedicado + .console.exe con logs)
       build\linux-server\velkaris_server.x86_64  (opcional, con -Linux, para un VPS)
  4. Crea los accesos directos "Velkaris" y "Velkaris - Servidor" en el Escritorio.
  5. Opcional (-Zip): empaqueta los .zip listos para subir a GitHub Releases.

.EXAMPLE
  .\tools\build_windows.ps1
.EXAMPLE
  .\tools\build_windows.ps1 -GodotPath "C:\Godot\Godot_v4.3-stable_win64.exe" -Zip
#>
[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [switch]$Linux,
    [switch]$Zip,
    [switch]$NoShortcut
)
$ErrorActionPreference = 'Stop'
$ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ToolsDir
$Build = Join-Path $ProjectRoot 'build'

function Write-Step([string]$Msg) { Write-Host "`n==> $Msg" -ForegroundColor Cyan }
function Stop-Build([string]$Msg) { Write-Host "`nERROR: $Msg" -ForegroundColor Red; exit 1 }

# rcedit: Godot 4.3 lo usa para incrustar el icono y la version en el .exe. Si esta en el PATH,
# Godot lo encuentra solo. Se descarga una version fija y se verifica su SHA-256.
$RceditUrl = 'https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe'
$RceditSha256 = '3E7801DB1A5EDBEC91B49A24A094AAD776CB4515488EA5A4CA2289C400EADE2A'

function Enable-Rcedit {
    $dir = Join-Path $Build '.tools'
    $exe = Join-Path $dir 'rcedit.exe'
    if (-not (Test-Path $exe)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $RceditUrl -OutFile $exe -UseBasicParsing
        } catch {
            Write-Host "    No se pudo descargar rcedit: el .exe tendra el icono generico de Godot." -ForegroundColor Yellow
            return
        }
    }
    if ((Get-FileHash $exe -Algorithm SHA256).Hash -ne $RceditSha256) {
        Remove-Item $exe -Force
        Write-Host '    rcedit descargado no coincide con el hash esperado; se descarta.' -ForegroundColor Yellow
        return
    }
    $env:PATH = "$dir;$env:PATH"
    Write-Host "    rcedit listo (icono y version del .exe)."
}

function Find-Godot([string]$Hint) {
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Hint) { $candidates.Add($Hint) }
    if ($env:GODOT) { $candidates.Add($env:GODOT) }
    foreach ($n in 'godot', 'godot4') {
        $cmd = Get-Command $n -ErrorAction SilentlyContinue
        if ($cmd) { $candidates.Add($cmd.Source) }
    }
    $dirs = @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents",
              'C:\Godot', "$env:LOCALAPPDATA\Programs", "$env:ProgramFiles\Godot",
              "$env:USERPROFILE\scoop\apps\godot\current")
    foreach ($d in $dirs) {
        if (Test-Path $d) {
            Get-ChildItem -Path $d -Filter 'Godot_v4*_win64*.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch 'mono' } | Sort-Object Name -Descending |
                ForEach-Object { $candidates.Add($_.FullName) }
        }
    }
    foreach ($c in $candidates) {
        if (-not (Test-Path $c)) { continue }
        # Se prefiere la variante _console.exe: muestra la salida de Godot en esta ventana.
        $console = $c -replace '(?<!_console)\.exe$', '_console.exe'
        if ($console -ne $c -and (Test-Path $console)) { return $console }
        return $c
    }
    return $null
}

function Invoke-Godot([string]$Godot, [string]$Arguments, [int]$TimeoutSec) {
    Write-Host "    godot $Arguments" -ForegroundColor DarkGray
    $p = Start-Process -FilePath $Godot -ArgumentList $Arguments -NoNewWindow -PassThru
    $null = $p.Handle  # Necesario en PowerShell 5.1 para poder leer ExitCode despues.
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        $p.Kill()
        Stop-Build "Godot no termino en $TimeoutSec s y se cancelo."
    }
    return $p.ExitCode
}

# --- 1. Godot ---------------------------------------------------------------------------
Write-Step 'Buscando Godot 4'
$godot = Find-Godot $GodotPath
if (-not $godot) {
    Stop-Build ("No encontre Godot. Descargalo (version estandar, no .NET) de https://godotengine.org/download/windows/`n" +
                "y vuelve a ejecutar:  .\tools\build_windows.ps1 -GodotPath 'C:\ruta\Godot_v4.x-stable_win64.exe'")
}
$verRaw = (& $godot --version 2>$null | Select-Object -Last 1)
if ("$verRaw" -notmatch '^(\d+)\.(\d+)(?:\.(\d+))?\.([a-z]+\d*)') { Stop-Build "No pude leer la version de Godot ('$verRaw')." }
$major = [int]$Matches[1]; $minor = [int]$Matches[2]
$tplName = if ($Matches[3]) { "$($Matches[1]).$($Matches[2]).$($Matches[3]).$($Matches[4])" } else { "$($Matches[1]).$($Matches[2]).$($Matches[4])" }
if ($major -ne 4 -or $minor -lt 3) { Stop-Build "Se necesita Godot 4.3 o superior (encontrado: $verRaw)." }
Write-Host "    $godot  (v$verRaw)"

# --- 2. Plantillas de exportacion ----------------------------------------------------------
Write-Step "Comprobando plantillas de exportacion $tplName"
$tplDirs = @((Join-Path $env:APPDATA "Godot\export_templates\$tplName"),
             (Join-Path (Split-Path -Parent $godot) "editor_data\export_templates\$tplName"))
$tplDir = $tplDirs | Where-Object { Test-Path (Join-Path $_ 'windows_release_x86_64.exe') } | Select-Object -First 1
if (-not $tplDir) {
    Stop-Build ("Faltan las plantillas de exportacion de Godot $tplName.`n" +
                "Abre el proyecto en Godot y ve a: Editor > Gestionar plantillas de exportacion > Descargar e instalar.")
}
if ($Linux -and -not (Test-Path (Join-Path $tplDir 'linux_release.x86_64'))) { Stop-Build 'Las plantillas no incluyen Linux.' }

# --- 3. Importar y exportar ------------------------------------------------------------------
Write-Step 'Preparando rcedit (icono del .exe)'
Enable-Rcedit

Write-Step 'Importando recursos del proyecto (la primera vez tarda un poco)'
$null = Invoke-Godot $godot "--headless --path `"$ProjectRoot`" --import" 600

Write-Step 'Exportando el cliente (Velkaris.exe)'
$clientDir = Join-Path $Build 'windows'
$clientExe = Join-Path $clientDir 'Velkaris.exe'
New-Item -ItemType Directory -Force -Path $clientDir | Out-Null
$code = Invoke-Godot $godot "--headless --path `"$ProjectRoot`" --export-release `"Windows Desktop`" `"$clientExe`"" 600
if (-not (Test-Path $clientExe)) { Stop-Build "La exportacion del cliente fallo (codigo $code). Revisa los mensajes de arriba." }
Copy-Item (Join-Path $ProjectRoot 'icon.ico') $clientDir -Force
Copy-Item (Join-Path $ToolsDir 'crear_acceso_directo.ps1') $clientDir -Force
Copy-Item (Join-Path $ToolsDir 'Crear_acceso_directo.bat') $clientDir -Force
Copy-Item (Join-Path $ToolsDir 'LEEME_JUGADORES.txt') $clientDir -Force

Write-Step 'Exportando el servidor dedicado (VelkarisServer.exe)'
$serverDir = Join-Path $Build 'server'
$serverExe = Join-Path $serverDir 'VelkarisServer.exe'
New-Item -ItemType Directory -Force -Path $serverDir | Out-Null
$code = Invoke-Godot $godot "--headless --path `"$ProjectRoot`" --export-release `"Windows Server`" `"$serverExe`"" 600
if (-not (Test-Path $serverExe)) { Stop-Build "La exportacion del servidor fallo (codigo $code)." }
Copy-Item (Join-Path $ProjectRoot 'icon.ico') $serverDir -Force
Copy-Item (Join-Path $ToolsDir 'iniciar_servidor.bat') $serverDir -Force
Copy-Item (Join-Path $ToolsDir 'abrir_puerto_firewall.ps1') $serverDir -Force
$serverCfg = Join-Path $serverDir 'server.cfg'
if (-not (Test-Path $serverCfg)) { Copy-Item (Join-Path $ProjectRoot 'server.cfg.example') $serverCfg }

if ($Linux) {
    Write-Step 'Exportando el servidor para Linux'
    $linuxDir = Join-Path $Build 'linux-server'
    $linuxBin = Join-Path $linuxDir 'velkaris_server.x86_64'
    New-Item -ItemType Directory -Force -Path $linuxDir | Out-Null
    $code = Invoke-Godot $godot "--headless --path `"$ProjectRoot`" --export-release `"Linux Server`" `"$linuxBin`"" 600
    if (-not (Test-Path $linuxBin)) { Stop-Build "La exportacion para Linux fallo (codigo $code)." }
    Copy-Item (Join-Path $ProjectRoot 'server.cfg.example') (Join-Path $linuxDir 'server.cfg') -Force
}

# --- 4. Accesos directos ------------------------------------------------------------------
if (-not $NoShortcut) {
    Write-Step 'Creando accesos directos en el Escritorio'
    & (Join-Path $ToolsDir 'crear_acceso_directo.ps1') -ExePath $clientExe -Name 'Velkaris'
    & (Join-Path $ToolsDir 'crear_acceso_directo.ps1') -ExePath (Join-Path $serverDir 'iniciar_servidor.bat') `
        -Name 'Velkaris - Servidor' -IconPath (Join-Path $serverDir 'icon.ico')
}

# --- 5. Paquetes para GitHub Releases -------------------------------------------------------
if ($Zip) {
    Write-Step 'Empaquetando .zip para GitHub Releases'
    $zipClient = Join-Path $Build 'Velkaris-Windows-x64.zip'
    $zipServer = Join-Path $Build 'Velkaris-Server-Windows-x64.zip'
    Compress-Archive -Path (Join-Path $clientDir '*') -DestinationPath $zipClient -Force
    Compress-Archive -Path (Join-Path $serverDir '*') -DestinationPath $zipServer -Force
    Write-Host "    $zipClient"
    Write-Host "    $zipServer"
}

Write-Host "`nListo." -ForegroundColor Green
Write-Host "  Juego:    $clientExe"
Write-Host "  Servidor: $(Join-Path $serverDir 'iniciar_servidor.bat')  (config: server.cfg)"

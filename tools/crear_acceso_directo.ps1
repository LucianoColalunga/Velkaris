<#
.SYNOPSIS
  Crea un acceso directo en el Escritorio con el icono del juego.
.EXAMPLE
  .\crear_acceso_directo.ps1 -ExePath .\Velkaris.exe
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [string]$Name = 'Velkaris',
    [string]$Arguments = '',
    [string]$IconPath = ''
)
$ErrorActionPreference = 'Stop'
$target = (Resolve-Path $ExePath).Path
# Icono: el indicado, o icon.ico junto al ejecutable, o el icono incrustado en el propio .exe.
$localIco = Join-Path (Split-Path -Parent $target) 'icon.ico'
$icon = if ($IconPath) { (Resolve-Path $IconPath).Path } elseif (Test-Path $localIco) { $localIco } else { $target }
# GetFolderPath respeta el Escritorio redirigido por OneDrive.
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop "$Name.lnk"
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath = $target
$lnk.Arguments = $Arguments
$lnk.WorkingDirectory = Split-Path -Parent $target
$lnk.IconLocation = "$icon,0"
$lnk.Description = 'Velkaris - La Guerra de los Tres Reinos'
$lnk.Save()
Write-Host "    Acceso directo creado: $lnkPath"

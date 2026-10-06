<#
.SYNOPSIS
  Abre (o cierra) el puerto UDP del servidor de Velkaris en el Firewall de Windows.
.DESCRIPTION
  Solo lo necesita quien HOSPEDA la partida. Pide permisos de administrador.
  Por seguridad, la regla se crea solo para redes "Privadas". Si tu red esta marcada como
  "Publica", cambiala a Privada en Configuracion > Red e Internet, o usa -AllProfiles.
.EXAMPLE
  .\abrir_puerto_firewall.ps1                 # abre UDP 7777 (redes privadas)
.EXAMPLE
  .\abrir_puerto_firewall.ps1 -Port 7777 -Remove
#>
[CmdletBinding()]
param(
    [int]$Port = 7777,
    [switch]$AllProfiles,
    [switch]$Remove
)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" -Port $Port"
    if ($AllProfiles) { $argList += ' -AllProfiles' }
    if ($Remove) { $argList += ' -Remove' }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
    exit
}

$ruleName = "Velkaris UDP $Port"
Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
if ($Remove) {
    Write-Host "Regla '$ruleName' eliminada."
} else {
    $fwProfile = if ($AllProfiles) { 'Any' } else { 'Private' }
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol UDP -LocalPort $Port `
        -Action Allow -Profile $fwProfile | Out-Null
    Write-Host "Regla '$ruleName' creada (perfil: $fwProfile)."
}
Read-Host 'Pulsa Enter para cerrar'

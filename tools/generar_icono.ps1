<#
.SYNOPSIS
  Genera icon.png (256 px, icono del proyecto Godot) e icon.ico (multi-tamaño, icono del .exe).
.DESCRIPTION
  Dibuja un escudo dividido en los colores de los tres reinos con la Esquirla de Ilun en el
  centro. No necesita programas externos: usa System.Drawing, incluido en Windows.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\generar_icono.ps1
#>
[CmdletBinding()]
param(
    [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if ((Split-Path -Leaf $OutDir) -eq 'tools') { $OutDir = Split-Path -Parent $OutDir }
Add-Type -AssemblyName System.Drawing

function New-ShieldPath {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddLine(40, 40, 128, 18)
    $p.AddLine(128, 18, 216, 40)
    $p.AddLine(216, 40, 216, 128)
    $p.AddBezier(216, 128, 216, 190, 170, 222, 128, 242)
    $p.AddBezier(128, 242, 86, 222, 40, 190, 40, 128)
    $p.CloseFigure()
    return $p
}

function New-Master {
    $bmp = New-Object System.Drawing.Bitmap 256, 256, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $shield = New-ShieldPath
    $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 22, 18, 32))), $shield)

    # Tres sectores: Brasalta (arriba), Céfira (abajo-derecha), Umbravel (abajo-izquierda).
    $g.SetClip($shield)
    $c = 128; $r = 190
    $g.FillPie((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 242, 107, 41))), $c - $r, $c - $r, 2 * $r, 2 * $r, 210, 120)
    $g.FillPie((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 140, 184, 255))), $c - $r, $c - $r, 2 * $r, 2 * $r, 330, 120)
    $g.FillPie((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 77, 204, 158))), $c - $r, $c - $r, 2 * $r, 2 * $r, 90, 120)
    $dark = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 22, 18, 32)), 7
    foreach ($deg in 90, 210, 330) {
        $rad = $deg * [Math]::PI / 180
        $g.DrawLine($dark, $c, $c, $c + [Math]::Cos($rad) * 200, $c + [Math]::Sin($rad) * 200)
    }
    $g.ResetClip()

    # Esquirla de Ilun (cristal central).
    $pts = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF 128, 62),
        (New-Object System.Drawing.PointF 164, 128),
        (New-Object System.Drawing.PointF 128, 194),
        (New-Object System.Drawing.PointF 92, 128))
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.PointF 128, 62), (New-Object System.Drawing.PointF 128, 194), ([System.Drawing.Color]::FromArgb(255, 255, 255, 255)), ([System.Drawing.Color]::FromArgb(255, 190, 210, 255))
    $g.FillPolygon($grad, $pts)
    $g.DrawPolygon($dark, $pts)
    $g.DrawLine((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(160, 120, 140, 200)), 3), 128, 62, 128, 194)

    # Borde dorado.
    $gold = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 235, 200, 110)), 10
    $gold.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.DrawPath($gold, $shield)
    $g.Dispose()
    return $bmp
}

function Get-PngBytes([System.Drawing.Bitmap]$src, [int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($src, 0, 0, $size, $size)
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return , $ms.ToArray()
}

$master = New-Master
$pngPath = Join-Path $OutDir 'icon.png'
$master.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)

# ICO con entradas PNG (formato soportado por Windows Vista y posteriores).
$sizes = 16, 24, 32, 48, 64, 128, 256
$images = @()
foreach ($s in $sizes) { $images += , (Get-PngBytes $master $s) }
$icoPath = Join-Path $OutDir 'icon.ico'
$fs = [System.IO.File]::Create($icoPath)
$w = New-Object System.IO.BinaryWriter $fs
$w.Write([UInt16]0); $w.Write([UInt16]1); $w.Write([UInt16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $dim = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([UInt16]1); $w.Write([UInt16]32)
    $w.Write([UInt32]$images[$i].Length); $w.Write([UInt32]$offset)
    $offset += $images[$i].Length
}
foreach ($img in $images) { $w.Write($img) }
$w.Close()
$master.Dispose()
Write-Host "Generados: $pngPath y $icoPath"

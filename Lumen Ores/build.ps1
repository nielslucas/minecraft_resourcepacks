<#
.SYNOPSIS
    Builds the Lumen Ores release zips into releases/<Version>/.

.DESCRIPTION
    1.21.1 (NeoForge): src/ as is.
    1.20.1 (Forge):    src/ with the files in src-1.20.1/ laid on top, without
                       Mega Showdown (no 1.20.1 version of that mod) and with
                       UTF-8 BOMs stripped from json/mcmeta files.
    pack-BAK.png is never shipped. Existing zips are only replaced with -Force.

.EXAMPLE
    .\build.ps1 -Version 0.3.0 -Target 1.20.1
#>
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [ValidateSet('all', '1.21.1', '1.20.1')][string]$Target = 'all',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot
$targets = @(
    @{ Mc = '1.21.1'; Loader = 'neoforge'; Layers = @('src'); Exclude = @('pack-BAK.png'); StripBom = $false },
    @{ Mc = '1.20.1'; Loader = 'forge'; Layers = @('src', 'src-1.20.1'); Exclude = @('pack-BAK.png', 'assets/mega_showdown/'); StripBom = $true }
) | Where-Object { $Target -eq 'all' -or $_.Mc -eq $Target }

$bom = [byte[]](0xEF, 0xBB, 0xBF)

foreach ($t in $targets) {
    # Collect files: later layers override earlier ones (key = path inside the zip).
    $files = [ordered]@{}
    foreach ($layer in $t.Layers) {
        $layerDir = Join-Path $root $layer
        Get-ChildItem -Path $layerDir -Recurse -File | Sort-Object FullName | ForEach-Object {
            $rel = $_.FullName.Substring($layerDir.Length + 1).Replace('\', '/')
            $files[$rel] = $_.FullName
        }
    }
    foreach ($ex in $t.Exclude) {
        @($files.Keys) | Where-Object { $_ -eq $ex -or ($ex.EndsWith('/') -and $_.StartsWith($ex)) } |
            ForEach-Object { $files.Remove($_) }
    }

    $outDir = Join-Path $root "releases\$Version"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $zipPath = Join-Path $outDir ("LumenOres_{0}_{1}_{2}.zip" -f $t.Mc, $t.Loader, $Version)
    if (Test-Path $zipPath) {
        if (-not $Force) { Write-Warning "Skipping $zipPath (exists, use -Force to replace)"; continue }
        Remove-Item $zipPath
    }

    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($rel in ($files.Keys | Sort-Object)) {
            $bytes = [System.IO.File]::ReadAllBytes($files[$rel])
            if ($t.StripBom -and $rel -match '\.(json|mcmeta)$' -and $bytes.Length -ge 3 -and
                $bytes[0] -eq $bom[0] -and $bytes[1] -eq $bom[1] -and $bytes[2] -eq $bom[2]) {
                $bytes = $bytes[3..($bytes.Length - 1)]
            }
            $entry = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
            $stream = $entry.Open()
            try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
        }
    } finally { $zip.Dispose() }

    Write-Host ("Built {0} ({1} files)" -f $zipPath, $files.Count)
}

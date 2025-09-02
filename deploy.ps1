<#
Packages a gadget folder into a .vgadget (zip) archive at repo root.
Output filename is derived from the first *.lua file (basename) found in the source folder.

Usage examples:
    pwsh ./deploy.ps1                           # uses default 'BlumDrawerMaker'
    pwsh ./deploy.ps1 -SourceFolder MyGadget    # package MyGadget folder
    pwsh ./deploy.ps1 -SourceFolder C:\path\to\OtherGadget

Parameters:
    -SourceFolder  Path (relative or absolute) to gadget source folder.
                                 Default: BlumDrawerMaker (under repo root)
    -Force         Overwrite existing .vgadget without prompt.
#>

param(
    [string]$SourceFolder = 'BlumDrawerMaker',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

# Resolve source folder (allow absolute or relative)
if (Test-Path $SourceFolder) {
    $gadgetFolder = (Resolve-Path $SourceFolder).Path
}
else {
    $gadgetFolder = Join-Path $repoRoot $SourceFolder
}
if (-not (Test-Path $gadgetFolder)) {
    Write-Error "Gadget folder not found: $gadgetFolder"
}

# Determine gadget base name from first .lua file
$luaFile = Get-ChildItem -Path $gadgetFolder -Filter *.lua -File -Recurse | Sort-Object FullName | Select-Object -First 1
if (-not $luaFile) {
    Write-Error "No .lua files found in $gadgetFolder to derive gadget name."
}
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($luaFile.Name)
$outputName = "$baseName.vgadget"
$outputPath = Join-Path $repoRoot $outputName

if (Test-Path $outputPath) {
    if ($Force) {
        Write-Host "Removing existing $outputName" -ForegroundColor Yellow
        Remove-Item $outputPath -Force
    }
    else {
        $ans = Read-Host "File $outputName exists. Overwrite? (y/N)"
        if ($ans -match '^[Yy]') {
            Remove-Item $outputPath -Force
        }
        else {
            Write-Warning 'Aborted by user.'
            exit 1
        }
    }
}

Write-Host "Creating $outputName with root folder '$baseName' from contents of $gadgetFolder" -ForegroundColor Cyan

# Staging directory to ensure everything is under a single top-level folder (required for .vgadget layout)
$stagingParent = Join-Path ([System.IO.Path]::GetTempPath()) ("gadgetpkg-" + [guid]::NewGuid())
$stagingRoot = Join-Path $stagingParent $baseName
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

# Copy all contents preserving structure
Copy-Item -Path (Join-Path $gadgetFolder '*') -Destination $stagingRoot -Recurse -Force

# Remove any nested archives that shouldn't ship
Get-ChildItem -Path $stagingRoot -Recurse -Include *.vgadget, *.zip -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

# Build a fresh temp zip path (avoid GetTempFileName zero-byte artifact)
$tmpZip = Join-Path ([System.IO.Path]::GetTempPath()) ("gadgetpkg-" + [guid]::NewGuid().ToString() + '.zip')
if (Test-Path $tmpZip) { Remove-Item $tmpZip -Force }

# Use .NET ZipFile to avoid historical Compress-Archive quirks
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue | Out-Null

# We want the archive to contain the top-level folder named $baseName; zip the stagingParent so that folder is included
[System.IO.Compression.ZipFile]::CreateFromDirectory($stagingParent, $tmpZip)

# Move/rename to .vgadget
Move-Item $tmpZip $outputPath -Force
Write-Host "Created $outputPath" -ForegroundColor Green

# Cleanup staging
Remove-Item $stagingParent -Recurse -Force -ErrorAction SilentlyContinue

# Optional: show resulting archive size
if (Test-Path $outputPath) {
    $sizeKB = [math]::Round((Get-Item $outputPath).Length / 1KB, 2)
    Write-Host "Archive size: $sizeKB KB" -ForegroundColor DarkGray
}

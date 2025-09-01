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

# Gather all files under the gadget folder.
Write-Host "Creating $outputName from contents of $gadgetFolder (base name from $($luaFile.Name))" -ForegroundColor Cyan

# Use a temporary zip then rename extension to .vgadget so gitignore can ignore these archives consistently.
$tmpZip = [System.IO.Path]::GetTempFileName()
Remove-Item $tmpZip -Force
$tmpZip = "$tmpZip.zip"

# Compress (exclude any prior .vgadget or .zip that might exist inside the folder)
$items = Get-ChildItem -Path $gadgetFolder -Recurse -File | Where-Object { $_.Extension -notin '.vgadget', '.zip' }

if ($items.Count -eq 0) {
    Write-Warning 'No files found to add to archive.'
}
else {
    Compress-Archive -Path $items.FullName -DestinationPath $tmpZip -Force
    Move-Item $tmpZip $outputPath
    Write-Host "Created $outputPath" -ForegroundColor Green
}

# Optional: show resulting archive size
if (Test-Path $outputPath) {
    $sizeKB = [math]::Round((Get-Item $outputPath).Length / 1KB, 2)
    Write-Host "Archive size: $sizeKB KB" -ForegroundColor DarkGray
}

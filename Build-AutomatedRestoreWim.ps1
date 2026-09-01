[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceWim,

    [string]$OutputWim = (Join-Path (Get-Location) "custom-boot.wim"),

    [ValidateRange(1, 99)]
    [int]$Index = 1,

    [string]$MountDirectory = (Join-Path $env:TEMP "AutomatedRestoreWimMount"),

    [string]$RestoreScript = (Join-Path $PSScriptRoot "auto_restore.cmd"),

    [string]$LauncherIni = (Join-Path $PSScriptRoot "Winpeshl.ini"),

    [switch]$Force
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator

    if (-not $principal.IsInRole($adminRole)) {
        throw "This script must be run from PowerShell as Administrator."
    }
}

function Resolve-ExistingFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description was not found: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Invoke-Dism {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Host "dism.exe $($Arguments -join ' ')" -ForegroundColor DarkGray
    & dism.exe @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "DISM failed with exit code $LASTEXITCODE."
    }
}

Assert-Administrator

$sourcePath = Resolve-ExistingFile -Path $SourceWim -Description "Source WIM"
$scriptPath = Resolve-ExistingFile -Path $RestoreScript -Description "Restore script"
$iniPath = Resolve-ExistingFile -Path $LauncherIni -Description "Launcher INI"

$outputParent = Split-Path -Parent $OutputWim
if ([string]::IsNullOrWhiteSpace($outputParent)) {
    $outputParent = (Get-Location).Path
}

if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
}

$outputPath = [IO.Path]::GetFullPath($OutputWim)
$mountPath = [IO.Path]::GetFullPath($MountDirectory)

if ($sourcePath -eq $outputPath) {
    throw "SourceWim and OutputWim must be different files. The source WIM is never modified in place."
}

if (Test-Path -LiteralPath $outputPath) {
    if (-not $Force) {
        throw "Output WIM already exists: $outputPath`nUse -Force to replace it."
    }

    Remove-Item -LiteralPath $outputPath -Force
}

if (-not (Test-Path -LiteralPath $mountPath)) {
    New-Item -ItemType Directory -Path $mountPath | Out-Null
}

if (-not (Test-Path -LiteralPath $mountPath -PathType Container)) {
    throw "MountDirectory is not a directory: $mountPath"
}

$mountContents = @(Get-ChildItem -LiteralPath $mountPath -Force)
if ($mountContents.Count -ne 0) {
    throw "MountDirectory must be empty: $mountPath"
}

$expectedIni = @(
    "[LaunchApps]"
    '%SYSTEMDRIVE%\Windows\System32\cmd.exe, /c %SYSTEMDRIVE%\Windows\System32\auto_restore.cmd'
)
$actualIni = @(Get-Content -LiteralPath $iniPath)

if (($actualIni -join "`n").Trim() -ne ($expectedIni -join "`n").Trim()) {
    throw "Winpeshl.ini does not contain the expected LaunchApps configuration."
}

if (Select-String -LiteralPath $scriptPath -Pattern "setlocal|EnableDelayedExpansion" -Quiet) {
    throw "The supplied auto_restore.cmd contains setlocal or delayed expansion. Use the tested stable script."
}

$mountedByThisScript = $false
$completed = $false

try {
    Write-Host "Checking WIM index $Index..." -ForegroundColor Cyan
    Invoke-Dism -Arguments @(
        "/English"
        "/Get-WimInfo"
        "/WimFile:$sourcePath"
        "/Index:$Index"
    )

    Write-Host "Creating working WIM..." -ForegroundColor Cyan
    Copy-Item -LiteralPath $sourcePath -Destination $outputPath -Force

    Write-Host "Mounting working WIM..." -ForegroundColor Cyan
    Invoke-Dism -Arguments @(
        "/English"
        "/Mount-Wim"
        "/WimFile:$outputPath"
        "/Index:$Index"
        "/MountDir:$mountPath"
        "/CheckIntegrity"
    )
    $mountedByThisScript = $true

    $diskRestorePath = Join-Path $mountPath "Program Files\Macrium\DiskRestore.exe"
    if (-not (Test-Path -LiteralPath $diskRestorePath -PathType Leaf)) {
        throw "DiskRestore.exe was not found in the expected location: $diskRestorePath"
    }

    $system32 = Join-Path $mountPath "Windows\System32"
    $startnetPath = Join-Path $system32 "startnet.cmd"

    if (-not (Test-Path -LiteralPath $startnetPath -PathType Leaf)) {
        throw "startnet.cmd was not found: $startnetPath"
    }

    Write-Host "Existing startnet.cmd (left unchanged):" -ForegroundColor Cyan
    Get-Content -LiteralPath $startnetPath | ForEach-Object { Write-Host "  $_" }

    $installedScript = Join-Path $system32 "auto_restore.cmd"
    $installedIni = Join-Path $system32 "Winpeshl.ini"

    Write-Host "Installing auto_restore.cmd and Winpeshl.ini..." -ForegroundColor Cyan
    Copy-Item -LiteralPath $scriptPath -Destination $installedScript -Force
    Copy-Item -LiteralPath $iniPath -Destination $installedIni -Force

    $sourceScriptHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $scriptPath).Hash
    $installedScriptHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installedScript).Hash
    $sourceIniHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $iniPath).Hash
    $installedIniHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installedIni).Hash

    if ($sourceScriptHash -ne $installedScriptHash) {
        throw "The installed auto_restore.cmd failed hash verification."
    }

    if ($sourceIniHash -ne $installedIniHash) {
        throw "The installed Winpeshl.ini failed hash verification."
    }

    Write-Host "Committing WIM changes..." -ForegroundColor Cyan
    Invoke-Dism -Arguments @(
        "/English"
        "/Unmount-Wim"
        "/MountDir:$mountPath"
        "/Commit"
        "/CheckIntegrity"
    )
    $mountedByThisScript = $false
    $completed = $true
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red

    if ($mountedByThisScript) {
        Write-Warning "An error occurred. Discarding this script's mounted changes."
        & dism.exe /English /Unmount-Wim "/MountDir:$mountPath" /Discard
        $mountedByThisScript = $false
    }

    throw
}
finally {
    if ($mountedByThisScript) {
        Write-Warning "The WIM is still mounted at: $mountPath"
    }
}

if ($completed) {
    $result = Get-Item -LiteralPath $outputPath
    $resultHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash

    Write-Host ""
    Write-Host "Automated restore WIM created successfully." -ForegroundColor Green
    Write-Host "Output: $($result.FullName)"
    Write-Host "Size:   $($result.Length) bytes"
    Write-Host "SHA256: $resultHash"
    Write-Host ""
    Write-Warning "Booting this WIM can overwrite Disk 0 without a final confirmation prompt."
}

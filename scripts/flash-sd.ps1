# Flash a full Ladrok TV SD-card image (WIPES the card, including /data), after a full backup.
# Needs: SD card in a card reader on this PC, an elevated (Administrator) PowerShell, WSL2.
# Usage:
#   .\scripts\flash-sd.ps1                                   -> lists candidate disks, writes nothing
#   .\scripts\flash-sd.ps1 -DiskNumber 3 -DryRun             -> all safety checks, writes nothing
#   .\scripts\flash-sd.ps1 -DiskNumber 3                     -> back up the card, write, verify
#   -Image <path> picks the image (default: newest ladrok-tv-*.img in the repo root); -NoBackup skips it.
param(
    [int]$DiskNumber = -1,
    [string]$Image,
    [switch]$DryRun,
    [switch]$NoBackup,
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'

function Get-WslPath([string]$p) {
    $full = (Resolve-Path $p).Path
    '/mnt/' + $full.Substring(0, 1).ToLower() + ($full.Substring(2) -replace '\\', '/')
}
$flasher = Get-WslPath (Join-Path $PSScriptRoot 'flash-image.sh')
if (-not $Image) {
    $Image = Get-ChildItem (Join-Path $PSScriptRoot '..\ladrok-tv-*.img') -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName
}

# Candidate disks: removable media only, never the Windows/boot disk
$candidates = Get-Disk | Where-Object {
    -not $_.IsBoot -and -not $_.IsSystem -and $_.BusType -in 'SD', 'USB', 'MMC' -and $_.Size -lt 512GB
}
if ($DiskNumber -lt 0) {
    Write-Host "Image: $Image"
    Write-Host 'Removable disks (put the Pi SD card in the reader, then re-run with -DiskNumber N):'
    $candidates | Format-Table Number, FriendlyName, BusType, PartitionStyle,
        @{ n = 'SizeGB'; e = { [math]::Round($_.Size / 1GB, 1) } } -AutoSize
    exit 0
}
if (-not $Image -or -not (Test-Path $Image)) { throw 'No image found; build one with scripts/build.sh or pass -Image.' }
$disk = $candidates | Where-Object Number -eq $DiskNumber
if (-not $disk) { throw "Disk $DiskNumber is not a removable SD/USB disk under 512 GB. Refusing." }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this from an elevated (Administrator) PowerShell: wsl --mount needs it.' }

Write-Host ("Target: disk {0}  {1}  {2:N1} GB" -f $disk.Number, $disk.FriendlyName, ($disk.Size / 1GB))
Write-Host "Image:  $Image"
if (-not $DryRun -and -not $Yes) {
    if ((Read-Host 'ERASE this card (all apps and data) and write the image? Type ERASE') -cne 'ERASE') { exit 1 }
}

$phys = "\\.\PHYSICALDRIVE$($disk.Number)"
wsl --mount $phys --bare
if ($LASTEXITCODE) { throw "wsl --mount $phys failed (close Explorer windows on the card and retry)." }
try {
    Start-Sleep 2
    $opts = @('--image', (Get-WslPath $Image), '--disk-size', "$($disk.Size)")
    if ($DryRun) { $opts += '--dry-run' }
    if ($NoBackup) { $opts += '--no-backup' }
    wsl -u root -e bash $flasher @opts
    if ($LASTEXITCODE) { throw 'flash-image.sh failed; see output above.' }
}
finally {
    wsl --unmount $phys | Out-Null
}
if (-not $DryRun) { Write-Host 'Done. Put the card back in the Pi and boot.' }

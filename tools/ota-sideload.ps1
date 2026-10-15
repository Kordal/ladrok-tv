# Install an OTA release (from scripts/make-ota.sh) on the Pi over adb, without the updater app.
# Usage: .\tools\ota-sideload.ps1 -Release D:\path\to\releases\<version> [-Variant userdebug|user] [-Reboot]
# Pushes the zip to /data/ota_package and runs update_engine_client with update-<variant>.json's
# values. (Releases before 2026-10-15 have a single update.json, which is used if present.)
param(
    [Parameter(Mandatory)][string]$Release,
    [string]$Variant = 'userdebug',
    [switch]$Reboot
)
$ErrorActionPreference = 'Stop'
$adb = Join-Path $PSScriptRoot 'platform-tools\adb.exe'
$json = Join-Path $Release "update-$Variant.json"
if (-not (Test-Path $json)) { $json = Join-Path $Release 'update.json' }
$cfg = Get-Content $json -Raw | ConvertFrom-Json
$zip = Join-Path $Release $cfg.file
if ((Get-Item $zip).Length -ne $cfg.size) { throw "$zip does not match update.json" }

$s = & (Join-Path $PSScriptRoot 'connect.ps1')
if ((& $adb -s $s shell id -u) -ne '0') {
    & $adb -s $s root | Out-Null; Start-Sleep 5
    $s = & (Join-Path $PSScriptRoot 'connect.ps1')
}
Write-Host "Device $s, installing $($cfg.version) ($($cfg.file))"
& $adb -s $s push $zip "/data/ota_package/$($cfg.file)"
if ($LASTEXITCODE) { throw 'push failed' }

$headers = ($cfg.payload_properties -join "`n")
$script = @"
F=/data/ota_package/$($cfg.file)
chown system:cache `$F; chmod 644 `$F; chcon u:object_r:ota_package_file:s0 `$F
update_engine_client --update --follow --payload=file://`$F --offset=$($cfg.payload_offset) --size=$($cfg.payload_size) --headers="$headers" 2>&1 | grep -vE 'DOWNLOADING|VERIFYING|FINALIZING' | tail -3
/vendor/bin/rpi_tryboot status
"@
$tmp = New-TemporaryFile
[IO.File]::WriteAllText($tmp, $script.Replace("`r`n", "`n"))
& $adb -s $s push $tmp /data/local/tmp/ota-sideload.sh | Out-Null
Remove-Item $tmp
& $adb -s $s shell sh /data/local/tmp/ota-sideload.sh
if ($Reboot) { & $adb -s $s reboot; Write-Host 'Rebooting into the new slot.' }

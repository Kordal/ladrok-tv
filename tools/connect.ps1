# Connect adb to the Raspberry Pi 5 (Android TV) over Wireless debugging.
# The TLS port changes on every reboot / adbd restart, so discover it via mDNS.
# Usage: .\tools\connect.ps1   -> prints the adb target (ip:port) on success
param([int]$Tries = 20)

$adb = Join-Path $PSScriptRoot 'platform-tools\adb.exe'
& $adb start-server | Out-Null

for ($i = 0; $i -lt $Tries; $i++) {
    $m = & $adb mdns services | Select-String '_adb-tls-connect._tcp\s+(\S+)'
    foreach ($hit in $m) {
        $target = $hit.Matches[0].Groups[1].Value
        if ((& $adb connect $target) -match '^(connected|already connected)') {
            Write-Output $target
            exit 0
        }
    }
    Start-Sleep 3
}
Write-Error "Pi not found via mDNS. Is it on, on Wi-Fi, with Wireless debugging enabled?"
exit 1

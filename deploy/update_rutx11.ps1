# =====================================================================
# EMS-Proxy Update-Skript (nur geaenderte Dateien) - RUTX11
# In ANSI speichern! Keine Umlaute/Sonderzeichen im Code verwenden.
# Vergleicht MD5-Hashes lokal vs. Router und uebertraegt nur Aenderungen.
# =====================================================================

param(
    [string]$RouterIP = "192.168.1.1",
    [string]$KeyFile  = "$env:USERPROFILE\.ssh\rutx11_key",
    [string]$SrcDir   = "$PSScriptRoot\..\EMS-Proxy"
)

$ErrorActionPreference = "Stop"

function Get-RemoteHash {
    param([string]$RemotePath)
    $out = & ssh -i $KeyFile -o BatchMode=yes -o StrictHostKeyChecking=no "root@$RouterIP" "md5sum $RemotePath 2>/dev/null" 2>$null
    if ($out -and $out -match "^([0-9a-f]{32})") { return $Matches[1] }
    return ""
}

$map = @(
    @{ src = "usr\bin\modbus_proxy.lua"; dst = "/usr/bin/modbus_proxy.lua"; restart = $true },
    @{ src = "usr\bin\powersplit.lua";   dst = "/usr/bin/powersplit.lua";   restart = $true },
    @{ src = "usr\bin\ems_watchdog.sh";  dst = "/usr/bin/ems_watchdog.sh";  restart = $true },
    @{ src = "www\setup.html";           dst = "/www/setup.html";           restart = $false },
    @{ src = "www\status.html";          dst = "/www/status.html";          restart = $false }
)
Get-ChildItem "$SrcDir\cgi-bin\*.cgi" | ForEach-Object {
    $map += @{ src = "cgi-bin\$($_.Name)"; dst = "/www/cgi-bin/$($_.Name)"; restart = $false }
}

$needsRestart = $false
$updated = 0

foreach ($m in $map) {
    $srcPath = Join-Path $SrcDir $m.src
    if (-not (Test-Path $srcPath)) { continue }
    $localHash  = (Get-FileHash -Algorithm MD5 $srcPath).Hash.ToLower()
    $remoteHash = Get-RemoteHash $m.dst
    if ($localHash -ne $remoteHash) {
        Write-Host "UPDATE: $($m.dst)"
        & scp -i $KeyFile -o BatchMode=yes -o StrictHostKeyChecking=no $srcPath "root@${RouterIP}:$($m.dst)"
        if ($LASTEXITCODE -eq 0) {
            $updated++
            if ($m.restart) { $needsRestart = $true }
        } else {
            Write-Warning "SCP-Fehler bei $($m.dst)"
        }
    }
}

if ($updated -gt 0) {
    & ssh -i $KeyFile -o BatchMode=yes -o StrictHostKeyChecking=no "root@$RouterIP" "chmod +x /usr/bin/*.lua /usr/bin/ems_watchdog.sh /www/cgi-bin/*.cgi"
    if ($needsRestart) {
        Write-Host "Kerndateien geaendert -> Proxy/Watchdog-Neustart"
        & ssh -i $KeyFile -o BatchMode=yes -o StrictHostKeyChecking=no "root@$RouterIP" "systemctl restart ems_watchdog 2>/dev/null || (killall ems_watchdog.sh 2>/dev/null; /usr/bin/ems_watchdog.sh &)"
    }
    Write-Host "$updated Datei(en) aktualisiert."
} else {
    Write-Host "Alles aktuell - keine Uebertragung noetig."
}

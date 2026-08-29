# =====================================================================
# EMS-Proxy Installer fuer Teltonika RUTX11 (Key-Auth, non-interactive)
# In ANSI speichern! Keine Umlaute/Sonderzeichen im Code verwenden.
#
# Ablauf:
#   1. Self-Test (SSH, SCP, modbus_cli)
#   2. Ordner anlegen
#   3. Dateien uebertragen
#   4. Rechte setzen, Dienste starten
# =====================================================================

param(
    [string]$RouterIP = "192.168.1.1",
    [string]$KeyFile  = "$env:USERPROFILE\.ssh\rutx11_key",
    [string]$SrcDir   = "$PSScriptRoot\..\EMS-Proxy"
)

$ErrorActionPreference = "Stop"

function Invoke-SSH {
    param([string]$Cmd)
    # BusyBox liefert teils True/False statt 0/1 -> Exitcode ueber Marker
    $full = "$Cmd; EC=`$?; echo EXITCODE:`$EC"
    $out = & ssh -i $KeyFile -o BatchMode=yes -o StrictHostKeyChecking=no "root@$RouterIP" $full 2>&1
    $text = $out -join "`n"
    Write-Host $text
    if ($text -match "EXITCODE:(\S+)") {
        $raw = $Matches[1].Trim()
        if ($raw -eq "True" -or $raw -eq "0") { return $true }
        Write-Warning "[SSH-FEHLER] Exitcode: $raw bei: $Cmd"
        return $false
    }
    return $true
}

function Invoke-SCP {
    param([string]$Src, [string]$Dst)
    & scp -i $KeyFile -o BatchMode=yes -o StrictHostKeyChecking=no $Src "root@${RouterIP}:$Dst"
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "[SCP-FEHLER] Exitcode $LASTEXITCODE bei: $Src -> $Dst"
        return $false
    }
    return $true
}

Write-Host "=== EMS-Proxy Installer (RUTX11: $RouterIP) ==="

# --- 1. Self-Test -----------------------------------------------------
if (-not (Test-Path $KeyFile)) {
    Write-Error "SSH-Key nicht gefunden: $KeyFile. Bitte zuerst Key-Auth einrichten (docs/SSH_Setup.md)."
}
if (-not (Invoke-SSH "echo SSH_OK")) { Write-Error "SSH-Verbindung fehlgeschlagen." }
Invoke-SSH "which modbus_cli || echo WARN: modbus_cli fehlt" | Out-Null

# --- 2. Ordner anlegen ------------------------------------------------
Invoke-SSH "mkdir -p /usr/bin /www/cgi-bin /etc/systemd/system /var/log" | Out-Null

# --- 3. Dateien uebertragen -------------------------------------------
$transfers = @(
    @{ src = "usr\bin\modbus_proxy.lua";              dst = "/usr/bin/modbus_proxy.lua" },
    @{ src = "usr\bin\powersplit.lua";                dst = "/usr/bin/powersplit.lua" },
    @{ src = "usr\bin\ems_watchdog.sh";               dst = "/usr/bin/ems_watchdog.sh" },
    @{ src = "etc\systemd\system\ems_watchdog.service"; dst = "/etc/systemd/system/ems_watchdog.service" },
    @{ src = "www\setup.html";                        dst = "/www/setup.html" },
    @{ src = "www\status.html";                       dst = "/www/status.html" }
)
Get-ChildItem "$SrcDir\cgi-bin\*.cgi" | ForEach-Object {
    $transfers += @{ src = "cgi-bin\$($_.Name)"; dst = "/www/cgi-bin/$($_.Name)" }
}
Get-ChildItem "$SrcDir\etc" -File | ForEach-Object {
    $transfers += @{ src = "etc\$($_.Name)"; dst = "/etc/$($_.Name)" }
}

$failed = 0
foreach ($t in $transfers) {
    $srcPath = Join-Path $SrcDir $t.src
    if (Test-Path $srcPath) {
        if (-not (Invoke-SCP $srcPath $t.dst)) { $failed++ }
    } else {
        Write-Warning "Quelldatei fehlt: $srcPath"
        $failed++
    }
}
if ($failed -gt 0) { Write-Error "$failed Datei(en) konnten nicht uebertragen werden." }

# --- 4. Rechte + Dienste ----------------------------------------------
Invoke-SSH "chmod +x /usr/bin/modbus_proxy.lua /usr/bin/powersplit.lua /usr/bin/ems_watchdog.sh /www/cgi-bin/*.cgi" | Out-Null
Invoke-SSH "[ -s /etc/tesvolt_proxy_mode ] || echo passthrough > /etc/tesvolt_proxy_mode" | Out-Null
Invoke-SSH "systemctl daemon-reload 2>/dev/null; systemctl enable ems_watchdog 2>/dev/null; systemctl restart ems_watchdog 2>/dev/null || /usr/bin/ems_watchdog.sh &" | Out-Null

Write-Host "=== Installation abgeschlossen. Status: http://$RouterIP/status.html ==="

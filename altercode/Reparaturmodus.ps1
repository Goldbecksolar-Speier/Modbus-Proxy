# ===============================================
# EMS-Proxy Reparaturmodus für RUTX11 (Key-Auth)
# ===============================================

param(
    [string]$RouterIP
)

# ============================================================
# 1. Router-IP abfragen
# ============================================================

if (-not $RouterIP) {
    Write-Host "Bitte IP des RUTX11 eingeben (z.B. 100.88.76.66): " -NoNewline
    $RouterIP = Read-Host
}

$global:RouterIP = $RouterIP
$global:localRoot = "C:\scripts\project\EMS-Proxy"

Write-Host ""
Write-Host "==============================================="
Write-Host " EMS-Proxy Reparaturmodus für RUTX11 (Key-Auth)"
Write-Host "==============================================="
Write-Host ""
Write-Host "Router-IP: $RouterIP"
Write-Host ""

# ============================================================
# 2. SSH-Key erzeugen + anzeigen + warten
# ============================================================

function Create-LocalKey {
    $keyDir = "$global:localRoot\ssh"
    $keyPath = "$keyDir\rutx11_key"
    $pubPath = "$keyPath.pub"

    if (-not (Test-Path $keyDir)) {
        New-Item -ItemType Directory -Path $keyDir | Out-Null
    }

    if (-not (Test-Path $keyPath)) {
        Write-Host ""
        Write-Host "? Erzeuge lokalen SSH-Key..."

        & ssh-keygen -t rsa -b 4096 -f $keyPath -N "" | Out-Null

        if (-not (Test-Path $pubPath)) {
            Write-Host "[FEHLER] Public Key wurde nicht erzeugt!"
            Write-Host "Bitte manuell ausführen:"
            Write-Host "ssh-keygen -t rsa -b 4096 -f `"$keyPath`" -N `"`"`"
            exit
        }

        Write-Host "[OK] Key erzeugt."
    } else {
        Write-Host ""
        Write-Host "[INFO] Lokaler Key existiert bereits."
    }

    Write-Host ""
    Write-Host "? Bitte folgenden Public Key auf dem Router eintragen:"
    Write-Host "   Datei: /etc/dropbear/authorized_keys"
    Write-Host ""
    Write-Host "-----------------------------------------------"
    Get-Content $pubPath
    Write-Host "-----------------------------------------------"
    Write-Host ""
    Write-Host "? Wenn der Key eingetragen ist, Enter drücken."
    Read-Host
}

# ============================================================
# 3. SSH Wrapper (non-interactive, Key-Auth)
# ============================================================

function SSH {
    param([string]$cmd)

    $fullCmd = "$cmd; EC=$?; echo EXITCODE:$EC"

    $proc = Start-Process -FilePath "ssh" `
        -ArgumentList "root@$global:RouterIP `"$fullCmd`"" `
        -NoNewWindow `
        -Wait `
        -PassThru

    $output = $proc.StandardOutput.ReadToEnd()
    $error  = $proc.StandardError.ReadToEnd()

    if ($output -match "EXITCODE:(.+)") {
        $exitRaw = $matches[1].Trim()

        if ($exitRaw -eq "True") { $exitcode = 0 }
        elseif ($exitRaw -eq "False") { $exitcode = 1 }
        else { $exitcode = [int]$exitRaw }

        if ($exitcode -ne 0) {
            Write-Host "[SSH-FEHLER] Exitcode: $exitcode"
            Write-Host $error
            return $false
        }
    }

    Write-Host $output
    return $true
}

# ============================================================
# 4. SCP Wrapper (non-interactive, Key-Auth)
# ============================================================

function SCP {
    param([string]$src, [string]$dst)

    $proc = Start-Process -FilePath "scp" `
        -ArgumentList "`"$src`" root@$global:RouterIP:`"$dst`"" `
        -NoNewWindow `
        -Wait `
        -PassThru

    if ($proc.ExitCode -ne 0) {
        Write-Host "[SCP-FEHLER] Exitcode: $($proc.ExitCode)"
        return $false
    }

    return $true
}

# ============================================================
# 5. Reparaturfunktionen
# ============================================================

function Fix-Webroot {
    Write-Host ""
    Write-Host "? Repariere Webroot..."

    SSH "mkdir -p /usr/share/ems-proxy"
    SSH "mkdir -p /usr/share/ems-proxy/cgi-bin"

    SCP "$global:localRoot\www\setup.html" "/usr/share/ems-proxy/setup.html"
    SCP "$global:localRoot\www\status.html" "/usr/share/ems-proxy/status.html"

    SCP "$global:localRoot\cgi-bin\set_mode.cgi" "/usr/share/ems-proxy/cgi-bin/set_mode.cgi"
    SCP "$global:localRoot\cgi-bin\get_mode.cgi" "/usr/share/ems-proxy/cgi-bin/get_mode.cgi"

    SSH "chmod +x /usr/share/ems-proxy/cgi-bin/*.cgi"
}

function Fix-Tesvolt {
    Write-Host ""
    Write-Host "? Repariere Tesvolt-Dateien..."

    SSH "mkdir -p /usr/share/ems-proxy"

    SCP "$global:localRoot\etc\tesvolt_cap_b" "/usr/share/ems-proxy/tesvolt_cap_b"
    SCP "$global:localRoot\etc\tesvolt_cap_t" "/usr/share/ems-proxy/tesvolt_cap_t"
    SCP "$global:localRoot\etc\tesvolt_proxy_mode" "/usr/share/ems-proxy/tesvolt_proxy_mode"
    SCP "$global:localRoot\etc\tesvolt_proxy_registers" "/usr/share/ems-proxy/tesvolt_proxy_registers"
    SCP "$global:localRoot\etc\tesvolt_split_mode" "/usr/share/ems-proxy/tesvolt_split_mode"
}

function Fix-ModbusCLI {
    Write-Host ""
    Write-Host "? Repariere modbus_cli..."

    SSH "opkg update"
    SSH "opkg install modbus-tools"
}

function Fix-CGI {
    Write-Host ""
    Write-Host "? Repariere CGI Engine..."

    SSH "uci set uhttpd.main.interpreter='.cgi=/bin/sh'"
    SSH "uci commit uhttpd"
    SSH "/etc/init.d/uHTTPd restart"
}

function Fix-Watchdog {
    Write-Host ""
    Write-Host "? Repariere Watchdog..."

    SCP "$global:localRoot\usr\bin\ems_watchdog.sh" "/usr/bin/ems_watchdog.sh"
    SSH "chmod +x /usr/bin/ems_watchdog.sh"

    SCP "$global:localRoot\etc\systemd\system\ems_watchdog.service" "/etc/init.d/ems-proxy-watchdog"
    SSH "chmod +x /etc/init.d/ems-proxy-watchdog"
    SSH "/etc/init.d/ems-proxy-watchdog enable"
}

# ============================================================
# 6. Reparaturmodus starten
# ============================================================

function RepairMode {

    Write-Host ""
    Write-Host "==============================================="
    Write-Host " Reparaturmodus gestartet"
    Write-Host "==============================================="
    Write-Host ""

    Fix-Webroot
    Fix-Tesvolt
    Fix-ModbusCLI
    Fix-CGI
    Fix-Watchdog

    Write-Host ""
    Write-Host "[OK] Reparaturmodus abgeschlossen."
    Write-Host ""
}

# ============================================================
# 7. Menü
# ============================================================

Write-Host "Was möchtest du tun?"
Write-Host "1 = Reparaturmodus starten"
Write-Host ""
Write-Host "Bitte Auswahl eingeben (1): " -NoNewline
$choice = Read-Host

switch ($choice) {
    "1" {
        Create-LocalKey
        RepairMode
    }
    default {
        Write-Host "[FEHLER] Ungültige Auswahl."
    }
}

Write-Host ""
Write-Host "Reparaturmodus beendet."
Write-Host ""

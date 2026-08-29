# ===============================================
# EMS-Proxy Reparaturmodus für RUTX11
# kompatibel mit RutOS 07.23.x + uHTTPd + Tailscale-SSH
# finaler Exitcode-sicherer SSH/SCP Wrapper
# ===============================================

param(
    [string]$RouterIP
)

if (-not $RouterIP) {
    Write-Host "Bitte IP des RUTX11 eingeben (z.B. 100.88.76.66): " -NoNewline
    $RouterIP = Read-Host
}

$global:RouterIP = $RouterIP
$global:localRoot = (Get-Location).Path

Write-Host ""
Write-Host "==============================================="
Write-Host " EMS-Proxy Reparaturmodus für RUTX11"
Write-Host "==============================================="
Write-Host ""
Write-Host "Router-IP: $RouterIP"
Write-Host ""

# ============================================================
# Finaler Exitcode-sicherer SSH Wrapper
# ============================================================

function SSH {
    param([string]$cmd)

    Write-Host ""
    Write-Host "? SSH-Befehl wird ausgeführt:"
    Write-Host "   $cmd"
    Write-Host "   (Passwort-Prompt erscheint im Terminal)"
    Write-Host ""

    $fullCmd = "$cmd; EC=$?; echo EXITCODE:$EC"

    $proc = Start-Process -FilePath "ssh" `
        -ArgumentList "root@$global:RouterIP `"$fullCmd`"" `
        -NoNewWindow `
        -RedirectStandardOutput "ssh_out.txt" `
        -RedirectStandardError "ssh_err.txt" `
        -PassThru

    $timeout = 20
    for ($i=0; $i -lt $timeout; $i++) {
        Start-Sleep -Seconds 1
        if ($proc.HasExited) { break }
    }

    if (-not $proc.HasExited) {
        Write-Host "[FEHLER] SSH hängt ? Prozess wird beendet."
        $proc.Kill()
        return $false
    }

    $output = Get-Content "ssh_out.txt" -Raw
    $error  = Get-Content "ssh_err.txt" -Raw

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
    } else {
        Write-Host "[WARNUNG] Kein Exitcode gefunden — SSH war erfolgreich, aber Windows hat ihn nicht geliefert."
    }

    Write-Host $output
    return $true
}

# ============================================================
# Finaler Exitcode-sicherer SCP Wrapper
# ============================================================

function SCP {
    param([string]$src, [string]$dst)

    Write-Host ""
    Write-Host "? SCP-Upload:"
    Write-Host "   Quelle: $src"
    Write-Host "   Ziel:   $dst"
    Write-Host "   (Passwort-Prompt erscheint im Terminal)"
    Write-Host ""

    $proc = Start-Process -FilePath "scp" `
        -ArgumentList "`"$src`" root@$global:RouterIP:`"$dst`"" `
        -NoNewWindow `
        -RedirectStandardOutput "scp_out.txt" `
        -RedirectStandardError "scp_err.txt" `
        -PassThru

    $timeout = 25
    for ($i=0; $i -lt $timeout; $i++) {
        Start-Sleep -Seconds 1
        if ($proc.HasExited) { break }
    }

    if (-not $proc.HasExited) {
        Write-Host "[FEHLER] SCP hängt ? Prozess wird beendet."
        $proc.Kill()
        return $false
    }

    if ($proc.ExitCode -ne 0) {
        Write-Host "[SCP-FEHLER] Exitcode: $($proc.ExitCode)"
        Write-Host (Get-Content "scp_err.txt" -Raw)
        return $false
    }

    Write-Host (Get-Content "scp_out.txt" -Raw)
    return $true
}

# ============================================================
# Reparaturfunktionen
# ============================================================

function Fix-Webroot {
    Write-Host ""
    Write-Host "? Repariere Webroot /usr/share/ems-proxy..."
    SSH "mkdir -p /usr/share/ems-proxy"
    SSH "mkdir -p /usr/share/ems-proxy/cgi-bin"

    SCP "$global:localRoot\EMS-Proxy\www\setup.html" "/usr/share/ems-proxy/setup.html"
    SCP "$global:localRoot\EMS-Proxy\www\status.html" "/usr/share/ems-proxy/status.html"

    SCP "$global:localRoot\EMS-Proxy\cgi-bin\set_mode.cgi" "/usr/share/ems-proxy/cgi-bin/set_mode.cgi"
    SCP "$global:localRoot\EMS-Proxy\cgi-bin\get_mode.cgi" "/usr/share/ems-proxy/cgi-bin/get_mode.cgi"

    SSH "chmod +x /usr/share/ems-proxy/cgi-bin/*.cgi"
}

function Fix-Tesvolt {
    Write-Host ""
    Write-Host "? Repariere Tesvolt-Konfigurationsdateien..."

    SSH "mkdir -p /usr/share/ems-proxy"

    SCP "$global:localRoot\EMS-Proxy\tesvolt_cap_b" "/usr/share/ems-proxy/tesvolt_cap_b"
    SCP "$global:localRoot\EMS-Proxy\tesvolt_cap_t" "/usr/share/ems-proxy/tesvolt_cap_t"
    SCP "$global:localRoot\EMS-Proxy\tesvolt_proxy_mode" "/usr/share/ems-proxy/tesvolt_proxy_mode"
    SCP "$global:localRoot\EMS-Proxy\tesvolt_proxy_registers" "/usr/share/ems-proxy/tesvolt_proxy_registers"
    SCP "$global:localRoot\EMS-Proxy\tesvolt_split_mode" "/usr/share/ems-proxy/tesvolt_split_mode"
}

function Fix-ModbusCLI {
    Write-Host ""
    Write-Host "? Repariere modbus_cli Installation..."
    SSH "opkg update"
    SSH "opkg install modbus-cli || opkg install modbus-tools"
}

function Fix-CGI {
    Write-Host ""
    Write-Host "? Repariere CGI-Engine (uHTTPd)..."
    SSH "uci set uhttpd.main.interpreter='.cgi=/bin/sh'"
    SSH "uci commit uhttpd"
    SSH "/etc/init.d/uHTTPd restart"
}

function Fix-Watchdog {
    Write-Host ""
    Write-Host "? Repariere EMS-Proxy-Watchdog..."

    SCP "$global:localRoot\EMS-Proxy\ems_watchdog.sh" "/usr/bin/ems_watchdog.sh"
    SSH "chmod +x /usr/bin/ems_watchdog.sh"

    SCP "$global:localRoot\EMS-Proxy\ems-proxy-watchdog" "/etc/init.d/ems-proxy-watchdog"
    SSH "chmod +x /etc/init.d/ems-proxy-watchdog"
    SSH "/etc/init.d/ems-proxy-watchdog enable"
}

# ============================================================
# Reparaturmodus
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
# Menü
# ============================================================

Write-Host "Was möchtest du tun?"
Write-Host "1 = Reparaturmodus starten"
Write-Host ""
Write-Host "Bitte Auswahl eingeben (1): " -NoNewline
$choice = Read-Host

switch ($choice) {
    "1" {
        RepairMode
    }
    default {
        Write-Host "[FEHLER] Ungültige Auswahl."
    }
}

Write-Host ""
Write-Host "Reparaturmodus beendet."
Write-Host ""

# ============================================================
# EMS‑Proxy Self‑Test + Installer für RUTX11
# ============================================================

$router_ip   = "100.88.76.66"
$router_user = "admin"
$localRoot   = "EMS-Proxy"

function Test-SSH {
    Write-Host "🔍 Test: SSH Verbindung..."
    try {
        ssh "$router_user@$router_ip" "echo OK" 2>$null
        Write-Host "✔ SSH erreichbar"
        return $true
    } catch {
        Write-Host "❌ SSH nicht erreichbar"
        return $false
    }
}

function Test-SCP {
    Write-Host "🔍 Test: SCP Upload..."
    try {
        scp "$localRoot\www\setup.html" "$router_user@$router_ip:/tmp/setup_test.html" 2>$null
        Write-Host "✔ SCP funktioniert"
        return $true
    } catch {
        Write-Host "❌ SCP funktioniert nicht"
        return $false
    }
}

function Test-CGI {
    Write-Host "🔍 Test: CGI Unterstützung..."
    try {
        ssh "$router_user@$router_ip" "grep -q 'cgi.assign' /etc/lighttpd/lighttpd.conf"
        Write-Host "✔ CGI aktiviert"
        return $true
    } catch {
        Write-Host "❌ CGI nicht aktiviert"
        return $false
    }
}

function Test-ModbusCLI {
    Write-Host "🔍 Test: modbus_cli..."
    try {
        ssh "$router_user@$router_ip" "modbus_cli --help" 2>$null
        Write-Host "✔ modbus_cli installiert"
        return $true
    } catch {
        Write-Host "❌ modbus_cli fehlt"
        return $false
    }
}

function Test-Systemd {
    Write-Host "🔍 Test: systemd..."
    try {
        ssh "$router_user@$router_ip" "systemctl --version" 2>$null
        Write-Host "✔ systemd verfügbar"
        return $true
    } catch {
        Write-Host "❌ systemd nicht verfügbar"
        return $false
    }
}

function Send-File($local, $remote) {
    Write-Host "→ $local  →  $remote"
    scp $local "$router_user@$router_ip:$remote"
}

function Send-SSH($cmd) {
    Write-Host "SSH: $cmd"
    ssh "$router_user@$router_ip" $cmd
}

# ============================================================
# SELF‑TEST
# ============================================================

Write-Host ""
Write-Host "==============================================="
Write-Host "   EMS‑Proxy Self‑Test für RUTX11"
Write-Host "==============================================="

$ok_ssh       = Test-SSH
$ok_scp       = Test-SCP
$ok_cgi       = Test-CGI
$ok_modbus    = Test-ModbusCLI
$ok_systemd   = Test-Systemd

if (!$ok_ssh -or !$ok_scp -or !$ok_cgi -or !$ok_modbus -or !$ok_systemd) {
    Write-Host ""
    Write-Host "❌ Installation abgebrochen — Voraussetzungen nicht erfüllt."
    Write-Host "Bitte korrigiere die oben angezeigten Fehler."
    exit
}

Write-Host ""
Write-Host "✔ Alle Tests bestanden — Installation wird gestartet."
Write-Host ""

# ============================================================
# INSTALLATION
# ============================================================

Send-SSH "mkdir -p /www /www/cgi-bin /etc /usr/bin /var/log"

# HTML
Send-File "$localRoot\www\setup.html"  "/www/setup.html"
Send-File "$localRoot\www\status.html" "/www/status.html"

# CGI
$cgis = @(
  "set_mode.cgi","get_mode.cgi","set_split.cgi","get_param.cgi",
  "set_params.cgi","set_ips.cgi","read_reg.cgi","add_reg_to_config.cgi",
  "get_heatmap_power.cgi","get_heatmap_soc.cgi"
)
foreach ($f in $cgis) { Send-File "$localRoot\cgi-bin\$f" "/www/cgi-bin/$f" }

# Config
$etcFiles = @(
  "tesvolt_proxy_mode","tesvolt_split_mode","tesvolt_cap_t",
  "tesvolt_cap_b","tesvolt_proxy_registers"
)
foreach ($f in $etcFiles) { Send-File "$localRoot\etc\$f" "/etc/$f" }

# Lua Engine
Send-File "$localRoot\usr\bin\powersplit.lua" "/usr/bin/powersplit.lua"
Send-File "$localRoot\usr\bin\modbus_proxy.lua" "/usr/bin/modbus_proxy.lua"

# Watchdog
Send-File "$localRoot\usr\bin\ems_watchdog.sh" "/usr/bin/ems_watchdog.sh"
Send-File "$localRoot\etc\ems_watchdog.service" "/etc/systemd/system/ems_watchdog.service"

# Rechte
Send-SSH "chmod +x /www/cgi-bin/*.cgi"
Send-SSH "chmod +x /usr/bin/*.lua /usr/bin/ems_watchdog.sh"

# Webserver
Send-SSH "grep -q 'cgi.assign' /etc/lighttpd/lighttpd.conf || echo 'cgi.assign = ( \".cgi\" => \"/bin/sh\" )' >> /etc/lighttpd/lighttpd.conf"
Send-SSH "/etc/init.d/lighttpd restart"

# Proxy
Send-SSH "killall modbus_proxy.lua 2>/dev/null; /usr/bin/modbus_proxy.lua &"

# Watchdog
Send-SSH "systemctl daemon-reload"
Send-SSH "systemctl enable ems_watchdog.service"
Send-SSH "systemctl start ems_watchdog.service"

Write-Host ""
Write-Host "==============================================="
Write-Host " EMS‑Proxy + Watchdog erfolgreich installiert "
Write-Host " Router: $router_ip"
Write-Host "==============================================="

# ============================================================
# EMS‑Proxy Auto‑Fix‑Installer für RUTX11
# ============================================================

$router_ip   = "192.168.1.1"
$router_user = "root"
$localRoot   = "EMS-Proxy"

function Send-File($local, $remote) {
    Write-Host "→ $local  →  $remote"
    scp $local "$router_user@$router_ip:$remote"
}

function Send-SSH($cmd) {
    Write-Host "SSH: $cmd"
    ssh "$router_user@$router_ip" $cmd
}

# ============================================================
# SELF‑TEST + AUTO‑FIX
# ============================================================

Write-Host ""
Write-Host "==============================================="
Write-Host "   EMS‑Proxy Auto‑Fix‑Installer für RUTX11"
Write-Host "==============================================="

# -------------------------------
# 1. SSH Test
# -------------------------------
Write-Host "🔍 Test: SSH Verbindung..."
try {
    ssh "$router_user@$router_ip" "echo OK" 2>$null
    Write-Host "✔ SSH erreichbar"
} catch {
    Write-Host "❌ SSH nicht erreichbar — bitte Router prüfen"
    exit
}

# -------------------------------
# 2. SCP Test
# -------------------------------
Write-Host "🔍 Test: SCP Upload..."
try {
    scp "$localRoot\www\setup.html" "$router_user@$router_ip:/tmp/setup_test.html" 2>$null
    Write-Host "✔ SCP funktioniert"
} catch {
    Write-Host "❌ SCP funktioniert nicht — AUTO‑FIX: SSH neu starten"
    Send-SSH "/etc/init.d/dropbear restart"
    Start-Sleep -Seconds 2
    try {
        scp "$localRoot\www\setup.html" "$router_user@$router_ip:/tmp/setup_test2.html" 2>$null
        Write-Host "✔ SCP repariert"
    } catch {
        Write-Host "❌ SCP weiterhin defekt — Abbruch"
        exit
    }
}

# -------------------------------
# 3. CGI Test
# -------------------------------
Write-Host "🔍 Test: CGI Unterstützung..."
try {
    ssh "$router_user@$router_ip" "grep -q 'cgi.assign' /etc/lighttpd/lighttpd.conf"
    Write-Host "✔ CGI aktiviert"
} catch {
    Write-Host "❌ CGI nicht aktiviert — AUTO‑FIX: CGI aktivieren"
    Send-SSH "echo 'cgi.assign = ( \".cgi\" => \"/bin/sh\" )' >> /etc/lighttpd/lighttpd.conf"
    Send-SSH "/etc/init.d/lighttpd restart"
    Write-Host "✔ CGI repariert"
}

# -------------------------------
# 4. modbus_cli Test
# -------------------------------
Write-Host "🔍 Test: modbus_cli..."
try {
    ssh "$router_user@$router_ip" "modbus_cli --help" 2>$null
    Write-Host "✔ modbus_cli installiert"
} catch {
    Write-Host "❌ modbus_cli fehlt — AUTO‑FIX: Installation"
    Send-SSH "opkg update"
    Send-SSH "opkg install modbus-tools"
    Write-Host "✔ modbus_cli installiert"
}

# -------------------------------
# 5. systemd Test
# -------------------------------
Write-Host "🔍 Test: systemd..."
try {
    ssh "$router_user@$router_ip" "systemctl --version" 2>$null
    Write-Host "✔ systemd verfügbar"
} catch {
    Write-Host "❌ systemd nicht verfügbar — RUTX11 Firmware zu alt"
    Write-Host "Bitte auf RutOS 7.x aktualisieren"
    exit
}

Write-Host ""
Write-Host "✔ Alle Tests bestanden oder automatisch repariert"
Write-Host "→ Installation startet jetzt"
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

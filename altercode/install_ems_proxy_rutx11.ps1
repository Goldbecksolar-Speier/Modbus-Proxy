# -------------------------------
# CONFIG
# -------------------------------
$router_ip   = "192.168.1.1"
$router_user = "root"

$localRoot = "EMS-Proxy"

function Send-File($local, $remote) {
    Write-Host "→ $local  →  $remote"
    scp $local "$router_user@$router_ip:$remote"
}

function Send-SSH($cmd) {
    Write-Host "SSH: $cmd"
    ssh "$router_user@$router_ip" $cmd
}

# -------------------------------
# 1. Basisstruktur auf dem RUTX11
# -------------------------------
Send-SSH "mkdir -p /www /www/cgi-bin /etc /usr/bin /var/log"

# -------------------------------
# 2. HTML-Seiten
# -------------------------------
Send-File "$localRoot\www\setup.html"  "/www/setup.html"
Send-File "$localRoot\www\status.html" "/www/status.html"

# -------------------------------
# 3. CGI-Skripte
# -------------------------------
$cgis = @(
  "set_mode.cgi",
  "get_mode.cgi",
  "set_split.cgi",
  "get_param.cgi",
  "set_params.cgi",
  "set_ips.cgi",
  "read_reg.cgi",
  "add_reg_to_config.cgi",
  "get_heatmap_power.cgi",
  "get_heatmap_soc.cgi"
)

foreach ($f in $cgis) {
    Send-File "$localRoot\cgi-bin\$f" "/www/cgi-bin/$f"
}

# -------------------------------
# 4. Config-Dateien
# -------------------------------
$etcFiles = @(
  "tesvolt_proxy_mode",
  "tesvolt_split_mode",
  "tesvolt_cap_t",
  "tesvolt_cap_b",
  "tesvolt_proxy_registers"
)

foreach ($f in $etcFiles) {
    Send-File "$localRoot\etc\$f" "/etc/$f"
}

# -------------------------------
# 5. Lua-Engine + Proxy
# -------------------------------
Send-File "$localRoot\usr\bin\powersplit.lua" "/usr/bin/powersplit.lua"
Send-File "$localRoot\usr\bin\modbus_proxy.lua" "/usr/bin/modbus_proxy.lua"

# -------------------------------
# 6. Watchdog-Skript + Service
# -------------------------------
Send-File "$localRoot\usr\bin\ems_watchdog.sh" "/usr/bin/ems_watchdog.sh"
Send-File "$localRoot\etc\ems_watchdog.service" "/etc/systemd/system/ems_watchdog.service"

# -------------------------------
# 7. Rechte setzen
# -------------------------------
Send-SSH "chmod +x /www/cgi-bin/*.cgi"
Send-SSH "chmod +x /usr/bin/powersplit.lua /usr/bin/modbus_proxy.lua /usr/bin/ems_watchdog.sh"

# -------------------------------
# 8. Webserver-CGI sicherstellen (optional)
# -------------------------------
Send-SSH "grep -q 'cgi.assign' /etc/lighttpd/lighttpd.conf || echo 'cgi.assign = ( \".cgi\" => \"/bin/sh\" )' >> /etc/lighttpd/lighttpd.conf"
Send-SSH "/etc/init.d/lighttpd restart"

# -------------------------------
# 9. Proxy starten
# -------------------------------
Send-SSH "killall modbus_proxy.lua 2>/dev/null; /usr/bin/modbus_proxy.lua &"

# -------------------------------
# 10. Watchdog aktivieren
# -------------------------------
Send-SSH "systemctl daemon-reload"
Send-SSH "systemctl enable ems_watchdog.service"
Send-SSH "systemctl start ems_watchdog.service"

Write-Host ""
Write-Host "----------------------------------------"
Write-Host " EMS-Proxy + Watchdog vollständig installiert "
Write-Host " Router: $router_ip"
Write-Host "----------------------------------------"

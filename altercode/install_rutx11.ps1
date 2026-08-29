# -------------------------------
# CONFIG
# -------------------------------
$router_ip   = "192.168.1.1"
$router_user = "root"
$router_pass = "yourpassword"

$localRoot = "EMS-Proxy"
$remoteRoot = "/www/EMS-Proxy"

# -------------------------------
# SSH / SCP Helper
# -------------------------------
function Send-File($local, $remote) {
    scp $local "$router_user@$router_ip:$remote"
}

function Send-SSH($cmd) {
    ssh "$router_user@$router_ip" $cmd
}

# -------------------------------
# 1. Create folder structure on RUTX11
# -------------------------------
Send-SSH "mkdir -p $remoteRoot"
Send-SSH "mkdir -p /www"
Send-SSH "mkdir -p /www/cgi-bin"
Send-SSH "mkdir -p /etc"
Send-SSH "mkdir -p /usr/bin"

# -------------------------------
# 2. Upload HTML files
# -------------------------------
Send-File "$localRoot\www\setup.html" "/www/setup.html"
Send-File "$localRoot\www\status.html" "/www/status.html"

# -------------------------------
# 3. Upload CGI scripts
# -------------------------------
Send-File "$localRoot\cgi-bin\set_mode.cgi" "/www/cgi-bin/set_mode.cgi"
Send-File "$localRoot\cgi-bin\get_mode.cgi" "/www/cgi-bin/get_mode.cgi"
Send-File "$localRoot\cgi-bin\set_split.cgi" "/www/cgi-bin/set_split.cgi"
Send-File "$localRoot\cgi-bin\get_param.cgi" "/www/cgi-bin/get_param.cgi"
Send-File "$localRoot\cgi-bin\set_params.cgi" "/www/cgi-bin/set_params.cgi"
Send-File "$localRoot\cgi-bin\set_ips.cgi" "/www/cgi-bin/set_ips.cgi"
Send-File "$localRoot\cgi-bin\read_reg.cgi" "/www/cgi-bin/read_reg.cgi"
Send-File "$localRoot\cgi-bin\add_reg_to_config.cgi" "/www/cgi-bin/add_reg_to_config.cgi"
Send-File "$localRoot\cgi-bin\get_heatmap_power.cgi" "/www/cgi-bin/get_heatmap_power.cgi"
Send-File "$localRoot\cgi-bin\get_heatmap_soc.cgi" "/www/cgi-bin/get_heatmap_soc.cgi"

# -------------------------------
# 4. Upload Lua engine
# -------------------------------
Send-File "$localRoot\usr\bin\powersplit.lua" "/usr/bin/powersplit.lua"
Send-File "$localRoot\usr\bin\modbus_proxy.lua" "/usr/bin/modbus_proxy.lua"

# -------------------------------
# 5. Upload config files
# -------------------------------
Send-File "$localRoot\etc\tesvolt_proxy_mode" "/etc/tesvolt_proxy_mode"
Send-File "$localRoot\etc\tesvolt_split_mode" "/etc/tesvolt_split_mode"
Send-File "$localRoot\etc\tesvolt_cap_t" "/etc/tesvolt_cap_t"
Send-File "$localRoot\etc\tesvolt_cap_b" "/etc/tesvolt_cap_b"
Send-File "$localRoot\etc\tesvolt_proxy_registers" "/etc/tesvolt_proxy_registers"

# -------------------------------
# 6. Make CGI scripts executable
# -------------------------------
Send-SSH "chmod +x /www/cgi-bin/*.cgi"

# -------------------------------
# 7. Make Lua scripts executable
# -------------------------------
Send-SSH "chmod +x /usr/bin/*.lua"

# -------------------------------
# 8. Start proxy service
# -------------------------------
Send-SSH "/usr/bin/modbus_proxy.lua &"

Write-Host "Installation complete!"

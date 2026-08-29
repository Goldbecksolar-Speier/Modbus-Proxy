# -------------------------------
# CONFIG
# -------------------------------
$router_ip   = "192.168.1.1"
$router_user = "root"
$router_pass = "yourpassword"

$localRoot = "EMS-Proxy"
$remoteRoot = "/www"

# -------------------------------
# SSH / SCP Helper
# -------------------------------
function Send-File($local, $remote) {
    Write-Host "Updating: $local → $remote"
    scp $local "$router_user@$router_ip:$remote"
}

function Send-SSH($cmd) {
    ssh "$router_user@$router_ip" $cmd
}

# -------------------------------
# FILE LISTS
# -------------------------------
$files_www = @(
    "setup.html",
    "status.html"
)

$files_cgi = @(
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

$files_etc = @(
    "tesvolt_proxy_mode",
    "tesvolt_split_mode",
    "tesvolt_cap_t",
    "tesvolt_cap_b",
    "tesvolt_proxy_registers"
)

$files_bin = @(
    "powersplit.lua",
    "modbus_proxy.lua"
)

# -------------------------------
# UPDATE WWW FILES
# -------------------------------
foreach ($f in $files_www) {
    $local = "$localRoot\www\$f"
    $remote = "$remoteRoot/$f"
    Send-File $local $remote
}

# -------------------------------
# UPDATE CGI FILES
# -------------------------------
foreach ($f in $files_cgi) {
    $local = "$localRoot\cgi-bin\$f"
    $remote = "$remoteRoot/cgi-bin/$f"
    Send-File $local $remote
}

# -------------------------------
# UPDATE ETC FILES
# -------------------------------
foreach ($f in $files_etc) {
    $local = "$localRoot\etc\$f"
    $remote = "/etc/$f"
    Send-File $local $remote
}

# -------------------------------
# UPDATE BIN FILES
# -------------------------------
foreach ($f in $files_bin) {
    $local = "$localRoot\usr\bin\$f"
    $remote = "/usr/bin/$f"
    Send-File $local $remote
}

# -------------------------------
# FIX PERMISSIONS
# -------------------------------
Write-Host "Fixing permissions..."
Send-SSH "chmod +x /www/cgi-bin/*.cgi"
Send-SSH "chmod +x /usr/bin/*.lua"

# -------------------------------
# RESTART PROXY
# -------------------------------
Write-Host "Restarting EMS Proxy..."
Send-SSH "killall modbus_proxy.lua 2>/dev/null"
Send-SSH "/usr/bin/modbus_proxy.lua &"

Write-Host ""
Write-Host "----------------------------------------"
Write-Host " EMS-Proxy Update Completed Successfully "
Write-Host "----------------------------------------"

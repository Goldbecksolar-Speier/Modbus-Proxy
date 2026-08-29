$router_ip   = "192.168.1.1"
$router_user = "root"

function Send-File($local, $remote) {
    scp $local "$router_user@$router_ip:$remote"
}

function Send-SSH($cmd) {
    ssh "$router_user@$router_ip" $cmd
}

# Upload watchdog script
Send-File "EMS-Proxy\usr\bin\ems_watchdog.sh" "/usr/bin/ems_watchdog.sh"

# Upload service file
Send-File "EMS-Proxy\etc\ems_watchdog.service" "/etc/systemd/system/ems_watchdog.service"

# Permissions
Send-SSH "chmod +x /usr/bin/ems_watchdog.sh"

# Enable + start service
Send-SSH "systemctl daemon-reload"
Send-SSH "systemctl enable ems_watchdog.service"
Send-SSH "systemctl start ems_watchdog.service"

Write-Host "Watchdog installed and running."

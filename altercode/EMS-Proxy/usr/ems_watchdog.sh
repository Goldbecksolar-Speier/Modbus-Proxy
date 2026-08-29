#!/bin/sh

LOG="/var/log/ems_watchdog.log"
PROXY="/usr/bin/modbus_proxy.lua"

echo "$(date) - Watchdog started" >> $LOG

while true; do

    # Check if proxy is running
    if ! pgrep -f "modbus_proxy.lua" >/dev/null; then
        echo "$(date) - Proxy not running → restarting" >> $LOG
        $PROXY &
        sleep 2
    fi

    # Check Tesvolt EMS register 30001 (SOC)
    SOC_T=$(modbus_cli tcp 127.0.0.1 -u 1 -r 30001 -t s16 2>/dev/null)
    if [ -z "$SOC_T" ]; then
        echo "$(date) - Tesvolt EMS unreachable → restarting proxy" >> $LOG
        killall modbus_proxy.lua 2>/dev/null
        $PROXY &
        sleep 2
    fi

    # Check BLUESUN PCS register 0x1140 (SOC)
    SOC_B=$(modbus_cli tcp 192.168.1.50 -u 1 -r 4416 -t s16 2>/dev/null)
    if [ -z "$SOC_B" ]; then
        echo "$(date) - BLUESUN PCS unreachable → restarting proxy" >> $LOG
        killall modbus_proxy.lua 2>/dev/null
        $PROXY &
        sleep 2
    fi

    # Check mode file
    MODE=$(cat /etc/tesvolt_proxy_mode 2>/dev/null)
    if [ -z "$MODE" ]; then
        echo "$(date) - Mode file missing → restoring default" >> $LOG
        echo "passthrough" > /etc/tesvolt_proxy_mode
    fi

    sleep 5
done

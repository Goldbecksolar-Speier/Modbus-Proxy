#!/bin/sh
# =====================================================================
# EMS Watchdog fuer RUTX11 (optimiert)
#  * ueberwacht Proxy-Prozess, Tesvolt-EMS-Link, BLUESUN-PCS-Link
#  * Failsafe: nach 3 BLUESUN-Fehlern -> passthrough + SetPower_B=0
#  * repariert fehlende Konfigdateien
#  * einfache Logrotation (max. 500 kB)
#  * kill per PID statt killall (sauberer auf BusyBox)
# =====================================================================

LOG="/var/log/ems_watchdog.log"
PROXY="/usr/bin/modbus_proxy.lua"
BLUESUN_IP=$(cat /etc/tesvolt_ip_b 2>/dev/null)
BLUESUN_IP=${BLUESUN_IP:-192.168.1.50}
TESVOLT_IP=$(cat /etc/tesvolt_ip_t 2>/dev/null)
TESVOLT_IP=${TESVOLT_IP:-192.168.1.40}

BS_FAIL=0
BS_FAIL_LIMIT=3

logmsg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG"
}

rotate_log() {
    if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 512000 ]; then
        mv "$LOG" "$LOG.old"
        logmsg "Logrotation durchgefuehrt"
    fi
}

restart_proxy() {
    logmsg "$1 -> Proxy-Neustart"
    PIDS=$(pgrep -f "modbus_proxy.lua")
    for P in $PIDS; do
        kill "$P" 2>/dev/null
    done
    sleep 1
    $PROXY &
    sleep 2
}

failsafe() {
    logmsg "FAILSAFE: $1 -> passthrough + SetPower_B=0"
    echo "passthrough" > /etc/tesvolt_proxy_mode
    # SetPower_B (0x1144 = 4420) auf 0 setzen
    modbus_cli tcp "$BLUESUN_IP" -u 1 -w 4420 -v 0 2>/dev/null
}

logmsg "Watchdog gestartet (Tesvolt=$TESVOLT_IP, BLUESUN=$BLUESUN_IP)"

while true; do
    rotate_log

    # 1) Proxy-Prozess pruefen
    if ! pgrep -f "modbus_proxy.lua" >/dev/null; then
        restart_proxy "Proxy laeuft nicht"
    fi

    # 2) Tesvolt EMS-Link: SOC (Register 30001) ueber den Proxy lesen
    SOC_T=$(modbus_cli tcp 127.0.0.1 -p 1502 -u 1 -r 30001 -t s16 2>/dev/null)
    if [ -z "$SOC_T" ]; then
        restart_proxy "Tesvolt EMS/Proxy antwortet nicht"
    fi

    # 3) BLUESUN PCS-Link: SOC (0x1140 = 4416) - nur im Split-Modus relevant
    MODE=$(cat /etc/tesvolt_proxy_mode 2>/dev/null)
    if [ "$MODE" = "split" ]; then
        SOC_B=$(modbus_cli tcp "$BLUESUN_IP" -u 1 -r 4416 -t s16 2>/dev/null)
        if [ -z "$SOC_B" ]; then
            BS_FAIL=$((BS_FAIL + 1))
            logmsg "BLUESUN nicht erreichbar ($BS_FAIL/$BS_FAIL_LIMIT)"
            if [ "$BS_FAIL" -ge "$BS_FAIL_LIMIT" ]; then
                failsafe "BLUESUN ${BS_FAIL_LIMIT}x nicht erreichbar"
                BS_FAIL=0
            fi
        else
            BS_FAIL=0
        fi
    fi

    # 4) Konfigdateien reparieren
    if [ ! -s /etc/tesvolt_proxy_mode ]; then
        logmsg "Mode-Datei fehlt -> Default passthrough"
        echo "passthrough" > /etc/tesvolt_proxy_mode
    fi
    if [ ! -s /etc/tesvolt_split_mode ]; then
        echo "capacity" > /etc/tesvolt_split_mode
    fi

    sleep 5
done

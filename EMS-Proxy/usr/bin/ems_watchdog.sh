#!/bin/sh
# =====================================================================
# EMS Watchdog fuer RUTX11 (optimiert)
#  * ueberwacht Proxy-Prozess, Tesvolt-EMS-Link, BLUESUN-PCS-Link
#  * Start/Stop-Steuerung ueber /etc/tesvolt_proxy_enabled (Setup-UI):
#    0 = Proxy stoppen und gestoppt lassen, sonst = laufen lassen.
#    (CGIs laufen als User uhttpd und duerfen den root-Proxy nicht
#    killen - deshalb setzt der Watchdog (root) den Wunsch um.)
#  * Failsafe: nach 3 BLUESUN-Fehlern -> passthrough + SetPower_B=0
#  * repariert fehlende Konfigdateien
#  * einfache Logrotation (max. 500 kB)
#  * kill per PID statt killall (sauberer auf BusyBox)
#  * KEINE Fallback-IPs: ohne /etc/tesvolt_ip_t/_b werden die
#    entsprechenden Checks uebersprungen (Proxy ist dann im Schutzmodus)
#  * Modbus-Zugriffe via mb_cli.lua (luasocket) - modbus_cli existiert
#    auf RUTOS NICHT!
#  * WICHTIG: EXC:<n> heisst der Proxy LEBT (Modbus-Exception ist eine
#    gueltige Antwort, z.B. Ziel-Batterie nicht erreichbar). Nur bei
#    ERR:* (connect refused / timeout) wird der Proxy neu gestartet.
# =====================================================================

LOG="/var/log/ems_watchdog.log"
PROXY="/usr/local/bin/modbus_proxy.lua"
MB="/usr/local/bin/mb_cli.lua"

BS_FAIL=0
BS_FAIL_LIMIT=3
STOP_LOGGED=0

logmsg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG"
}

rotate_log() {
    if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 512000 ]; then
        mv "$LOG" "$LOG.old"
        logmsg "Logrotation durchgefuehrt"
    fi
}

kill_proxy() {
    PIDS=$(pgrep -f "modbus_proxy.lua")
    for P in $PIDS; do
        kill "$P" 2>/dev/null
    done
}

restart_proxy() {
    logmsg "$1 -> Proxy-Neustart"
    kill_proxy
    sleep 1
    "$PROXY" &
    sleep 2
}

failsafe() {
    BLUESUN_IP=$(cat /etc/tesvolt_ip_b 2>/dev/null)
    [ -z "$BLUESUN_IP" ] && return
    logmsg "FAILSAFE: $1 -> passthrough + SetPower_B=0"
    echo "passthrough" > /etc/tesvolt_proxy_mode
    # SetPower_B=0 (Register 0x1144 = 4420; ACHTUNG: Schreibpfad UDAN-EMS
    # 0x1500/0x1530 noch in Herstellerklaerung - Register ggf. anpassen)
    lua "$MB" write "$BLUESUN_IP" 502 1 4420 0 >/dev/null 2>&1
}

logmsg "Watchdog gestartet"

while true; do
    rotate_log

    # 0) Start/Stop-Wunsch der Setup-UI umsetzen
    ENABLED=$(cat /etc/tesvolt_proxy_enabled 2>/dev/null)
    [ -z "$ENABLED" ] && ENABLED=1
    if [ "$ENABLED" = "0" ]; then
        if pgrep -f "modbus_proxy.lua" >/dev/null; then
            logmsg "Proxy per Setup-UI gestoppt -> beende Prozess"
            kill_proxy
        fi
        if [ "$STOP_LOGGED" = "0" ]; then
            logmsg "Proxy angehalten (enabled=0) - warte auf Start per UI"
            STOP_LOGGED=1
        fi
        sleep 5
        continue
    fi
    if [ "$STOP_LOGGED" = "1" ]; then
        logmsg "Proxy per Setup-UI wieder freigegeben (enabled=1)"
        STOP_LOGGED=0
    fi

    # IPs bei jedem Durchlauf frisch lesen (Setup-UI kann sie jederzeit setzen)
    TESVOLT_IP=$(cat /etc/tesvolt_ip_t 2>/dev/null)
    BLUESUN_IP=$(cat /etc/tesvolt_ip_b 2>/dev/null)

    # 1) Proxy-Prozess pruefen
    if ! pgrep -f "modbus_proxy.lua" >/dev/null; then
        restart_proxy "Proxy laeuft nicht"
    fi

    # 2) Proxy-Erreichbarkeit: SOC (Register 30001 -> FC04 addr 0) via Proxy.
    #    OK:*  -> alles gut
    #    EXC:* -> Proxy LEBT (z.B. EXC:11 Ziel-Batterie down) -> KEIN Neustart
    #    ERR:* -> Proxy antwortet nicht auf TCP -> Neustart
    R=$(lua "$MB" read 127.0.0.1 1502 1 4 0 2>/dev/null)
    case "$R" in
        OK:*)  : ;;
        EXC:*) : ;; # Proxy lebt; Ziel-Problem wird im Proxy-Log gefuehrt
        *)     restart_proxy "Proxy antwortet nicht auf Port 1502 ($R)" ;;
    esac

    # 3) BLUESUN PCS-Link: SOC (0x1140 = 4416, FC04) - nur im Split-Modus
    #    und NICHT im Simulationsmodus (keine echten Geraete!)
    MODE=$(cat /etc/tesvolt_proxy_mode 2>/dev/null)
    SIM=$(cat /etc/tesvolt_sim 2>/dev/null)
    if [ "$MODE" = "split" ] && [ -n "$BLUESUN_IP" ] && [ "$SIM" != "1" ]; then
        SOC_B=$(lua "$MB" read "$BLUESUN_IP" 502 1 4 4416 2>/dev/null)
        case "$SOC_B" in
            OK:*|EXC:*) BS_FAIL=0 ;;
            *)
                BS_FAIL=$((BS_FAIL + 1))
                logmsg "BLUESUN nicht erreichbar ($BS_FAIL/$BS_FAIL_LIMIT)"
                if [ "$BS_FAIL" -ge "$BS_FAIL_LIMIT" ]; then
                    failsafe "BLUESUN ${BS_FAIL_LIMIT}x nicht erreichbar"
                    BS_FAIL=0
                fi
                ;;
        esac
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

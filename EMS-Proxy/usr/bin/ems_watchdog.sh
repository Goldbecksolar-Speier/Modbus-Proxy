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
#  * NEU: 24h-Verlaufs-Sampler - alle 5 min werden die UI-Register
#    ueber den Proxy gelesen und nach /tmp/ems_history.csv geschrieben
#    (RAM, flash-schonend; Format ts;reg;rohwert; Pruning auf 24 h).
#    status.html laedt diese Historie via get_history.cgi.
# =====================================================================

LOG="/var/log/ems_watchdog.log"
PROXY="/usr/local/bin/modbus_proxy.lua"
MB="/usr/local/bin/mb_cli.lua"

# Historie: reg:fc:addr (Adresse = Proxy-Adressraum wie in status.html)
HIST="/tmp/ems_history.csv"
HIST_BUCKET_FILE="/tmp/ems_history.bucket"
HIST_REGS="30001:4:0 30003:4:2 30004:4:3 30005:4:4 30007:4:6 30008:4:7 30011:4:10 30015:4:14 40003:3:2 40004:3:3"
HIST_WINDOW=86400
HIST_BUCKET_S=300

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

# --- 24h-Historie: alle 5 min ein Sample pro Register ueber den Proxy ---
sample_history() {
    NOW=$(date +%s)
    BUCKET=$(( NOW / HIST_BUCKET_S * HIST_BUCKET_S ))
    LAST=$(cat "$HIST_BUCKET_FILE" 2>/dev/null)
    [ "$BUCKET" = "$LAST" ] && return
    echo "$BUCKET" > "$HIST_BUCKET_FILE"
    for ENTRY in $HIST_REGS; do
        REG=${ENTRY%%:*}
        REST=${ENTRY#*:}
        FC=${REST%%:*}
        ADDR=${REST#*:}
        R=$(lua "$MB" read 127.0.0.1 1502 1 "$FC" "$ADDR" 2>/dev/null)
        case "$R" in
            OK:*) echo "$BUCKET;$REG;${R#OK:}" >> "$HIST" ;;
        esac
    done
    # Pruning: nur die letzten 24 h behalten (max ~2880 Zeilen)
    CUT=$(( NOW - HIST_WINDOW ))
    if [ -f "$HIST" ]; then
        awk -F';' -v c="$CUT" '$1 >= c' "$HIST" > "$HIST.tmp" && mv "$HIST.tmp" "$HIST"
        chmod 644 "$HIST"
    fi
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

    # 2b) 24h-Historie sampeln (alle 5 min, siehe sample_history)
    sample_history

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

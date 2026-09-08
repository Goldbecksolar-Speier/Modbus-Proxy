#!/bin/sh
# =====================================================================
# EMS Watchdog fuer RUTX11 (optimiert)
#  * ueberwacht Proxy-Prozess, Tesvolt-EMS-Link, BLUESUN-PCS-Link
#  * Start/Stop-Steuerung ueber /etc/tesvolt_proxy_enabled (Setup-UI):
#    0 = Proxy stoppen und gestoppt lassen, sonst = laufen lassen.
#    (CGIs laufen als User uhttpd und duerfen den root-Proxy nicht
#    killen - deshalb setzt der Watchdog (root) den Wunsch um.)
#  * Failsafe: nach 3 BLUESUN-Fehlern -> passthrough + BLUESUN Standby
#    (UDAN-EMS Steuerblock 0x1501=3 / 0x1502=0; Herstellerfreigabe
#    2026-09-04 - das UDAN-EMS hat KEINEN eigenen Watchdog!)
#  * Geraeteslots (Profil-Loader): periodischer read-only Poll;
#    Intervall konfigurierbar ueber /etc/tesvolt_dev_poll_interval
#    (Sekunden, Default 60, Min 10, Max 3600) - wird bei JEDEM Tick
#    frisch gelesen, Aenderung wirkt ohne Neustart. Wichtig, wenn
#    mehrere Master (Cloud, EMS) dieselben Geraete abfragen: laengeres
#    Intervall = weniger Kollisionen (z.B. Kaco NX3, Solis-Cloud).
#  * Sniffer (sniffer.html): startet auf Marker-Anforderung ein
#    passives tcpdump-Capture (Port 502) - CGIs laufen als uhttpd
#    und duerfen kein tcpdump starten, deshalb macht es der Watchdog.
#  * Port-Mirroring (sniffer.html): setzt auf Marker-Anforderung die
#    swconfig-Mirror-Register (CGIs duerfen kein swconfig) und
#    schreibt den Port-/Mirror-Status alle 10 s nach /tmp fuer die UI.
#    NICHT reboot-fest (gewollt, Regel 23).
#  * repariert fehlende Konfigdateien
#  * einfache Logrotation (max. 500 kB)
#  * kill per PID statt killall (sauberer auf BusyBox)
#  * KEINE Fallback-IPs: ohne /etc/tesvolt_ip_t/_b werden die
#    entsprechenden Checks uebersprungen (Proxy ist dann im Schutzmodus)
#  * Modbus-Zugriffe via mb_cli.lua (luasocket) - modbus_cli existiert
#    auf RUTOS NICHT!
#  * BLUESUN Unit-ID aus /etc/tesvolt_unit_b (Default 10 lt. Hersteller)
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

bs_unit() {
    U=$(cat /etc/tesvolt_unit_b 2>/dev/null)
    [ -z "$U" ] && U=10
    echo "$U"
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
    BS_UNIT=$(bs_unit)
    logmsg "FAILSAFE: $1 -> passthrough + BLUESUN Standby (0x1501=3, 0x1502=0)"
    echo "passthrough" > /etc/tesvolt_proxy_mode
    # UDAN-EMS Steuerblock (Herstellerfreigabe 2026-09-04, Variante A):
    # 0x1501 (5377) SystemState  = 3 (Standby)
    # 0x1502 (5378) ExpectedPower = 0 (0.1 kW-Skala)
    # Herstellervorgabe: min. 200 ms Abstand zwischen Requests -> sleep 1
    lua "$MB" write "$BLUESUN_IP" 502 "$BS_UNIT" 5377 3 >/dev/null 2>&1
    sleep 1
    lua "$MB" write "$BLUESUN_IP" 502 "$BS_UNIT" 5378 0 >/dev/null 2>&1
}


# ---------------------------------------------------------------------
# Geraeteslots (Profil-Loader): periodischer read-only Poll als root.
# Muss im Watchdog laufen: CGIs laufen als uhttpd und duerfen wegen
# Sticky-Bit in /tmp keine root-eigenen Statusdateien ersetzen.
# Laeuft AUCH bei gestopptem Proxy (Standorte ohne Steuerung, Phase 1).
# Intervall aus /etc/tesvolt_dev_poll_interval (Setup ueber devices.html)
# - bei jedem Tick frisch gelesen, geclampt auf 10..3600 s, Default 60.
# ---------------------------------------------------------------------
DEV_LAST_POLL=0

dev_poll_interval() {
    I=$(cat /etc/tesvolt_dev_poll_interval 2>/dev/null | tr -cd '0-9')
    [ -z "$I" ] && I=60
    [ "$I" -lt 10 ] && I=10
    [ "$I" -gt 3600 ] && I=3600
    echo "$I"
}

device_poll_tick() {
    # Konfigaenderung (set_dev.cgi): Scan-Cache + Status verwerfen
    for n in 1 2 3 4; do
        if [ -f "/tmp/emsproxy_dev${n}_cfgchange" ]; then
            rm -f "/tmp/emsproxy_dev${n}_cfgchange" \
                  "/tmp/emsproxy_dev${n}_scan" \
                  "/tmp/emsproxy_dev${n}_status"
            logmsg "Geraeteslot $n: Konfig geaendert - Scan-Cache/Status verworfen"
        fi
    done
    NOW=$(date +%s)
    FORCE=0
    [ -f /tmp/emsproxy_poll_req ] && FORCE=1
    DPI=$(dev_poll_interval)
    if [ "$FORCE" = "0" ] && [ $((NOW - DEV_LAST_POLL)) -lt "$DPI" ]; then
        return
    fi
    ANY=0
    for n in 1 2 3 4; do
        [ -s "/etc/tesvolt_dev${n}_profile" ] && ANY=1
    done
    if [ "$ANY" = "1" ] && [ -f /usr/local/bin/device_poll.lua ]; then
        [ "$FORCE" = "1" ] && logmsg "Geraeteslot-Poll per UI angefordert"
        lua /usr/local/bin/device_poll.lua >/dev/null 2>&1
    fi
    rm -f /tmp/emsproxy_poll_req
    DEV_LAST_POLL=$NOW
}

# ---------------------------------------------------------------------
# Sniffer (sniffer.html): REIN PASSIVES tcpdump-Capture auf Port 502.
# uhttpd->root-Kanal (Regel 18): sniff_ctl.cgi legt Marker an,
# der Watchdog (root) fuehrt aus:
#   /tmp/emsproxy_sniff_req   = Capture starten (Inhalt: Dauer in s)
#   /tmp/emsproxy_sniff_stop  = laufendes Capture vorzeitig beenden
#   /tmp/emsproxy_sniff_state = RUNNING:<start>:<dauer> | DONE:<ende> | ERROR:...
#   /tmp/emsproxy_sniff.pcap  = Rohdaten (RAM, max. 2000 Pakete)
#   /tmp/emsproxy_sniff.txt   = geparste Zeilen (sniff_parse.lua)
# Capture laeuft als Hintergrund-Subshell - der 5-s-Tick blockiert nicht.
# ---------------------------------------------------------------------
sniff_tick() {
    [ -f /tmp/emsproxy_sniff_req ] || return
    DUR=$(cat /tmp/emsproxy_sniff_req 2>/dev/null | tr -cd '0-9')
    rm -f /tmp/emsproxy_sniff_req
    [ -z "$DUR" ] && DUR=60
    [ "$DUR" -lt 10 ] && DUR=10
    [ "$DUR" -gt 300 ] && DUR=300
    if [ -f /tmp/emsproxy_sniff_state ] && grep -q '^RUNNING' /tmp/emsproxy_sniff_state 2>/dev/null; then
        logmsg "Sniffer: Anforderung ignoriert - Capture laeuft bereits"
        return
    fi
    if ! command -v tcpdump >/dev/null 2>&1; then
        echo "ERROR:tcpdump nicht installiert - auf dem Router: opkg update; opkg install tcpdump" > /tmp/emsproxy_sniff_state
        chmod 644 /tmp/emsproxy_sniff_state
        logmsg "Sniffer: tcpdump fehlt (opkg install tcpdump)"
        return
    fi
    echo "RUNNING:$(date +%s):$DUR" > /tmp/emsproxy_sniff_state
    chmod 644 /tmp/emsproxy_sniff_state
    logmsg "Sniffer: Capture gestartet (Port 502, ${DUR}s, br-lan)"
    (
        rm -f /tmp/emsproxy_sniff.pcap /tmp/emsproxy_sniff_stop
        tcpdump -i br-lan -nn -s 128 -c 2000 -w /tmp/emsproxy_sniff.pcap port 502 2>/tmp/emsproxy_sniff_err &
        TPID=$!
        SLEPT=0
        while [ "$SLEPT" -lt "$DUR" ]; do
            sleep 2
            SLEPT=$((SLEPT + 2))
            [ -f /tmp/emsproxy_sniff_stop ] && break
            kill -0 "$TPID" 2>/dev/null || break   # -c 2000 erreicht
        done
        rm -f /tmp/emsproxy_sniff_stop
        kill "$TPID" 2>/dev/null
        sleep 1
        if [ -s /tmp/emsproxy_sniff.pcap ]; then
            lua /usr/local/bin/sniff_parse.lua /tmp/emsproxy_sniff.pcap > /tmp/emsproxy_sniff.txt 2>>/tmp/emsproxy_sniff_err
        else
            echo "#COUNT=0" > /tmp/emsproxy_sniff.txt
        fi
        chmod 644 /tmp/emsproxy_sniff.txt 2>/dev/null
        echo "DONE:$(date +%s)" > /tmp/emsproxy_sniff_state
        chmod 644 /tmp/emsproxy_sniff_state
    ) &
}

# ---------------------------------------------------------------------
# Port-Mirroring (sniffer.html): uhttpd->root-Kanal (Regel 18).
# mirror_ctl.cgi legt /tmp/emsproxy_mirror_req an, der Watchdog setzt
# die swconfig-Register (Monitor-Port fest = 0 = CPU) und schreibt den
# Port-/Mirror-Status alle 10 s nach /tmp/emsproxy_swports:
#   ts=<unix>  mirror_rx=0/1  mirror_tx=0/1  mirror_src=N  mirror_mon=N
#   port=N:up|down:<speed>   (je Switch-Port eine Zeile)
# Die Einstellung ist NICHT reboot-fest (gewollt, Regel 23) und kostet
# CPU/Durchsatz - nach der Analyse wieder abschalten!
# ---------------------------------------------------------------------
MIRROR_LAST=0

mirror_apply() {
    # $1 = rx (0/1), $2 = tx (0/1), $3 = Quellport (leer bei off)
    swconfig dev switch0 set enable_mirror_rx "$1" 2>>"$LOG"
    swconfig dev switch0 set enable_mirror_tx "$2" 2>>"$LOG"
    if [ -n "$3" ]; then
        swconfig dev switch0 set mirror_monitor_port 0 2>>"$LOG"
        swconfig dev switch0 set mirror_source_port "$3" 2>>"$LOG"
    fi
    swconfig dev switch0 set apply 1 2>>"$LOG"
}

mirror_tick() {
    command -v swconfig >/dev/null 2>&1 || return
    # 1) Anforderung der UI umsetzen (Marker von mirror_ctl.cgi)
    if [ -f /tmp/emsproxy_mirror_req ]; then
        REQ=$(cat /tmp/emsproxy_mirror_req 2>/dev/null | tr -cd 'a-z0-9:=')
        rm -f /tmp/emsproxy_mirror_req
        case "$REQ" in
            on:*)
                RX=$(echo "$REQ" | sed -n 's/.*rx=\([01]\).*/\1/p')
                TX=$(echo "$REQ" | sed -n 's/.*tx=\([01]\).*/\1/p')
                SRC=$(echo "$REQ" | sed -n 's/.*src=\([1-9]\).*/\1/p')
                [ -z "$RX" ] && RX=1
                [ -z "$TX" ] && TX=1
                if [ -n "$SRC" ]; then
                    mirror_apply "$RX" "$TX" "$SRC"
                    logmsg "Mirroring EIN: Port $SRC -> CPU (rx=$RX tx=$TX) - NICHT reboot-fest, nach Analyse abschalten!"
                else
                    logmsg "Mirroring: Anforderung ohne gueltigen Quellport ignoriert ($REQ)"
                fi
                ;;
            off)
                mirror_apply 0 0 ""
                logmsg "Mirroring AUS"
                ;;
        esac
        MIRROR_LAST=0   # Status sofort aktualisieren
    fi
    # 2) Port-/Mirror-Status alle 10 s fuer die UI schreiben
    NOW=$(date +%s)
    [ $((NOW - MIRROR_LAST)) -lt 10 ] && return
    MIRROR_LAST=$NOW
    {
        echo "ts=$NOW"
        MRX=$(swconfig dev switch0 get enable_mirror_rx 2>/dev/null | tr -cd '0-9')
        MTX=$(swconfig dev switch0 get enable_mirror_tx 2>/dev/null | tr -cd '0-9')
        MSRC=$(swconfig dev switch0 get mirror_source_port 2>/dev/null | tr -cd '0-9')
        MMON=$(swconfig dev switch0 get mirror_monitor_port 2>/dev/null | tr -cd '0-9')
        echo "mirror_rx=${MRX:-0}"
        echo "mirror_tx=${MTX:-0}"
        echo "mirror_src=$MSRC"
        echo "mirror_mon=$MMON"
        swconfig dev switch0 show 2>/dev/null | while read -r LINE; do
            case "$LINE" in
                *port:*link:*)
                    P=$(echo "$LINE" | sed -n 's/.*port:\([0-9]*\) .*/\1/p')
                    ST=down
                    echo "$LINE" | grep -q 'link:up' && ST=up
                    SPD=$(echo "$LINE" | sed -n 's/.*speed:\([0-9]*\).*/\1/p')
                    [ -n "$P" ] && echo "port=$P:$ST:$SPD"
                    ;;
            esac
        done
    } > /tmp/emsproxy_swports.tmp 2>/dev/null
    mv /tmp/emsproxy_swports.tmp /tmp/emsproxy_swports 2>/dev/null
    chmod 644 /tmp/emsproxy_swports 2>/dev/null
}

logmsg "Watchdog gestartet"

while true; do
    rotate_log

    # 0a) Geraeteslots pollen - VOR dem enabled-Check, damit der Poll
    #     auch bei gestopptem Proxy laeuft (z.B. Standort Hebauer)
    device_poll_tick

    # 0b) Sniffer-Anforderung pruefen (laeuft ebenfalls unabhaengig
    #     vom Proxy-Zustand - rein passives Mitlesen)
    sniff_tick

    # 0c) Port-Mirroring: UI-Anforderung umsetzen + Portstatus schreiben
    mirror_tick

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

    # 3) BLUESUN PCS-Link: System-SOC (0x1140 = 4416, FC04) - nur im
    #    Split-Modus und NICHT im Simulationsmodus (keine echten Geraete!)
    MODE=$(cat /etc/tesvolt_proxy_mode 2>/dev/null)
    SIM=$(cat /etc/tesvolt_sim 2>/dev/null)
    if [ "$MODE" = "split" ] && [ -n "$BLUESUN_IP" ] && [ "$SIM" != "1" ]; then
        BS_UNIT=$(bs_unit)
        SOC_B=$(lua "$MB" read "$BLUESUN_IP" 502 "$BS_UNIT" 4 4416 2>/dev/null)
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

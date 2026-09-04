#!/bin/sh
# =====================================================================
# bluesun_test_guard.sh - Failsafe fuer die Geraete-Testseite (test.html)
#
# Das UDAN-EMS hat KEINEN eigenen Watchdog: ein gesetzter Sollwert
# bleibt bei Kommunikationsverlust dauerhaft aktiv. Dieser Guard
# schreibt deshalb automatisch Standby (0x1501=3) + 0 kW (0x1502=0),
# wenn die Testseite laenger als TIMEOUT Sekunden keinen Heartbeat
# (/tmp/bluesun_test_hb) mehr geschrieben hat.
#
# Gestartet von test_bluesun.cgi bei der ersten Schreibaktion.
# Beendet sich selbst, sobald /tmp/bluesun_test_active fehlt
# (Standby-/NOT-AUS-Button) oder der Failsafe ausgeloest wurde.
# =====================================================================
HB=/tmp/bluesun_test_hb
ACTIVE=/tmp/bluesun_test_active
TIMEOUT=60
LOG=/var/log/ems_proxy.log

IP=$(cat /etc/tesvolt_ip_b 2>/dev/null)
UNIT=$(cat /etc/tesvolt_unit_b 2>/dev/null)
[ -n "$UNIT" ] || UNIT=10

[ -n "$IP" ] || exit 0

while [ -f "$ACTIVE" ]; do
    now=$(date +%s)
    hb=$(cat "$HB" 2>/dev/null)
    [ -n "$hb" ] || hb=0
    if [ $((now - hb)) -gt $TIMEOUT ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') TESTGUARD: Heartbeat-Timeout (> ${TIMEOUT}s) - schreibe Standby+0kW" >> "$LOG"
        /usr/bin/lua /usr/local/bin/mb_cli.lua write "$IP" 502 "$UNIT" 5377 3 >> "$LOG" 2>&1
        sleep 1
        /usr/bin/lua /usr/local/bin/mb_cli.lua write "$IP" 502 "$UNIT" 5378 0 >> "$LOG" 2>&1
        rm -f "$ACTIVE"
        exit 0
    fi
    sleep 5
done
exit 0

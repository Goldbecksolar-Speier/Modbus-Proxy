#!/bin/sh
# =====================================================================
# solis_test_guard.sh - Failsafe fuer die Solis-Batterietest-Sektion
# auf test.html (analog zu bluesun_test_guard.sh)
#
# Das Solis-Geraet hat zwar einen eigenen Timeout (Register 43282,
# Default 5 Minuten) - dieser Guard ist die engere, schnellere
# Absicherung: setzt die Fernsteuerung zurueck, wenn die Testseite
# laenger als TIMEOUT Sekunden keinen Heartbeat mehr geschrieben hat.
#
# Gestartet von test_solis.cgi bei der ersten Schreibaktion.
# Beendet sich selbst, sobald die Aktiv-Markerdatei fehlt (Standby-/
# NOT-AUS-Button) oder der Failsafe ausgeloest wurde.
# =====================================================================
HB=/tmp/solis_test_hb
ACTIVE=/tmp/solis_test_active
TIMEOUT=60
LOG=/var/log/ems_proxy.log

IP=$(cat /etc/tesvolt_ip_ems_s 2>/dev/null)
UNIT=$(cat /etc/tesvolt_dev1_unit 2>/dev/null)
[ -n "$UNIT" ] || UNIT=1

[ -n "$IP" ] || exit 0

while [ -f "$ACTIVE" ]; do
    now=$(date +%s)
    hb=$(cat "$HB" 2>/dev/null)
    [ -n "$hb" ] || hb=0
    if [ $((now - hb)) -gt $TIMEOUT ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') SOLISTESTGUARD: Heartbeat-Timeout (> ${TIMEOUT}s) - deaktiviere Fernsteuerung (Reg 44280=0)" >> "$LOG"
        /usr/bin/lua /usr/local/bin/mb_cli.lua write "$IP" 502 "$UNIT" 44280 0 >> "$LOG" 2>&1
        rm -f "$ACTIVE"
        exit 0
    fi
    sleep 5
done
exit 0

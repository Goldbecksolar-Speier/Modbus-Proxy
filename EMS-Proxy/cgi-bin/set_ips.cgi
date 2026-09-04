#!/bin/sh
# Speichert Geraete-IPs und Aktivierungsflags (Setup-Seite)
#   /cgi-bin/set_ips.cgi?ip_t=..&ip_b=..&en_t=0|1&en_b=0|1&en_sma=0|1
# en_* = Geraet per Modbus/TCP aktiv (0 = z.B. CAN-Bus-Anbindung, nicht ansprechen)
# WICHTIG: laeuft als User uhttpd - Zieldateien muessen uhttpd gehoeren
# (macht github_update.sh). Schreibfehler werden als FEHLER gemeldet.
echo "Content-Type: text/plain"
echo ""

IP_T=$(echo "$QUERY_STRING" | sed -n 's/.*ip_t=\([0-9.]*\).*/\1/p')
IP_B=$(echo "$QUERY_STRING" | sed -n 's/.*ip_b=\([0-9.]*\).*/\1/p')
EN_T=$(echo "$QUERY_STRING" | sed -n 's/.*en_t=\([01]\).*/\1/p')
EN_B=$(echo "$QUERY_STRING" | sed -n 's/.*en_b=\([01]\).*/\1/p')
EN_SMA=$(echo "$QUERY_STRING" | sed -n 's/.*en_sma=\([01]\).*/\1/p')

ERR=""

write_check() {
    # $1=Datei $2=Wert
    echo "$2" > "$1" 2>/dev/null
    if [ "$(cat "$1" 2>/dev/null)" != "$2" ]; then
        ERR="$ERR $1(nicht schreibbar - github_update.sh erneut ausfuehren!)"
    fi
}

[ -n "$IP_T" ]   && write_check /etc/tesvolt_ip_t   "$IP_T"
[ -n "$IP_B" ]   && write_check /etc/tesvolt_ip_b   "$IP_B"
[ -n "$EN_T" ]   && write_check /etc/tesvolt_en_t   "$EN_T"
[ -n "$EN_B" ]   && write_check /etc/tesvolt_en_b   "$EN_B"
[ -n "$EN_SMA" ] && write_check /etc/tesvolt_en_sma "$EN_SMA"

if [ -n "$ERR" ]; then
    echo "FEHLER:$ERR"
else
    echo "OK"
fi

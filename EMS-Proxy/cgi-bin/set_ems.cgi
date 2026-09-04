#!/bin/sh
# Speichert EMS-Quelle und SMA-IPs (Setup-Seite)
#   /cgi-bin/set_ems.cgi?source=tesvolt|datamanager&ip_dm=..&ip_sma=..&unit_dm=..
# WICHTIG: laeuft als User uhttpd (uid 575). Die Zieldateien muessen
# existieren und uhttpd gehoeren (macht github_update.sh). Schlaegt das
# Schreiben fehl, wird FEHLER gemeldet - nicht stillschweigend OK!
echo "Content-Type: text/plain"
echo ""

SRC=$(echo "$QUERY_STRING" | sed -n 's/.*source=\([a-z]*\).*/\1/p')
IP_DM=$(echo "$QUERY_STRING" | sed -n 's/.*ip_dm=\([0-9.]*\).*/\1/p')
IP_SMA=$(echo "$QUERY_STRING" | sed -n 's/.*ip_sma=\([0-9.]*\).*/\1/p')
UNIT_DM=$(echo "$QUERY_STRING" | sed -n 's/.*unit_dm=\([0-9]*\).*/\1/p')

ERR=""

# schreibt $2 nach $1 und verifiziert den Inhalt (Rueckgabe: setzt ERR)
write_check() {
    # $1=Datei $2=Wert
    echo "$2" > "$1" 2>/dev/null
    if [ "$(cat "$1" 2>/dev/null)" != "$2" ]; then
        ERR="$ERR $1(nicht schreibbar - github_update.sh erneut ausfuehren!)"
    fi
}

case "$SRC" in
    tesvolt|datamanager) write_check /etc/tesvolt_ems_source "$SRC" ;;
    "") ;;
    *) ERR="$ERR source-ungueltig($SRC)" ;;
esac
[ -n "$IP_DM" ]   && write_check /etc/tesvolt_ip_dm   "$IP_DM"
[ -n "$IP_SMA" ]  && write_check /etc/tesvolt_ip_sma  "$IP_SMA"
[ -n "$UNIT_DM" ] && write_check /etc/tesvolt_unit_dm "$UNIT_DM"

if [ -n "$ERR" ]; then
    echo "FEHLER:$ERR"
else
    echo "OK source=$(cat /etc/tesvolt_ems_source 2>/dev/null)"
fi

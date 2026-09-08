#!/bin/sh
# =====================================================================
# set_devpoll.cgi - Poll-Intervall der Geraeteslots lesen/setzen
#   ohne Parameter        -> aktueller Wert (INTERVAL=n)
#   ?interval=10..3600    -> Wert setzen (Sekunden)
#
# Der Watchdog liest /etc/tesvolt_dev_poll_interval bei JEDEM Tick
# frisch - die Aenderung wirkt ohne Neustart (max. 5 s Verzoegerung).
# Regel 15: geschriebenen Inhalt verifizieren, nie blind OK melden.
# =====================================================================

echo "Content-Type: text/plain"
echo ""

F="/etc/tesvolt_dev_poll_interval"

VAL=$(echo "$QUERY_STRING" | sed -n 's/.*interval=\([0-9]*\).*/\1/p' | tr -cd '0-9')

# Lesen (kein Parameter)
if [ -z "$VAL" ]; then
    CUR=$(cat "$F" 2>/dev/null | tr -cd '0-9')
    [ -z "$CUR" ] && CUR=60
    echo "INTERVAL=$CUR"
    exit 0
fi

# Setzen mit Bereichspruefung
if [ "$VAL" -lt 10 ] 2>/dev/null || [ "$VAL" -gt 3600 ] 2>/dev/null; then
    echo "FEHLER:interval muss 10..3600 Sekunden sein (war: $VAL)"
    exit 0
fi

echo "$VAL" > "$F" 2>/dev/null

# Verifikation (Regel 15): zurueckgelesener Inhalt muss stimmen
CHECK=$(cat "$F" 2>/dev/null | tr -cd '0-9')
if [ "$CHECK" = "$VAL" ]; then
    echo "OK:INTERVAL=$VAL"
else
    echo "FEHLER:Schreiben fehlgeschlagen (Datei enthaelt '$CHECK') - Rechte pruefen (github_update.sh 2x ausfuehren)"
fi

#!/bin/sh
# =====================================================================
# sniff_ctl.cgi - Steuerung des passiven Modbus-Sniffers (sniffer.html)
#
# Das CGI laeuft als User uhttpd und darf KEIN tcpdump starten.
# Es signalisiert nur per Marker-Datei (Regel 18), der Watchdog (root)
# fuehrt das Capture aus und legt das Ergebnis nach /tmp.
#
#   ?cmd=start&dur=60  Capture anfordern (Dauer 10..300 s)
#   ?cmd=stop          laufendes Capture vorzeitig beenden
#   ?cmd=status        RUNNING:<start>:<dauer> | DONE:<ende> | ERROR:... | IDLE
#   ?cmd=result        geparste Zeilen (sniff_parse.lua-Ausgabe)
# =====================================================================

echo "Content-Type: text/plain; charset=utf-8"
echo ""

CMD=$(echo "$QUERY_STRING" | sed -n 's/.*cmd=\([a-z]*\).*/\1/p')
DUR=$(echo "$QUERY_STRING" | sed -n 's/.*dur=\([0-9]*\).*/\1/p')

case "$CMD" in
    start)
        [ -z "$DUR" ] && DUR=60
        [ "$DUR" -lt 10 ] && DUR=10
        [ "$DUR" -gt 300 ] && DUR=300
        # Doppelstart abfangen (Watchdog prueft zusaetzlich)
        if [ -f /tmp/emsproxy_sniff_state ] && grep -q '^RUNNING' /tmp/emsproxy_sniff_state 2>/dev/null; then
            echo "ERR:Capture laeuft bereits"
            exit 0
        fi
        if echo "$DUR" > /tmp/emsproxy_sniff_req 2>/dev/null; then
            echo "OK:Capture angefordert (${DUR}s) - Watchdog startet binnen 5 s"
        else
            echo "ERR:Marker-Datei nicht schreibbar"
        fi
        ;;
    stop)
        touch /tmp/emsproxy_sniff_stop 2>/dev/null
        echo "OK:Stop angefordert"
        ;;
    status)
        if [ -f /tmp/emsproxy_sniff_state ]; then
            cat /tmp/emsproxy_sniff_state
        else
            echo "IDLE"
        fi
        ;;
    result)
        if [ -f /tmp/emsproxy_sniff.txt ]; then
            cat /tmp/emsproxy_sniff.txt
        else
            echo "#COUNT=0"
        fi
        ;;
    *)
        echo "ERR:unbekanntes cmd (start|stop|status|result)"
        ;;
esac

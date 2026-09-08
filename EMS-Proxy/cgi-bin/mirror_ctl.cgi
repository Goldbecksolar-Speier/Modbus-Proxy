#!/bin/sh
# =====================================================================
# mirror_ctl.cgi - Steuerung des Port-Mirrorings (sniffer.html)
#
# Das CGI laeuft als User uhttpd und darf KEIN swconfig ausfuehren.
# Es signalisiert nur per Marker-Datei (Regel 18), der Watchdog (root)
# setzt die Switch-Register und schreibt den Status nach /tmp.
#
#   ?cmd=status               Portliste + Mirror-Zustand
#                             (Inhalt von /tmp/emsproxy_swports)
#   ?cmd=on&src=N&rx=1&tx=1   Mirroring anfordern (Quellport N=1..5,
#                             Kopie an CPU-Port 0)
#   ?cmd=off                  Mirroring abschalten
#
# Die Einstellung ist NICHT reboot-fest (gewollt, Regel 23).
# =====================================================================

echo "Content-Type: text/plain; charset=utf-8"
echo ""

CMD=$(echo "$QUERY_STRING" | sed -n 's/.*cmd=\([a-z]*\).*/\1/p')

case "$CMD" in
    status)
        if [ -f /tmp/emsproxy_swports ]; then
            cat /tmp/emsproxy_swports
        else
            echo "ERR:keine Switch-Daten - Watchdog laeuft nicht oder swconfig fehlt"
        fi
        ;;
    on)
        SRC=$(echo "$QUERY_STRING" | sed -n 's/.*src=\([1-9]\).*/\1/p')
        RX=$(echo "$QUERY_STRING" | sed -n 's/.*rx=\([01]\).*/\1/p')
        TX=$(echo "$QUERY_STRING" | sed -n 's/.*tx=\([01]\).*/\1/p')
        [ -z "$RX" ] && RX=1
        [ -z "$TX" ] && TX=1
        if [ -z "$SRC" ]; then
            echo "ERR:kein gueltiger Quellport (src=1..5)"
            exit 0
        fi
        if [ "$RX" = "0" ] && [ "$TX" = "0" ]; then
            echo "ERR:RX und TX beide aus - mindestens einen Haken setzen"
            exit 0
        fi
        if echo "on:rx=$RX:tx=$TX:src=$SRC" > /tmp/emsproxy_mirror_req 2>/dev/null; then
            echo "OK:Mirroring angefordert (Port $SRC, rx=$RX tx=$TX) - Watchdog setzt binnen 5 s"
        else
            echo "ERR:Marker-Datei nicht schreibbar"
        fi
        ;;
    off)
        if echo "off" > /tmp/emsproxy_mirror_req 2>/dev/null; then
            echo "OK:Abschaltung angefordert - Watchdog setzt binnen 5 s"
        else
            echo "ERR:Marker-Datei nicht schreibbar"
        fi
        ;;
    *)
        echo "ERR:unbekanntes cmd (status|on|off)"
        ;;
esac

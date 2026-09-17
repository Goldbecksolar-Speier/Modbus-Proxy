#!/bin/sh
# =====================================================================
# set_griddraw.cgi - Solis Netzbezug-Begrenzung (Remote Dispatch Mode)
#   ?en=0|1&kw=<zahl>
# Schreibt nur Config-Dateien; das eigentliche Schreiben ins Geraet
# (Register 44100-44103) macht der Watchdog (root) im naechsten Tick -
# CGIs laufen als uhttpd und sollen keine Live-Geraeteschreibzugriffe
# ausloesen (Regel: uhttpd->root-Kanal ueber /etc + Marker).
# =====================================================================
echo "Content-Type: text/plain"
echo ""
EN=$(echo "$QUERY_STRING" | sed -n 's/.*en=\([01]\).*/\1/p')
KW=$(echo "$QUERY_STRING" | sed -n 's/.*kw=\([0-9.]*\).*/\1/p')
[ -n "$EN" ] && echo "$EN" > /etc/tesvolt_griddraw_en
[ -n "$KW" ] && echo "$KW" > /etc/tesvolt_griddraw_kw
touch /tmp/emsproxy_griddraw_cfgchange 2>/dev/null
echo "OK"

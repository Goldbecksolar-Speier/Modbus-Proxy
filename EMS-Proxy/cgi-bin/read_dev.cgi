#!/bin/sh
# =====================================================================
# read_dev.cgi - Geraeteslots (Profil-Loader) lesen
#   ?slot=N        -> Inhalt von /tmp/emsproxy_devN_status ausgeben
#   ?slot=N&cfg=1  -> Slot-Konfiguration ausgeben (key=value)
#   ?poll=1        -> Poll-Anforderung setzen (/tmp/emsproxy_poll_req)
#
# WICHTIG: CGIs laufen als User uhttpd. Der eigentliche Poll laeuft
# im Watchdog (root) - wegen Sticky-Bit in /tmp darf uhttpd die von
# root geschriebenen Statusdateien nicht ersetzen. Das CGI liest nur.
# =====================================================================
echo "Content-Type: text/plain"
echo ""

case "$QUERY_STRING" in
  *poll=1*)
    if touch /tmp/emsproxy_poll_req 2>/dev/null; then
      echo "REQUESTED"
    else
      echo "FEHLER:poll-Anforderung nicht schreibbar"
    fi
    exit 0 ;;
esac

SLOT=$(echo "$QUERY_STRING" | sed -n 's/.*slot=\([1-4]\).*/\1/p')
[ -n "$SLOT" ] || { echo "FEHLER:slot=1..4 fehlt"; exit 0; }

case "$QUERY_STRING" in
  *cfg=1*)
    for k in profile ip port unit en; do
      echo "$k=$(cat /etc/tesvolt_dev${SLOT}_${k} 2>/dev/null)"
    done
    exit 0 ;;
esac

if [ -f "/tmp/emsproxy_dev${SLOT}_status" ]; then
  cat "/tmp/emsproxy_dev${SLOT}_status"
else
  echo "NOSTATUS"
fi

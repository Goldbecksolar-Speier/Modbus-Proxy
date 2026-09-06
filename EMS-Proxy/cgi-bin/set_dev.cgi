#!/bin/sh
# =====================================================================
# set_dev.cgi - Geraeteslot (Profil-Loader) speichern
#   ?slot=N&profile=..&ip=..&port=..&unit=..&en=0|1
#
# Schreibt /etc/tesvolt_devN_* (gehoeren dem uhttpd-User, Installer).
# Nach dem Speichern wird der Scan-Cache-Verwurf und ein Sofort-Poll
# beim Watchdog angefordert (cfgchange- und poll_req-Marker in /tmp).
# =====================================================================
echo "Content-Type: text/plain"
echo ""

Q="$QUERY_STRING"
SLOT=$(echo "$Q" | sed -n 's/.*slot=\([1-4]\).*/\1/p')
[ -n "$SLOT" ] || { echo "FEHLER:slot=1..4 fehlt"; exit 0; }

getp() { echo "$Q" | tr '&' '\n' | sed -n "s/^$1=//p" | head -n 1; }

# Eingaben strikt filtern (Profilname-Whitelist wie profile_loader.lua)
PROFILE=$(getp profile | tr -cd 'A-Za-z0-9_-')
IP=$(getp ip | tr -cd '0-9.')
PORT=$(getp port | tr -cd '0-9')
UNIT=$(getp unit | tr -cd '0-9')
EN=$(getp en | tr -cd '01' | cut -c1)
[ -n "$EN" ] || EN=1

ERR=""
w() {
  f="/etc/tesvolt_dev${SLOT}_$1"
  if ! echo "$2" 2>/dev/null > "$f"; then ERR="$ERR $f"; fi
}
w profile "$PROFILE"
w ip "$IP"
w port "$PORT"
w unit "$UNIT"
w en "$EN"

if [ -n "$ERR" ]; then
  echo "FEHLER:nicht schreibbar:$ERR"
  exit 0
fi

# Watchdog (root) soll Scan-Cache verwerfen und sofort neu pollen
touch "/tmp/emsproxy_dev${SLOT}_cfgchange" 2>/dev/null
touch /tmp/emsproxy_poll_req 2>/dev/null
echo "OK slot=$SLOT profile=$PROFILE ip=$IP port=$PORT unit=$UNIT en=$EN"

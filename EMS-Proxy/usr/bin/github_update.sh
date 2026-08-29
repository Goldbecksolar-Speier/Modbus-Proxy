#!/bin/sh
# =====================================================================
# github_update.sh - Self-Update des EMS-Proxy direkt vom GitHub-Branch
# fuer Teltonika RUTX11 (RUTOS/BusyBox, kein git noetig)
#
# Aufruf:
#   github_update.sh [branch]      (Default: main)
#   z.B.: github_update.sh feature/optimierung
#
# Privates Repo: Token in /etc/github_token ablegen (chmod 600).
#   Das Token NIEMALS ins Repo committen!
#
# Verhalten:
#   * Download als Tarball nach /tmp (RAM, kein Flash-Verschleiss)
#   * Konfigdateien (/etc/tesvolt_*) werden NIE ueberschrieben,
#     nur angelegt falls sie fehlen (IPs/Kapazitaeten bleiben erhalten)
#   * Dienste werden nach dem Update neu gestartet
#   * Log nach /var/log/ems_proxy.log
# =====================================================================

OWNER="Goldbecksolar-Speier"
REPO="Modbus-Proxy"
BRANCH="${1:-main}"
TOKEN_FILE="/etc/github_token"
LOGFILE="/var/log/ems_proxy.log"
WORKDIR="/tmp/mp_update"
TARBALL="/tmp/mp_update.tar.gz"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') UPDATE: $1" | tee -a "$LOGFILE"
}

fail() {
    log "FEHLER: $1"
    rm -rf "$WORKDIR" "$TARBALL"
    exit 1
}

log "Starte Update von $OWNER/$REPO Branch '$BRANCH'"

# --- 1. Download -------------------------------------------------------
rm -rf "$WORKDIR" "$TARBALL"
mkdir -p "$WORKDIR"

if [ -f "$TOKEN_FILE" ]; then
    TOKEN=$(cat "$TOKEN_FILE")
    log "Token gefunden - nutze API-Tarball (privates Repo)"
    URL="https://api.github.com/repos/$OWNER/$REPO/tarball/$BRANCH"
    wget -q --header="Authorization: token $TOKEN" -O "$TARBALL" "$URL" \
        || curl -fsSL -H "Authorization: token $TOKEN" -o "$TARBALL" "$URL" \
        || fail "Download fehlgeschlagen (Token/Netz pruefen): $URL"
else
    URL="https://github.com/$OWNER/$REPO/archive/refs/heads/$BRANCH.tar.gz"
    wget -q -O "$TARBALL" "$URL" \
        || curl -fsSL -o "$TARBALL" "$URL" \
        || fail "Download fehlgeschlagen (Repo privat? Token nach $TOKEN_FILE legen): $URL"
fi

[ -s "$TARBALL" ] || fail "Tarball leer: $TARBALL"

# --- 2. Entpacken -------------------------------------------------------
tar -xzf "$TARBALL" -C "$WORKDIR" || fail "Entpacken fehlgeschlagen"

# Tarball-Wurzelordner ermitteln (Name variiert je nach Download-Weg)
SRC=$(find "$WORKDIR" -maxdepth 2 -type d -name "EMS-Proxy" | head -n 1)
[ -n "$SRC" ] || fail "EMS-Proxy-Ordner im Tarball nicht gefunden"
log "Quelle: $SRC"

# --- 3. Dateien installieren ---------------------------------------------
cp "$SRC/usr/bin/modbus_proxy.lua"  /usr/bin/ || fail "copy modbus_proxy.lua"
cp "$SRC/usr/bin/powersplit.lua"    /usr/bin/ || fail "copy powersplit.lua"
cp "$SRC/usr/bin/ems_watchdog.sh"   /usr/bin/ || fail "copy ems_watchdog.sh"
[ -f "$SRC/usr/bin/github_update.sh" ] && cp "$SRC/usr/bin/github_update.sh" /usr/bin/
cp "$SRC/etc/init.d/ems_watchdog"   /etc/init.d/ || fail "copy init.d/ems_watchdog"
cp "$SRC"/cgi-bin/*.cgi             /www/cgi-bin/ || fail "copy cgi-bin"
cp "$SRC"/www/*.html                /www/ || fail "copy www"

# Konfigdateien: NUR anlegen wenn nicht vorhanden (nie ueberschreiben!)
for f in "$SRC"/etc/tesvolt_*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    if [ ! -f "/etc/$base" ]; then
        cp "$f" "/etc/$base"
        log "Konfig angelegt: /etc/$base"
    fi
done

# --- 4. Rechte + Dienste --------------------------------------------------
chmod +x /usr/bin/modbus_proxy.lua /usr/bin/powersplit.lua \
         /usr/bin/ems_watchdog.sh /usr/bin/github_update.sh \
         /etc/init.d/ems_watchdog /www/cgi-bin/*.cgi 2>/dev/null

# luasocket sicherstellen
if ! opkg list-installed 2>/dev/null | grep -qi luasocket; then
    log "luasocket fehlt - installiere via opkg"
    opkg update >/dev/null 2>&1
    opkg install luasocket >/dev/null 2>&1 || log "WARNUNG: luasocket-Installation fehlgeschlagen"
fi

/etc/init.d/ems_watchdog enable  2>/dev/null
/etc/init.d/ems_watchdog restart 2>/dev/null || /usr/bin/ems_watchdog.sh &

# --- 5. Aufraeumen ----------------------------------------------------------
rm -rf "$WORKDIR" "$TARBALL"
log "Update abgeschlossen (Branch '$BRANCH')"
echo "OK - Update auf Branch '$BRANCH' abgeschlossen. Log: $LOGFILE"

#!/bin/sh
# =====================================================================
# github_update.sh - Self-Update des EMS-Proxy direkt vom GitHub-Branch
# fuer Teltonika RUTX11 (RUTOS/BusyBox, kein git noetig)
#
# Aufruf:
#   /usr/local/bin/github_update.sh [branch]      (Default: main)
#   z.B.: /usr/local/bin/github_update.sh feature/optimierung
#
# WICHTIG - RUTOS-Dateisystem:
#   / ist squashfs (READ-ONLY). Beschreibbar sind nur /etc und /usr/local
#   (Overlay) sowie /tmp und /var (RAM). Deshalb:
#     Skripte  -> /usr/local/bin/
#     Web-UI   -> /usr/local/www/  (eigene uhttpd-Instanz, Port 8080)
#     Konfig   -> /etc/tesvolt_*
#
# WICHTIG - CGI-Rechte:
#   uhttpd fuehrt CGIs unter RUTOS als User 'uhttpd' (uid 575) aus,
#   NICHT als root! Die Konfigdateien /etc/tesvolt_* muessen daher
#   existieren und dem User uhttpd gehoeren (Truncate auf eigene Datei
#   braucht kein Schreibrecht auf /etc selbst).
#
# Privates Repo: Token in /etc/github_token ablegen (chmod 600).
#   Das Token NIEMALS ins Repo committen!
#
# Verhalten:
#   * curl bevorzugt (BusyBox-wget kann keine HTTP-Header!)
#   * Download als Tarball nach /tmp (RAM, kein Flash-Verschleiss)
#   * Konfigdateien (/etc/tesvolt_*) werden NIE ueberschrieben
#   * uhttpd-Instanz 'emsproxy' (Port 8080) wird bei Bedarf angelegt
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

BIN=/usr/local/bin
WEB=/usr/local/www

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') UPDATE: $1" | tee -a "$LOGFILE"
}

fail() {
    log "FEHLER: $1"
    rm -rf "$WORKDIR" "$TARBALL"
    exit 1
}

# Download-Funktion: curl bevorzugen, BusyBox-wget kann keine Header
fetch() {
    # $1=URL $2=Zieldatei [$3=Token]
    if command -v curl >/dev/null 2>&1; then
        if [ -n "$3" ]; then
            curl -fsSL -H "Authorization: token $3" -o "$2" "$1"
        else
            curl -fsSL -o "$2" "$1"
        fi
    else
        if [ -n "$3" ]; then
            wget -q --header="Authorization: token $3" -O "$2" "$1"
        else
            wget -q -O "$2" "$1"
        fi
    fi
}

log "Starte Update von $OWNER/$REPO Branch '$BRANCH'"

# --- 0. Schreibbarkeit pruefen ------------------------------------------
mkdir -p "$BIN" "$WEB/cgi-bin" 2>/dev/null
touch "$BIN/.wtest" 2>/dev/null || fail "$BIN nicht beschreibbar - df -h pruefen"
rm -f "$BIN/.wtest"

# --- 1. Download -----------------------------------------------------------
rm -rf "$WORKDIR" "$TARBALL"
mkdir -p "$WORKDIR"

if [ -f "$TOKEN_FILE" ]; then
    TOKEN=$(cat "$TOKEN_FILE")
    log "Token gefunden - nutze API-Tarball (privates Repo)"
    fetch "https://api.github.com/repos/$OWNER/$REPO/tarball/$BRANCH" "$TARBALL" "$TOKEN" \
        || fail "Download fehlgeschlagen (Token/Netz pruefen)"
else
    fetch "https://github.com/$OWNER/$REPO/archive/refs/heads/$BRANCH.tar.gz" "$TARBALL" "" \
        || fail "Download fehlgeschlagen (Repo privat? Token nach $TOKEN_FILE legen)"
fi

[ -s "$TARBALL" ] || fail "Tarball leer: $TARBALL"

# --- 2. Entpacken -----------------------------------------------------------
tar -xzf "$TARBALL" -C "$WORKDIR" || fail "Entpacken fehlgeschlagen"

SRC=$(find "$WORKDIR" -maxdepth 2 -type d -name "EMS-Proxy" | head -n 1)
[ -n "$SRC" ] || fail "EMS-Proxy-Ordner im Tarball nicht gefunden"
log "Quelle: $SRC"

# --- 3. Dateien installieren (nur beschreibbare Pfade!) -----------------------
cp "$SRC/usr/bin/modbus_proxy.lua"  "$BIN/" || fail "copy modbus_proxy.lua"
cp "$SRC/usr/bin/powersplit.lua"    "$BIN/" || fail "copy powersplit.lua"
cp "$SRC/usr/bin/ems_watchdog.sh"   "$BIN/" || fail "copy ems_watchdog.sh"
cp "$SRC/usr/bin/mb_cli.lua"        "$BIN/" || fail "copy mb_cli.lua"
[ -f "$SRC/usr/bin/github_update.sh" ] && cp "$SRC/usr/bin/github_update.sh" "$BIN/"
cp "$SRC/etc/init.d/ems_watchdog"   /etc/init.d/ || fail "copy init.d/ems_watchdog"
cp "$SRC"/cgi-bin/*.cgi             "$WEB/cgi-bin/" || fail "copy cgi-bin"
cp "$SRC"/www/*.html                "$WEB/" || fail "copy www"

# Konfigdateien: NUR anlegen wenn nicht vorhanden (nie ueberschreiben!)
for f in "$SRC"/etc/tesvolt_*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    if [ ! -f "/etc/$base" ]; then
        cp "$f" "/etc/$base"
        log "Konfig angelegt: /etc/$base"
    fi
done

# CGI-Schreibrechte: uhttpd-CGIs laufen als User 'uhttpd' (uid 575), NICHT root.
# Damit die Setup-UI speichern kann, muessen alle Konfigdateien existieren
# und dem uhttpd-User gehoeren (Fallback: world-writable).
for base in ip_t ip_b cap_t cap_b proxy_mode split_mode proxy_registers; do
    f="/etc/tesvolt_$base"
    [ -f "$f" ] || touch "$f"
    if chown uhttpd:uhttpd "$f" 2>/dev/null; then
        chmod 664 "$f"
    else
        chmod 666 "$f"
        log "WARNUNG: chown uhttpd fehlgeschlagen fuer $f - chmod 666 gesetzt"
    fi
done
log "Konfigdatei-Rechte fuer uhttpd-User gesetzt"

# --- 4. Rechte ---------------------------------------------------------------
chmod +x "$BIN"/modbus_proxy.lua "$BIN"/powersplit.lua "$BIN"/mb_cli.lua \
         "$BIN"/ems_watchdog.sh "$BIN"/github_update.sh \
         /etc/init.d/ems_watchdog "$WEB"/cgi-bin/*.cgi 2>/dev/null

# --- 5. uhttpd-Instanz fuer die Web-UI (Port 8080) ---------------------------
if ! uci -q get uhttpd.emsproxy >/dev/null 2>&1; then
    log "Lege uhttpd-Instanz 'emsproxy' an (Port 8080, Home $WEB)"
    uci set uhttpd.emsproxy=uhttpd
    uci add_list uhttpd.emsproxy.listen_http='0.0.0.0:8080'
    uci set uhttpd.emsproxy.home="$WEB"
    uci set uhttpd.emsproxy.cgi_prefix='/cgi-bin'
    uci commit uhttpd
    /etc/init.d/uhttpd restart
fi

# --- 6. luasocket sicherstellen -----------------------------------------------
if ! opkg list-installed 2>/dev/null | grep -qi luasocket; then
    log "luasocket fehlt - installiere via opkg"
    opkg update >/dev/null 2>&1
    opkg install luasocket >/dev/null 2>&1 || log "WARNUNG: luasocket-Installation fehlgeschlagen"
fi

# --- 7. Dienste ----------------------------------------------------------------
/etc/init.d/ems_watchdog enable  2>/dev/null
/etc/init.d/ems_watchdog restart 2>/dev/null || "$BIN/ems_watchdog.sh" &

# --- 8. Aufraeumen ---------------------------------------------------------------
rm -rf "$WORKDIR" "$TARBALL"
log "Update abgeschlossen (Branch '$BRANCH')"
echo "OK - Update abgeschlossen. Web-UI: http://<ROUTER-IP>:8080/setup.html  Log: $LOGFILE"

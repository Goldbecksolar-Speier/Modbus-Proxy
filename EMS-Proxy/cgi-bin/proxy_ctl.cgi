#!/bin/sh
# Start/Stop/Status des EMS-Proxy.
# Laeuft als User uhttpd -> darf den root-Proxy NICHT killen.
# Deshalb: Wunsch in /etc/tesvolt_proxy_enabled schreiben,
# der Watchdog (root) setzt ihn innerhalb von ~5 s um.
echo "Content-Type: text/plain"
echo ""
ACTION=$(echo "$QUERY_STRING" | sed -n 's/.*action=\([a-z]*\).*/\1/p')
case "$ACTION" in
    start)
        echo "1" > /etc/tesvolt_proxy_enabled 2>/dev/null && echo "OK:start" || echo "ERROR:write"
        ;;
    stop)
        echo "0" > /etc/tesvolt_proxy_enabled 2>/dev/null && echo "OK:stop" || echo "ERROR:write"
        ;;
    status)
        EN=$(cat /etc/tesvolt_proxy_enabled 2>/dev/null)
        [ -z "$EN" ] && EN=1
        if pgrep -f "modbus_proxy.lua" >/dev/null 2>&1; then RUN=1; else RUN=0; fi
        SIM=$(cat /etc/tesvolt_sim 2>/dev/null)
        [ -z "$SIM" ] && SIM=0
        echo "enabled=$EN running=$RUN sim=$SIM"
        ;;
    *)
        echo "ERROR:invalid action"
        ;;
esac

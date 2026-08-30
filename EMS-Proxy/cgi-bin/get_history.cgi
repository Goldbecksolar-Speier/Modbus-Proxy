#!/bin/sh
# get_history.cgi - Liefert die 24h-Verlaufs-Historie als CSV.
# Format pro Zeile: <unix_ts_sekunden>;<register>;<rohwert>
# Datenquelle: /tmp/ems_history.csv (geschrieben vom Watchdog, alle 5 min).
# Rein lesend.
echo "Content-Type: text/plain"
echo ""
cat /tmp/ems_history.csv 2>/dev/null

#!/bin/sh
# health.cgi - Liefert Service-Gesundheitsdaten als Key=Value-Zeilen.
# Nur lesend, keine Eingriffe (Regel: keine Auto-Aenderungen an Produktivsystemen).
# Ausgabeformat: eine key=value Zeile pro Wert, Abschnitt LOG: danach Rohzeilen.
echo "Content-Type: text/plain"
echo ""

# --- Proxy-Prozess ---
PROXY_PID=$(pgrep -f "modbus_proxy.lua" 2>/dev/null | head -n1)
if [ -n "$PROXY_PID" ]; then
    echo "proxy_running=1"
    echo "proxy_pid=$PROXY_PID"
else
    echo "proxy_running=0"
    echo "proxy_pid=-"
fi

# --- Soll-Zustand (enabled-Flag) ---
EN=$(cat /etc/tesvolt_proxy_enabled 2>/dev/null)
[ -z "$EN" ] && EN=1
echo "proxy_enabled=$EN"

# --- Simulationsmodus ---
SIM=$(cat /etc/tesvolt_sim 2>/dev/null)
[ -z "$SIM" ] && SIM=0
echo "sim=$SIM"

# --- Watchdog ---
WD_PIDFILE="/var/run/ems_watchdog.pid"
WD_PID=$(cat "$WD_PIDFILE" 2>/dev/null)
if [ -n "$WD_PID" ] && [ -d "/proc/$WD_PID" ]; then
    echo "watchdog_running=1"
    echo "watchdog_pid=$WD_PID"
else
    # Fallback ueber Prozessliste
    WD_PID2=$(pgrep -f "ems_watchdog" 2>/dev/null | head -n1)
    if [ -n "$WD_PID2" ]; then
        echo "watchdog_running=1"
        echo "watchdog_pid=$WD_PID2"
    else
        echo "watchdog_running=0"
        echo "watchdog_pid=-"
    fi
fi

# --- Ports (1502 Proxy, 8080 WebUI) ---
if netstat -tln 2>/dev/null | grep -q ":1502 "; then
    echo "port_1502=1"
else
    echo "port_1502=0"
fi
if netstat -tln 2>/dev/null | grep -q ":8080 "; then
    echo "port_8080=1"
else
    echo "port_8080=0"
fi

# --- System ---
UPT=$(cut -d. -f1 /proc/uptime 2>/dev/null)
echo "uptime_s=${UPT:-0}"
MEMFREE=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null)
[ -z "$MEMFREE" ] && MEMFREE=$(awk '/MemFree/ {print $2}' /proc/meminfo 2>/dev/null)
echo "mem_avail_kb=${MEMFREE:-0}"
LOAD=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)
echo "load1=${LOAD:-0}"
echo "now=$(date '+%Y-%m-%d %H:%M:%S')"

# --- Letzte relevante Logzeilen ---
echo "LOG:"
logread 2>/dev/null | grep -iE 'proxy|watchdog|oom|kill' | tail -n 15

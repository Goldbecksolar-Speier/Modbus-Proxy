#!/bin/sh
# Speichert EMS-Quelle und SMA-IPs (Setup-Seite)
#   /cgi-bin/set_ems.cgi?source=tesvolt|datamanager&ip_dm=..&ip_sma=..&unit_dm=..
echo "Content-Type: text/plain"
echo ""
SRC=$(echo "$QUERY_STRING" | sed -n 's/.*source=\([a-z]*\).*/\1/p')
IP_DM=$(echo "$QUERY_STRING" | sed -n 's/.*ip_dm=\([0-9.]*\).*/\1/p')
IP_SMA=$(echo "$QUERY_STRING" | sed -n 's/.*ip_sma=\([0-9.]*\).*/\1/p')
UNIT_DM=$(echo "$QUERY_STRING" | sed -n 's/.*unit_dm=\([0-9]*\).*/\1/p')
case "$SRC" in
    tesvolt|datamanager) echo "$SRC" > /etc/tesvolt_ems_source ;;
esac
[ -n "$IP_DM" ]  && echo "$IP_DM"  > /etc/tesvolt_ip_dm
[ -n "$IP_SMA" ] && echo "$IP_SMA" > /etc/tesvolt_ip_sma
[ -n "$UNIT_DM" ] && echo "$UNIT_DM" > /etc/tesvolt_unit_dm
echo "OK"

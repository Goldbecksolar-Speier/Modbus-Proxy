#!/bin/sh
echo "Content-Type: text/plain"
echo ""
IP_T=$(echo "$QUERY_STRING" | sed -n 's/.*ip_t=\([0-9.]*\).*/\1/p')
IP_B=$(echo "$QUERY_STRING" | sed -n 's/.*ip_b=\([0-9.]*\).*/\1/p')
[ -n "$IP_T" ] && echo "$IP_T" > /etc/tesvolt_ip_t
[ -n "$IP_B" ] && echo "$IP_B" > /etc/tesvolt_ip_b
echo "OK"

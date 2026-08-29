#!/bin/sh
echo "Content-Type: text/plain"
echo ""
CAP_T=$(echo "$QUERY_STRING" | sed -n 's/.*cap_t=\([0-9.]*\).*/\1/p')
CAP_B=$(echo "$QUERY_STRING" | sed -n 's/.*cap_b=\([0-9.]*\).*/\1/p')
[ -n "$CAP_T" ] && echo "$CAP_T" > /etc/tesvolt_cap_t
[ -n "$CAP_B" ] && echo "$CAP_B" > /etc/tesvolt_cap_b
echo "OK"

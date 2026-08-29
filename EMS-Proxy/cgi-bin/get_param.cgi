#!/bin/sh
echo "Content-Type: text/plain"
echo ""
NAME=$(echo "$QUERY_STRING" | sed -n 's/.*name=\([a-z_]*\).*/\1/p')
case "$NAME" in
    cap_t)      cat /etc/tesvolt_cap_t 2>/dev/null || echo 0 ;;
    cap_b)      cat /etc/tesvolt_cap_b 2>/dev/null || echo 0 ;;
    split_mode) cat /etc/tesvolt_split_mode 2>/dev/null || echo capacity ;;
    ip_t)       cat /etc/tesvolt_ip_t 2>/dev/null || echo "" ;;
    ip_b)       cat /etc/tesvolt_ip_b 2>/dev/null || echo "" ;;
    *)          echo "ERROR:unknown param" ;;
esac

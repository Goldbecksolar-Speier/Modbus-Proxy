#!/bin/sh
echo "Content-Type: text/plain"
echo ""
NAME=$(echo "$QUERY_STRING" | sed -n 's/.*name=\([a-z_]*\).*/\1/p')
case "$NAME" in
    cap_t)        cat /etc/tesvolt_cap_t 2>/dev/null || echo 0 ;;
    cap_b)        cat /etc/tesvolt_cap_b 2>/dev/null || echo 0 ;;
    split_mode)   cat /etc/tesvolt_split_mode 2>/dev/null || echo capacity ;;
    ip_t)         cat /etc/tesvolt_ip_t 2>/dev/null || echo "" ;;
    ip_b)         cat /etc/tesvolt_ip_b 2>/dev/null || echo "" ;;
    ip_dm)        cat /etc/tesvolt_ip_dm 2>/dev/null || echo "" ;;
    ip_sma)       cat /etc/tesvolt_ip_sma 2>/dev/null || echo "" ;;
    ems_source)   cat /etc/tesvolt_ems_source 2>/dev/null || echo tesvolt ;;
    unit_dm)      cat /etc/tesvolt_unit_dm 2>/dev/null || echo 3 ;;
    sim)          cat /etc/tesvolt_sim 2>/dev/null || echo 0 ;;
    enabled)      cat /etc/tesvolt_proxy_enabled 2>/dev/null || echo 1 ;;
    grid_max_chg) cat /etc/tesvolt_grid_max_chg 2>/dev/null || echo "" ;;
    grid_max_dis) cat /etc/tesvolt_grid_max_dis 2>/dev/null || echo "" ;;
    grid_use_ems) cat /etc/tesvolt_grid_use_ems 2>/dev/null || echo 0 ;;
    *)            echo "ERROR:unknown param" ;;
esac

#!/bin/sh
# Liefert einen einzelnen Konfigurationsparameter
#   /cgi-bin/get_param.cgi?name=<param>
echo "Content-Type: text/plain"
echo ""

NAME=$(echo "$QUERY_STRING" | sed -n 's/.*name=\([a-z_]*\).*/\1/p')

case "$NAME" in
    cap_t)        cat /etc/tesvolt_cap_t 2>/dev/null ;;
    cap_b)        cat /etc/tesvolt_cap_b 2>/dev/null ;;
    split_mode)   cat /etc/tesvolt_split_mode 2>/dev/null ;;
    ip_t)         cat /etc/tesvolt_ip_t 2>/dev/null ;;
    ip_b)         cat /etc/tesvolt_ip_b 2>/dev/null ;;
    ip_dm)        cat /etc/tesvolt_ip_dm 2>/dev/null ;;
    ip_sma)       cat /etc/tesvolt_ip_sma 2>/dev/null ;;
    ip_ems_t)     cat /etc/tesvolt_ip_ems_t 2>/dev/null ;;
    ip_ems_s)     cat /etc/tesvolt_ip_ems_s 2>/dev/null ;;
    ems_source)   cat /etc/tesvolt_ems_source 2>/dev/null ;;
    unit_dm)      cat /etc/tesvolt_unit_dm 2>/dev/null ;;
    sim)          cat /etc/tesvolt_sim 2>/dev/null ;;
    en_t)         cat /etc/tesvolt_en_t 2>/dev/null ;;
    en_b)         cat /etc/tesvolt_en_b 2>/dev/null ;;
    en_sma)       cat /etc/tesvolt_en_sma 2>/dev/null ;;
    grid_max_chg) cat /etc/tesvolt_grid_max_chg 2>/dev/null ;;
    grid_max_dis) cat /etc/tesvolt_grid_max_dis 2>/dev/null ;;
    grid_use_ems) cat /etc/tesvolt_grid_use_ems 2>/dev/null ;;
    *)            echo "" ;;
esac

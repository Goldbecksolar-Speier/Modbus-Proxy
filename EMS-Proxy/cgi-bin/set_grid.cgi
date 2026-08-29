#!/bin/sh
echo "Content-Type: text/plain"
echo ""
CHG=$(echo "$QUERY_STRING" | sed -n 's/.*chg=\([0-9.]*\).*/\1/p')
DIS=$(echo "$QUERY_STRING" | sed -n 's/.*dis=\([0-9.]*\).*/\1/p')
USE_EMS=$(echo "$QUERY_STRING" | sed -n 's/.*use_ems=\([01]\).*/\1/p')
# Leere Werte sind erlaubt (= Limit nicht gesetzt, nur Warnhinweis in UI)
echo "$CHG" > /etc/tesvolt_grid_max_chg
echo "$DIS" > /etc/tesvolt_grid_max_dis
[ -n "$USE_EMS" ] && echo "$USE_EMS" > /etc/tesvolt_grid_use_ems
echo "OK"

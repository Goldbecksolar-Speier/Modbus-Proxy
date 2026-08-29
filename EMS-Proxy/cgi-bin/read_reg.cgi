#!/bin/sh
echo "Content-Type: text/plain"
echo ""
REG=$(echo "$QUERY_STRING" | sed -n 's/.*reg=\([0-9]*\).*/\1/p')
if [ -z "$REG" ]; then
    echo "ERROR:no reg"
    exit 0
fi
if ! grep -q "^$REG$" /etc/tesvolt_proxy_registers 2>/dev/null; then
    echo "NOT_FOUND"
    exit 0
fi
VAL=$(modbus_cli tcp 127.0.0.1 -p 1502 -u 1 -r "$REG" -t s16 2>/dev/null)
if [ -z "$VAL" ]; then
    echo "ERROR:read failed"
else
    echo "$VAL"
fi

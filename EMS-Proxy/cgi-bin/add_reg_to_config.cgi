#!/bin/sh
echo "Content-Type: text/plain"
echo ""
REG=$(echo "$QUERY_STRING" | sed -n 's/.*reg=\([0-9]*\).*/\1/p')
if [ -z "$REG" ]; then
    echo "ERROR:no reg"
    exit 0
fi
if ! grep -q "^$REG$" /etc/tesvolt_proxy_registers 2>/dev/null; then
    echo "$REG" >> /etc/tesvolt_proxy_registers
fi
echo "OK:$REG"

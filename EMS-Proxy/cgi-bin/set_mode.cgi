#!/bin/sh
echo "Content-Type: text/plain"
echo ""
MODE=$(echo "$QUERY_STRING" | sed -n 's/.*mode=\([a-z]*\).*/\1/p')
if [ "$MODE" = "split" ] || [ "$MODE" = "passthrough" ]; then
    echo "$MODE" > /etc/tesvolt_proxy_mode
    echo "OK:$MODE"
else
    echo "ERROR:invalid mode"
fi

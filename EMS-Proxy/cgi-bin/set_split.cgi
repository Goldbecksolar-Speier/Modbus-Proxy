#!/bin/sh
echo "Content-Type: text/plain"
echo ""
SPLIT=$(echo "$QUERY_STRING" | sed -n 's/.*split=\([a-z]*\).*/\1/p')
if [ "$SPLIT" = "capacity" ] || [ "$SPLIT" = "soc" ]; then
    echo "$SPLIT" > /etc/tesvolt_split_mode
    echo "OK:$SPLIT"
else
    echo "ERROR:invalid split mode"
fi

#!/bin/sh
echo "Content-Type: text/plain"
echo ""
cat /etc/tesvolt_proxy_mode 2>/dev/null || echo "passthrough"

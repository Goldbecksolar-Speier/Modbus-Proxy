#!/bin/sh
# Simulationsmodus ein-/ausschalten (1 = Fantasiewerte, keine Geraete)
echo "Content-Type: text/plain"
echo ""
SIM=$(echo "$QUERY_STRING" | sed -n 's/.*sim=\([01]\).*/\1/p')
if [ "$SIM" = "0" ] || [ "$SIM" = "1" ]; then
    echo "$SIM" > /etc/tesvolt_sim 2>/dev/null && echo "OK:$SIM" || echo "ERROR:write"
else
    echo "ERROR:invalid sim"
fi

#!/bin/bash

LOCATION=""

DATA=$(curl -s 'wttr.in/'"${LOCATION}"'?format=%c|%t|%C|%l')

if [ -z "$DATA" ]; then
    echo '{"text": "N/A", "tooltip": "Weather unavailable"}'
    exit 1
fi

ICON=$(echo "$DATA" | cut -d'|' -f1 | xargs)
TEMP=$(echo "$DATA" | cut -d'|' -f2 | xargs)
DESC=$(echo "$DATA" | cut -d'|' -f3 | xargs)
LOC=$(echo "$DATA" | cut -d'|' -f4 | xargs)

echo "{\"text\": \"$ICON $TEMP\", \"tooltip\": \"$DESC $LOC\"}"

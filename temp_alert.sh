#!/bin/bash
# temp_alert.sh
# Monitor UPS temperature

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TELEGRAM_SCRIPT="$SCRIPT_DIR/send_telegram_alert.sh"

# Read temperature from C program
read -r temperature

# Alert threshold (40°C is reasonable for most UPS units)
TEMP_THRESHOLD=40.0

if (( $(echo "$temperature > $TEMP_THRESHOLD" | bc -l) )); then
    $TELEGRAM_SCRIPT temp "$temperature"
    logger -t ups_monitor "High temperature: $temperature°C"
fi

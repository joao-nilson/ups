#!/bin/bash
# load_alert.sh
# Monitor load and alert if high

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TELEGRAM_SCRIPT="$SCRIPT_DIR/send_telegram_alert.sh"

# Read load value from C program
read -r load_value

# Alert thresholds (adjust as needed)
WARNING_THRESHOLD=70
CRITICAL_THRESHOLD=85

if [ "$load_value" -ge "$CRITICAL_THRESHOLD" ]; then
    $TELEGRAM_SCRIPT load "$load_value"
    logger -t ups_monitor "CRITICAL load: $load_value%"
elif [ "$load_value" -ge "$WARNING_THRESHOLD" ]; then
    $TELEGRAM_SCRIPT load "$load_value"
    logger -t ups_monitor "High load: $load_value%"
fi

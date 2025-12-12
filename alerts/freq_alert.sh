#!/bin/bash
# freq_alert.sh
# Alert for frequency issues

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TELEGRAM_SCRIPT="$SCRIPT_DIR/send_telegram_alert.sh"

# Read frequency from C program
read -r frequency

# Alert if frequency is 0 or outside normal range
if (( $(echo "$frequency == 0.0" | bc -l) )) || \
   (( $(echo "$frequency < 58.0" | bc -l) )) || \
   (( $(echo "$frequency > 62.0" | bc -l) )); then
    $TELEGRAM_SCRIPT freq "$frequency"
    logger -t ups_monitor "Frequency alert: $frequency Hz"
fi

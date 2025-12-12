#!/bin/bash
# flag_alert.sh
# Monitor status flag changes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TELEGRAM_SCRIPT="$SCRIPT_DIR/send_telegram_alert.sh"

# Read flag value from C program
read -r flag_value

# Previous flag file
PREV_FLAG_FILE="/tmp/ups_previous_flag"

# Check if file exists and read previous flag
if [ -f "$PREV_FLAG_FILE" ]; then
    previous_flag=$(cat "$PREV_FLAG_FILE")
else
    previous_flag=""
fi

# Alert on any flag change
if [ "$flag_value" != "$previous_flag" ]; then
    $TELEGRAM_SCRIPT flag "$flag_value"
    logger -t ups_monitor "Flag changed: $previous_flag -> $flag_value"
fi

# Store current flag
echo "$flag_value" > "$PREV_FLAG_FILE"

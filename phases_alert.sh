#!/bin/bash
# phases_alert.sh
# Called by C program when a phase is down

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TELEGRAM_SCRIPT="$SCRIPT_DIR/send_telegram_alert.sh"

# Read phase values from C program (via stdin)
read -r phase1 phase2 phase3

# Send alert
$TELEGRAM_SCRIPT phase "$phase1" "$phase2" "$phase3"

# Also log to system log
logger -t ups_monitor "Phase alert: $phase1 $phase2 $phase3"

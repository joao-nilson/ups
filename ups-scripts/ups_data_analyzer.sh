#!/bin/bash
LOG_DIR="/var/log/ups"
DATA_LOG="$LOG_DIR/ups_data.csv"

if [ ! -f "$DATA_LOG" ]; then
    echo "No data log found at $DATA_LOG"
    exit 1
fi

echo "=== UPS Data Analysis ==="
echo "Log file: $DATA_LOG"
echo ""

# Count records
TOTAL_RECORDS=$(wc -l < "$DATA_LOG" | awk '{print $1}')
echo "Total records: $((TOTAL_RECORDS - 1))" # Subtract header

if [ $TOTAL_RECORDS -le 1 ]; then
    echo "No data records found."
    exit 0
fi

echo ""
echo "=== Voltage Statistics ==="
awk -F, 'NR>1 {print $2}' "$DATA_LOG" | sort -n | awk '
  NR==1 {min=$1} 
  {sum+=$1} 
  END {printf "Phase 1: Min=%.1fV, Max=%.1fV, Avg=%.1fV\n", min, $1, sum/(NR-1)}'

awk -F, 'NR>1 {print $3}' "$DATA_LOG" | sort -n | awk '
  NR==1 {min=$1} 
  {sum+=$1} 
  END {printf "Phase 2: Min=%.1fV, Max=%.1fV, Avg=%.1fV\n", min, $1, sum/(NR-1)}'

awk -F, 'NR>1 {print $4}' "$DATA_LOG" | sort -n | awk '
  NR==1 {min=$1} 
  {sum+=$1} 
  END {printf "Phase 3: Min=%.1fV, Max=%.1fV, Avg=%.1fV\n", min, $1, sum/(NR-1)}'

echo ""
echo "=== Load Statistics ==="
awk -F, 'NR>1 {print $5}' "$DATA_LOG" | sort -n | awk '
  NR==1 {min=$1} 
  {sum+=$1} 
  END {printf "Load: Min=%d%%, Max=%d%%, Avg=%.1f%%\n", min, $1, sum/(NR-1)}'

echo ""
echo "=== Recent Events ==="
EVENT_LOG="$LOG_DIR/ups_events.log"
if [ -f "$EVENT_LOG" ]; then
    tail -10 "$EVENT_LOG"
else
    echo "No event log found."
fi

echo ""
echo "=== Status Flag Summary ==="
awk -F, 'NR>1 {print $9}' "$DATA_LOG" | sort | uniq -c | sort -nr | while read count flags; do
    binary=$(echo "obase=2;$flags" | bc)
    printf "Count: %3d - Flags: %8s (binary: %08s)\n" "$count" "$flags" "$binary"
done

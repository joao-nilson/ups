#!/bin/bash
DATA_LOG="/var/log/ups/ups_data.csv"

if [ ! -f "$DATA_LOG" ]; then
    echo "No data log found at $DATA_LOG"
    exit 1
fi

echo "=== UPS Data Analysis ==="
echo "Log file: $DATA_LOG"
echo ""

# Count records
TOTAL_RECORDS=$(wc -l < "$DATA_LOG")
VALID_RECORDS=$(grep -c '^[0-9]\{4\}-[0-9]' "$DATA_LOG")
echo "Total records: $((TOTAL_RECORDS - 1))"
echo "Valid data records: $VALID_RECORDS"

if [ $VALID_RECORDS -eq 0 ]; then
    echo "No valid data records found."
    exit 0
fi

echo ""
echo "=== Voltage Statistics (Last 24 hours) ==="
awk -F, -v today=$(date '+%Y-%m-%d') '$1 ~ today && $2 ~ /^[0-9]/ {print $2}' "$DATA_LOG" | awk '
NR==1 {min=$1; max=$1; sum=0}
{
    if($1<min) min=$1;
    if($1>max) max=$1;
    sum+=$1;
    count++
}
END {
    if(count>0) 
        printf "Phase 1: Min=%.1fV, Max=%.1fV, Avg=%.1fV (%d samples)\n", min, max, sum/count, count
    else
        print "No data for today"
}'

awk -F, -v today=$(date '+%Y-%m-%d') '$1 ~ today && $3 ~ /^[0-9]/ {print $3}' "$DATA_LOG" | awk '
NR==1 {min=$1; max=$1; sum=0}
{
    if($1<min) min=$1;
    if($1>max) max=$1;
    sum+=$1;
    count++
}
END {
    if(count>0) 
        printf "Phase 2: Min=%.1fV, Max=%.1fV, Avg=%.1fV (%d samples)\n", min, max, sum/count, count
    else
        print "No data for today"
}'

awk -F, -v today=$(date '+%Y-%m-%d') '$1 ~ today && $4 ~ /^[0-9]/ {print $4}' "$DATA_LOG" | awk '
NR==1 {min=$1; max=$1; sum=0}
{
    if($1<min) min=$1;
    if($1>max) max=$1;
    sum+=$1;
    count++
}
END {
    if(count>0) 
        printf "Phase 3: Min=%.1fV, Max=%.1fV, Avg=%.1fV (%d samples)\n", min, max, sum/count, count
    else
        print "No data for today"
}'

echo ""
echo "=== Load Statistics ==="
awk -F, '$5 ~ /^[0-9]/ {print $5}' "$DATA_LOG" | sort -n | awk '
NR==1 {min=$1} 
{sum+=$1} 
END {
    if(NR>0) 
        printf "Load: Min=%d%%, Max=%d%%, Avg=%.1f%% (%d samples)\n", min, $1, sum/NR, NR
    else
        print "No load data"
}'

echo ""
echo "=== Recent Status Flags ==="
awk -F, '$9 ~ /^[0-9]/ {print $9}' "$DATA_LOG" | tail -10 | while read flags; do
    binary=$(echo "obase=2;$flags" | bc | xargs printf "%08d")
    echo "Flags: $flags (binary: $binary)"
done

echo ""
echo "=== Latest Entry ==="
tail -1 "$DATA_LOG"

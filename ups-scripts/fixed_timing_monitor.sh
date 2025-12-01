#!/bin/bash
DEVICE="/dev/ttyUSB0"
LOG_DIR="/var/log/ups"
DATA_LOG="$LOG_DIR/ups_data.csv"
EVENT_LOG="$LOG_DIR/ups_events.log"

sudo mkdir -p $LOG_DIR

# Create CSV header
if [ ! -f "$DATA_LOG" ]; then
    echo "timestamp,voltage_phase1,voltage_phase2,voltage_phase3,load_percent,frequency,battery_voltage,temperature,status_flags" | sudo tee $DATA_LOG
fi

sudo stty -F $DEVICE 2400 cs8 -cstopb -parenb -ixon -ixoff raw

# Function to log events
log_event() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a $EVENT_LOG
}

echo "=== Fixed Timing UPS Monitor ==="
echo "Logging to: $DATA_LOG"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Clear buffer more aggressively
    sudo timeout 2 cat $DEVICE > /dev/null 2>&1
    
    # Send command
    echo -ne "Q1\r" | sudo tee $DEVICE > /dev/null
    
    # Wait longer and collect multiple reads
    sleep 4
    RESPONSE1=$(timeout 2 sudo cat $DEVICE)
    sleep 1
    RESPONSE2=$(timeout 2 sudo cat $DEVICE)
    sleep 1
    RESPONSE3=$(timeout 2 sudo cat $DEVICE)
    
    # Combine all responses
    FULL_RESPONSE="${RESPONSE1} ${RESPONSE2} ${RESPONSE3}"
    CLEAN_RESPONSE=$(echo "$FULL_RESPONSE" | tr -d '\n\r' | sed 's/  */ /g')
    
    # Debug output
    echo "Debug - Combined response: '$CLEAN_RESPONSE'"
    
    # Try multiple parsing patterns
    if [[ "$CLEAN_RESPONSE" =~ \(([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+) ]]; then
        # Full 8-value response
        V1="${BASH_REMATCH[1]}"
        V2="${BASH_REMATCH[2]}"
        V3="${BASH_REMATCH[3]}"
        LOAD="${BASH_REMATCH[4]}"
        FREQ="${BASH_REMATCH[5]}"
        BATT="${BASH_REMATCH[6]}"
        TEMP="${BASH_REMATCH[7]}"
        FLAGS="${BASH_REMATCH[8]}"
        
        echo "$TIMESTAMP,$V1,$V2,$V3,$LOAD,$FREQ,$BATT,$TEMP,$FLAGS" | sudo tee -a $DATA_LOG
        log_event "SUCCESS: Full data parsed and logged"
        
    elif [[ "$CLEAN_RESPONSE" =~ \(([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+)\ ([0-9.]+)\ ([0-9.]+) ]]; then
        # 6-value response (missing temp and flags)
        V1="${BASH_REMATCH[1]}"
        V2="${BASH_REMATCH[2]}"
        V3="${BASH_REMATCH[3]}"
        LOAD="${BASH_REMATCH[4]}"
        FREQ="${BASH_REMATCH[5]}"
        BATT="${BASH_REMATCH[6]}"
        
        echo "$TIMESTAMP,$V1,$V2,$V3,$LOAD,$FREQ,$BATT,UNKNOWN,UNKNOWN" | sudo tee -a $DATA_LOG
        log_event "PARTIAL: Logged 6 values (missing temp/flags)"
        
    else
        log_event "ERROR: Failed to parse response: $CLEAN_RESPONSE"
        echo "No parseable data received"
    fi
    
    # Display current status from log
    clear
    echo "=== UPS Monitor - $TIMESTAMP ==="
    echo "Data Log: $DATA_LOG"
    echo "Event Log: $EVENT_LOG"
    echo ""
    tail -1 "$DATA_LOG" | awk -F, '{
        printf "Voltage L1: %s V\n", $2
        printf "Voltage L2: %s V\n", $3
        printf "Voltage L3: %s V\n", $4
        printf "Load: %s %%\n", $5
        printf "Frequency: %s Hz\n", $6
        printf "Battery: %s V\n", $7
        printf "Temperature: %s °C\n", $8
        printf "Status Flags: %s\n", $9
    }'
    
    echo ""
    echo "Total entries: $(($(wc -l < "$DATA_LOG") - 1))"
    echo "Next update in 30 seconds..."
    sleep 30
done

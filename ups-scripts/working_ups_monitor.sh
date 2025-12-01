#!/bin/bash
DEVICE="/dev/ttyUSB0"
LOG_DIR="/var/log/ups"
DATA_LOG="$LOG_DIR/ups_data.csv"

# Create logs directory
sudo mkdir -p $LOG_DIR

# Create CSV header
if [ ! -f "$DATA_LOG" ]; then
    echo "timestamp,voltage_phase1,voltage_phase2,voltage_phase3,load_percent,frequency,battery_voltage,temperature,status_flags" | sudo tee $DATA_LOG
fi

# Set serial parameters
sudo stty -F $DEVICE 2400 cs8 -cstopb -parenb -ixon -ixoff raw

echo "=== ATA UPS Monitor ==="
echo "Logging to: $DATA_LOG"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    # Clear any old data
    sudo timeout 0.5 cat $DEVICE > /dev/null 2>&1
    
    # Get status from UPS
    echo -ne "Q1\r" | sudo tee $DEVICE > /dev/null
    sleep 3  # Give more time for complete response
    
    # Read the response - capture everything
    RESPONSE=$(timeout 4 sudo cat $DEVICE)
    
    # Clean up the response
    CLEAN_RESPONSE=$(echo "$RESPONSE" | tr -d '\n\r' | sed 's/  */ /g')
    
    # Debug: show what we received
    echo "Debug - Raw response: '$RESPONSE'"
    echo "Debug - Clean response: '$CLEAN_RESPONSE'"
    
    # Parse the response - handle the format: (121.9 122.1 127.4 049 59.9 2.28
    if [[ "$CLEAN_RESPONSE" =~ \(([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+) ]]; then
        # Full response with all 8 values
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        V1="${BASH_REMATCH[1]}"
        V2="${BASH_REMATCH[2]}"
        V3="${BASH_REMATCH[3]}"
        LOAD="${BASH_REMATCH[4]}"
        FREQ="${BASH_REMATCH[5]}"
        BATT="${BASH_REMATCH[6]}"
        TEMP="${BASH_REMATCH[7]}"
        FLAGS="${BASH_REMATCH[8]}"
        
        echo "$TIMESTAMP,$V1,$V2,$V3,$LOAD,$FREQ,$BATT,$TEMP,$FLAGS" | sudo tee -a $DATA_LOG
        
        clear
        echo "=== ATA UPS Status - $TIMESTAMP ==="
        echo "Voltage L1: $V1 V"
        echo "Voltage L2: $V2 V" 
        echo "Voltage L3: $V3 V"
        echo "Load: $LOAD %"
        echo "Frequency: $FREQ Hz"
        echo "Battery: $BATT V"
        echo "Temperature: $TEMP °C"
        echo "Status Flags: $FLAGS"
        
    elif [[ "$CLEAN_RESPONSE" =~ \(([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+)\ ([0-9.]+)\ ([0-9.]+) ]]; then
        # Partial response - we're missing temperature and flags
        # Let's try to get the complete response with another read
        echo "Got partial response, trying to get remainder..."
        REMAINDER=$(timeout 2 sudo cat $DEVICE)
        FULL_RESPONSE="$CLEAN_RESPONSE $REMAINDER"
        FULL_CLEAN=$(echo "$FULL_RESPONSE" | tr -d '\n\r' | sed 's/  */ /g')
        
        echo "Debug - Full response: '$FULL_CLEAN'"
        
        if [[ "$FULL_CLEAN" =~ \(([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+) ]]; then
            TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
            V1="${BASH_REMATCH[1]}"
            V2="${BASH_REMATCH[2]}"
            V3="${BASH_REMATCH[3]}"
            LOAD="${BASH_REMATCH[4]}"
            FREQ="${BASH_REMATCH[5]}"
            BATT="${BASH_REMATCH[6]}"
            TEMP="${BASH_REMATCH[7]}"
            FLAGS="${BASH_REMATCH[8]}"
            
            echo "$TIMESTAMP,$V1,$V2,$V3,$LOAD,$FREQ,$BATT,$TEMP,$FLAGS" | sudo tee -a $DATA_LOG
            
            clear
            echo "=== ATA UPS Status - $TIMESTAMP ==="
            echo "Voltage L1: $V1 V"
            echo "Voltage L2: $V2 V" 
            echo "Voltage L3: $V3 V"
            echo "Load: $LOAD %"
            echo "Frequency: $FREQ Hz"
            echo "Battery: $BATT V"
            echo "Temperature: $TEMP °C"
            echo "Status Flags: $FLAGS"
        else
            # Log partial data anyway
            TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
            V1="${BASH_REMATCH[1]}"
            V2="${BASH_REMATCH[2]}"
            V3="${BASH_REMATCH[3]}"
            LOAD="${BASH_REMATCH[4]}"
            FREQ="${BASH_REMATCH[5]}"
            BATT="${BASH_REMATCH[6]}"
            
            echo "$TIMESTAMP,$V1,$V2,$V3,$LOAD,$FREQ,$BATT,UNKNOWN,UNKNOWN" | sudo tee -a $DATA_LOG
            echo "Logged partial data (missing temp and flags)"
        fi
    else
        echo "No parseable data received: $CLEAN_RESPONSE"
    fi
    
    echo ""
    echo "Entries in log: $(($(wc -l < "$DATA_LOG") - 1))"
    echo "Next update in 30 seconds..."
    sleep 30
done

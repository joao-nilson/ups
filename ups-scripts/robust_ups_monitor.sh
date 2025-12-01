#!/bin/bash
DEVICE="/dev/ttyUSB0"
LOG_DIR="/var/log/ups"
DATA_LOG="$LOG_DIR/ups_data.csv"

sudo mkdir -p $LOG_DIR

# Create CSV header
if [ ! -f "$DATA_LOG" ]; then
    echo "timestamp,voltage_phase1,voltage_phase2,voltage_phase3,load_percent,frequency,battery_voltage,temperature,status_flags" | sudo tee $DATA_LOG
fi

sudo stty -F $DEVICE 2400 cs8 -cstopb -parenb -ixon -ixoff raw

echo "=== Robust ATA UPS Monitor ==="
echo "Logging to: $DATA_LOG"
echo "Press Ctrl+C to stop"
echo ""

# Function to get complete UPS response
get_ups_data() {
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Clear buffer
        sudo timeout 1 cat $DEVICE > /dev/null 2>&1
        
        # Send command
        echo -ne "Q1\r" | sudo tee $DEVICE > /dev/null
        
        # Wait for response and collect all data
        local response=""
        local start_time=$(date +%s)
        
        while [ $(($(date +%s) - start_time)) -lt 5 ]; do
            local chunk=$(timeout 1 sudo cat $DEVICE 2>/dev/null)
            if [ -n "$chunk" ]; then
                response="${response}${chunk}"
                # Check if we have a complete response (contains all 8 values)
                if [[ "$response" =~ \(([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+) ]]; then
                    echo "$response"
                    return 0
                fi
            fi
            sleep 0.1
        done
        
        attempt=$((attempt + 1))
        echo "Attempt $attempt failed, retrying..." >&2
        sleep 1
    done
    
    echo "ERROR: Failed to get complete response after $max_attempts attempts" >&2
    return 1
}

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Get data from UPS
    RESPONSE=$(get_ups_data)
    
    if [ $? -eq 0 ] && [[ "$RESPONSE" =~ \(([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+) ]]; then
        V1="${BASH_REMATCH[1]}"
        V2="${BASH_REMATCH[2]}"
        V3="${BASH_REMATCH[3]}"
        LOAD="${BASH_REMATCH[4]}"
        FREQ="${BASH_REMATCH[5]}"
        BATT="${BASH_REMATCH[6]}"
        TEMP="${BASH_REMATCH[7]}"
        FLAGS="${BASH_REMATCH[8]}"
        
        # Log to CSV
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
        
        # Status interpretation
        echo ""
        echo "=== Status Interpretation ==="
        if [ $((FLAGS & 1)) -ne 0 ]; then echo "✓ Utility Power OK"; else echo "✗ Utility Power Failed - On Battery"; fi
        if [ $((FLAGS & 2)) -ne 0 ]; then echo "✓ Battery Charging"; else echo "✗ Battery Not Charging"; fi
        if [ $((FLAGS & 4)) -ne 0 ]; then echo "⚠ Low Battery"; else echo "✓ Battery OK"; fi
        if [ $((FLAGS & 8)) -ne 0 ]; then echo "⚡ UPS Online"; else echo "🔌 UPS on Bypass"; fi
        if [ $((FLAGS & 16)) -ne 0 ]; then echo "🔧 Test in Progress"; fi
        if [ $((FLAGS & 32)) -ne 0 ]; then echo "🚨 Alarm Active"; fi
        
    else
        echo "Failed to get valid data: $RESPONSE"
        # Log error but don't add to CSV to avoid incomplete data
    fi
    
    echo ""
    echo "Total entries in log: $(($(wc -l < "$DATA_LOG") - 1))"
    echo "Next update in 30 seconds..."
    sleep 30
done

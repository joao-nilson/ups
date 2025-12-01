#!/bin/bash
DEVICE="/dev/ttyUSB0"
LOG_DIR="/var/log/ups"
DATA_LOG="$LOG_DIR/ups_data.csv"
EVENT_LOG="$LOG_DIR/ups_events.log"

# Create log directory if it doesn't exist
sudo mkdir -p $LOG_DIR
sudo chmod 755 $LOG_DIR

# Create CSV header if file doesn't exist
if [ ! -f "$DATA_LOG" ]; then
    echo "timestamp,voltage_phase1,voltage_phase2,voltage_phase3,load_percent,frequency,battery_voltage,temperature,status_flags,status_binary" | sudo tee $DATA_LOG
fi

# Function to log events
log_event() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a $EVENT_LOG
}

# Function to send command and get response
get_ups_response() {
    local command="$1"
    # Clear any existing data in buffer
    sudo timeout 1 cat $DEVICE > /dev/null 2>&1
    
    # Send command
    echo -ne "$command\r" | sudo tee $DEVICE > /dev/null
    sleep 1
    
    # Read response
    local response=$(timeout 3 sudo cat $DEVICE)
    echo "$response"
}

# Check if device exists
if [ ! -c "$DEVICE" ]; then
    log_event "ERROR: Device $DEVICE not found"
    echo "Error: Device $DEVICE not found"
    exit 1
fi

# Initialize serial port
sudo stty -F $DEVICE 2400 cs8 -cstopb -parenb -ixon -ixoff raw

log_event "UPS Monitor Started"

echo "=============================================="
echo "    ATA Hipower UPS Monitor with Logging"
echo "=============================================="
echo "Data Log: $DATA_LOG"
echo "Event Log: $EVENT_LOG"
echo ""

# Test communication
echo "Testing UPS communication..."
ID_RESPONSE=$(get_ups_response "I")
if [ -n "$ID_RESPONSE" ]; then
    echo "✓ UPS Responded: $ID_RESPONSE"
    log_event "UPS Communication OK - Identification: $ID_RESPONSE"
else
    echo "✗ No response from UPS"
    log_event "ERROR: No response from UPS on initial communication"
fi

echo ""
echo "=== Starting Monitoring ==="
echo "Press Ctrl+C to exit"
echo ""

ERROR_COUNT=0
MAX_ERRORS=5

while true; do
    # Get status from UPS
    STATUS_RESPONSE=$(get_ups_response "Q1")
    
    if [ -n "$STATUS_RESPONSE" ] && [[ "$STATUS_RESPONSE" =~ \(.*\) ]]; then
        ERROR_COUNT=0
        
        # Parse the status response
        if [[ "$STATUS_RESPONSE" =~ \(([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+) ]]; then
            TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
            V1="${BASH_REMATCH[1]}"
            V2="${BASH_REMATCH[2]}"
            V3="${BASH_REMATCH[3]}"
            LOAD="${BASH_REMATCH[4]}"
            FREQ="${BASH_REMATCH[5]}"
            BATT="${BASH_REMATCH[6]}"
            TEMP="${BASH_REMATCH[7]}"
            FLAGS="${BASH_REMATCH[8]}"
            FLAGS_BINARY=$(echo "obase=2;$FLAGS" | bc 2>/dev/null || echo "0")
            
            # Log to CSV
            echo "$TIMESTAMP,$V1,$V2,$V3,$LOAD,$FREQ,$BATT,$TEMP,$FLAGS,$FLAGS_BINARY" | sudo tee -a $DATA_LOG
            
            # Display status
            clear
            echo "=============================================="
            echo "    ATA Hipower UPS Monitor - $(date)"
            echo "=============================================="
            echo "Data Log: $DATA_LOG (entries: $(($(wc -l < "$DATA_LOG") - 1)))"
            echo "Event Log: $EVENT_LOG"
            echo ""
            echo "=== Current Status ==="
            echo "Input Voltage Phase 1: $V1 V"
            echo "Input Voltage Phase 2: $V2 V" 
            echo "Input Voltage Phase 3: $V3 V"
            echo "Load Level: $LOAD %"
            echo "Frequency: $FREQ Hz"
            echo "Battery Voltage: $BATT V"
            echo "Temperature: $TEMP °C"
            echo "Status Flags: $FLAGS (binary: $FLAGS_BINARY)"
            
            # Status interpretation
            echo ""
            echo "=== Status Interpretation ==="
            if [ $((FLAGS & 1)) -ne 0 ]; then echo "✓ Utility Power OK"; else echo "✗ Utility Power Failed"; fi
            if [ $((FLAGS & 2)) -ne 0 ]; then echo "✓ Battery Charging"; else echo "✗ Battery Not Charging"; fi
            if [ $((FLAGS & 4)) -ne 0 ]; then echo "⚠ Low Battery"; else echo "✓ Battery OK"; fi
            if [ $((FLAGS & 8)) -ne 0 ]; then echo "⚡ UPS Online"; else echo "🔌 UPS on Bypass"; fi
            if [ $((FLAGS & 16)) -ne 0 ]; then echo "🔧 Test in Progress"; fi
            if [ $((FLAGS & 32)) -ne 0 ]; then echo "🚨 Alarm Active"; fi
            
            echo ""
            echo "Last update: $TIMESTAMP"
        else
            log_event "WARNING: Could not parse response: $STATUS_RESPONSE"
            echo "Parse error: $STATUS_RESPONSE"
        fi
    else
        ERROR_COUNT=$((ERROR_COUNT + 1))
        log_event "ERROR: No response from UPS (attempt $ERROR_COUNT)"
        echo "Error: No response from UPS (attempt $ERROR_COUNT/$MAX_ERRORS)"
        
        if [ $ERROR_COUNT -ge $MAX_ERRORS ]; then
            log_event "CRITICAL: Too many errors, stopping monitor"
            echo "Too many errors, stopping monitor."
            break
        fi
    fi
    
    echo ""
    echo "Next update in 30 seconds..."
    sleep 30
done

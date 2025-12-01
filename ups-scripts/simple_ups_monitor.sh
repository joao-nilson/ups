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
    sudo timeout 1 cat $DEVICE > /dev/null 2>&1
    
    # Get status from UPS
    echo -ne "Q1\r" | sudo tee $DEVICE > /dev/null
    sleep 2
    RESPONSE=$(timeout 3 sudo cat $DEVICE)
    
    if [[ "$RESPONSE" =~ \(([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+) ]]; then
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$TIMESTAMP,${BASH_REMATCH[1]},${BASH_REMATCH[2]},${BASH_REMATCH[3]},${BASH_REMATCH[4]},${BASH_REMATCH[5]},${BASH_REMATCH[6]},${BASH_REMATCH[7]},${BASH_REMATCH[8]}" | sudo tee -a $DATA_LOG
        
        # Display current status
        clear
        echo "=== ATA UPS Status - $TIMESTAMP ==="
        echo "Voltage L1: ${BASH_REMATCH[1]}V"
        echo "Voltage L2: ${BASH_REMATCH[2]}V" 
        echo "Voltage L3: ${BASH_REMATCH[3]}V"
        echo "Load: ${BASH_REMATCH[4]}%"
        echo "Frequency: ${BASH_REMATCH[5]}Hz"
        echo "Battery: ${BASH_REMATCH[6]}V"
        echo "Temperature: ${BASH_REMATCH[7]}°C"
        echo "Status: ${BASH_REMATCH[8]}"
        echo ""
        echo "Data logged to: $DATA_LOG"
        echo "Next update in 30 seconds..."
    else
        echo "No data received: $RESPONSE"
    fi
    
    sleep 30
done

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

# Set serial parameters
sudo stty -F $DEVICE 2400 cs8 -cstopb -parenb -ixon -ixoff raw

# Function to log events
log_event() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a $EVENT_LOG
}

# Function to parse and log data
log_ups_data() {
    local response="$1"
    
    if [[ "$response" =~ \(([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+) ]]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local v1="${BASH_REMATCH[1]}"
        local v2="${BASH_REMATCH[2]}"
        local v3="${BASH_REMATCH[3]}"
        local load="${BASH_REMATCH[4]}"
        local freq="${BASH_REMATCH[5]}"
        local batt="${BASH_REMATCH[6]}"
        local temp="${BASH_REMATCH[7]}"
        local flags="${BASH_REMATCH[8]}"
        local flags_binary=$(echo "obase=2;$flags" | bc)
        
        # Log to CSV
        echo "$timestamp,$v1,$v2,$v3,$load,$freq,$batt,$temp,$flags,$flags_binary" | sudo tee -a $DATA_LOG
        
        # Return values for display
        echo "$v1:$v2:$v3:$load:$freq:$batt:$temp:$flags"
    else
        echo "parse_error"
    fi
}

# Function to check for status changes
check_status_change() {
    local current_flags="$1"
    local last_flags="$2"
    
    if [ "$current_flags" != "$last_flags" ]; then
        local changes=$((current_flags ^ last_flags))
        
        if [ $((changes & 1)) -ne 0 ]; then
            if [ $((current_flags & 1)) -ne 0 ]; then
                log_event "STATUS CHANGE: Utility Power Restored"
            else
                log_event "STATUS CHANGE: Utility Power Failed - Running on Battery"
            fi
        fi
        
        if [ $((changes & 2)) -ne 0 ]; then
            if [ $((current_flags & 2)) -ne 0 ]; then
                log_event "STATUS CHANGE: Battery Charging Started"
            else
                log_event "STATUS CHANGE: Battery Charging Stopped"
            fi
        fi
        
        if [ $((changes & 4)) -ne 0 ]; then
            if [ $((current_flags & 4)) -ne 0 ]; then
                log_event "ALERT: Low Battery Warning"
            else
                log_event "STATUS CHANGE: Battery Level Normal"
            fi
        fi
        
        if [ $((changes & 8)) -ne 0 ]; then
            if [ $((current_flags & 8)) -ne 0 ]; then
                log_event "STATUS CHANGE: UPS Online Mode"
            else
                log_event "STATUS CHANGE: UPS Bypass Mode"
            fi
        fi
        
        if [ $((changes & 16)) -ne 0 ]; then
            if [ $((current_flags & 16)) -ne 0 ]; then
                log_event "STATUS CHANGE: Self Test Started"
            else
                log_event "STATUS CHANGE: Self Test Completed"
            fi
        fi
        
        if [ $((changes & 32)) -ne 0 ]; then
            if [ $((current_flags & 32)) -ne 0 ]; then
                log_event "ALARM: UPS Alarm Activated"
            else
                log_event "ALARM: UPS Alarm Cleared"
            fi
        fi
    fi
}

echo "=============================================="
echo "    ATA Hipower UPS Monitor with Logging"
echo "=============================================="
echo "Data Log: $DATA_LOG"
echo "Event Log: $EVENT_LOG"
echo ""

# Get identification info
echo -ne "I\r" | sudo tee $DEVICE > /dev/null
sleep 0.5
ID_RESPONSE=$(timeout 2 sudo cat $DEVICE)
log_event "UPS Monitor Started - Identification: $ID_RESPONSE"
echo "Identification: $ID_RESPONSE"

# Initialize last flags for change detection
LAST_FLAGS=""

echo ""
echo "=== Starting Monitoring ==="
echo "Press Ctrl+C to exit"
echo ""

while true; do
    # Get status
    echo -ne "Q1\r" | sudo tee $DEVICE > /dev/null
    sleep 0.5
    STATUS_RESPONSE=$(timeout 2 sudo cat $DEVICE)
    
    # Parse and log data
    PARSED_DATA=$(log_ups_data "$STATUS_RESPONSE")
    
    if [ "$PARSED_DATA" != "parse_error" ]; then
        IFS=':' read -r v1 v2 v3 load freq batt temp flags <<< "$PARSED_DATA"
        
        # Check for status changes
        if [ -n "$LAST_FLAGS" ] && [ "$flags" != "$LAST_FLAGS" ]; then
            check_status_change "$flags" "$LAST_FLAGS"
        fi
        LAST_FLAGS="$flags"
        
        # Display current status
        clear
        echo "=============================================="
        echo "    ATA Hipower UPS Monitor - $(date)"
        echo "=============================================="
        echo "Data Log: $DATA_LOG"
        echo "Event Log: $EVENT_LOG"
        echo ""
        echo "=== Current Status ==="
        echo "Input Voltage Phase 1: $v1 V"
        echo "Input Voltage Phase 2: $v2 V" 
        echo "Input Voltage Phase 3: $v3 V"
        echo "Load Level: $load %"
        echo "Frequency: $freq Hz"
        echo "Battery Voltage: $batt V"
        echo "Temperature: $temp °C"
        echo "Status Flags: $flags (binary: $(echo "obase=2;$flags" | bc))"
        
        # Status interpretation
        echo ""
        echo "=== Status Interpretation ==="
        if [ $((flags & 1)) -ne 0 ]; then echo "✓ Utility Power OK"; else echo "✗ Utility Power Failed"; fi
        if [ $((flags & 2)) -ne 0 ]; then echo "✓ Battery Charging"; else echo "✗ Battery Not Charging"; fi
        if [ $((flags & 4)) -ne 0 ]; then echo "⚠ Low Battery"; else echo "✓ Battery OK"; fi
        if [ $((flags & 8)) -ne 0 ]; then echo "⚡ UPS Online"; else echo "🔌 UPS on Bypass"; fi
        if [ $((flags & 16)) -ne 0 ]; then echo "🔧 Test in Progress"; fi
        if [ $((flags & 32)) -ne 0 ]; then echo "🚨 Alarm Active"; fi
        
        echo ""
        echo "Last data logged at: $(date '+%H:%M:%S')"
    else
        echo "Failed to parse status: $STATUS_RESPONSE"
        log_event "ERROR: Failed to parse status response: $STATUS_RESPONSE"
    fi
    
    echo ""
    echo "Next update in 30 seconds..."
    sleep 30
done

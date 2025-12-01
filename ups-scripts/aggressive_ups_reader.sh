#!/bin/bash
DEVICE="/dev/ttyUSB0"
LOG_DIR="/var/log/ups"
DATA_LOG="$LOG_DIR/ups_data.csv"
RAW_LOG="$LOG_DIR/ups_raw_detailed.log"

sudo mkdir -p $LOG_DIR

# Create CSV header
if [ ! -f "$DATA_LOG" ]; then
    echo "timestamp,voltage_phase1,voltage_phase2,voltage_phase3,load_percent,frequency,battery_voltage,temperature,status_flags" | sudo tee $DATA_LOG
fi

sudo stty -F $DEVICE 2400 cs8 -cstopb -parenb -ixon -ixoff raw

echo "=== Aggressive UPS Reader ==="
echo "Data Log: $DATA_LOG"
echo "Raw Log: $RAW_LOG"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Aggressive buffer clearing
    echo "Clearing buffer..."
    for i in {1..3}; do
        sudo timeout 0.5 cat $DEVICE > /dev/null 2>&1
        sleep 0.1
    done
    
    # Send command multiple times (some UPS need this)
    echo "Sending command..."
    for i in {1..2}; do
        echo -ne "Q1\r" | sudo tee $DEVICE > /dev/null
        sleep 0.5
    done
    
    # Collect data over longer period with multiple reads
    echo "Collecting response..."
    FULL_RESPONSE=""
    for i in {1..10}; do
        CHUNK=$(timeout 1 sudo cat $DEVICE 2>/dev/null)
        if [ -n "$CHUNK" ]; then
            FULL_RESPONSE="${FULL_RESPONSE} ${CHUNK}"
            echo "Chunk $i: $CHUNK"
        fi
        sleep 0.5
    done
    
    # Log raw response for analysis
    echo "$TIMESTAMP - Full collected: $FULL_RESPONSE" | sudo tee -a $RAW_LOG
    
    # Clean the response
    CLEAN_RESPONSE=$(echo "$FULL_RESPONSE" | tr -d '\n\r' | sed 's/  */ /g')
    
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
        echo "✅ SUCCESS: Full data logged"
        
    elif [[ "$CLEAN_RESPONSE" =~ \(([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+)\ ([0-9.]+)\ ([0-9.]+) ]]; then
        # 6-value response (most common partial)
        V1="${BASH_REMATCH[1]}"
        V2="${BASH_REMATCH[2]}"
        V3="${BASH_REMATCH[3]}"
        LOAD="${BASH_REMATCH[4]}"
        FREQ="${BASH_REMATCH[5]}"
        BATT="${BASH_REMATCH[6]}"
        
        echo "$TIMESTAMP,$V1,$V2,$V3,$LOAD,$FREQ,$BATT,UNKNOWN,UNKNOWN" | sudo tee -a $DATA_LOG
        echo "⚠️ PARTIAL: Logged 6 values"
        
        # Try to find missing values in the full response
        if [[ "$CLEAN_RESPONSE" =~ ([0-9.]+)\ ([0-9]+)([^0-9]*)$ ]]; then
            TEMP_FOUND="${BASH_REMATCH[1]}"
            FLAGS_FOUND="${BASH_REMATCH[2]}"
            if [ -n "$TEMP_FOUND" ] && [ -n "$FLAGS_FOUND" ]; then
                echo "Found potential missing values: temp=$TEMP_FOUND, flags=$FLAGS_FOUND"
            fi
        fi
    else
        echo "❌ No parseable data"
        echo "$TIMESTAMP,UNKNOWN,UNKNOWN,UNKNOWN,UNKNOWN,UNKNOWN,UNKNOWN,UNKNOWN,UNKNOWN" | sudo tee -a $DATA_LOG
    fi
    
    echo "Waiting 30 seconds..."
    echo "========================"
    sleep 30
done

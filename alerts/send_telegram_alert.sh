#!/bin/bash
# send_telegram_alert.sh
# Send alerts to Telegram with formatted messages

# Configuration
TELEGRAM_BOT_TOKEN="BOT_TOKEN"
TELEGRAM_CHAT_ID="CHAT_ID"
LOG_FILE="/var/log/ups_alerts.log"
ALERT_COOLDOWN_MINUTES=5  # Prevent spam alerts

# Alert types
ALERT_PHASE_DOWN="PHASE_DOWN"
ALERT_HIGH_LOAD="HIGH_LOAD"
ALERT_FREQ_ISSUE="FREQUENCY_ISSUE"
ALERT_HIGH_TEMP="HIGH_TEMPERATURE"
ALERT_FLAG_CHANGE="FLAG_CHANGE"

# Function to log alerts
log_alert() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to check cooldown
check_cooldown() {
    local alert_type="$1"
    local cooldown_file="/tmp/ups_alert_cooldown_${alert_type}"
    
    if [ -f "$cooldown_file" ]; then
        local last_alert_time=$(cat "$cooldown_file")
        local current_time=$(date +%s)
        local elapsed_minutes=$(( (current_time - last_alert_time) / 60 ))
        
        if [ $elapsed_minutes -lt $ALERT_COOLDOWN_MINUTES ]; then
            return 1  # Still in cooldown
        fi
    fi
    
    # Update cooldown file
    date +%s > "$cooldown_file"
    return 0  # Not in cooldown
}

# Function to send Telegram message
send_telegram_message() {
    local message="$1"
    local alert_type="$2"
    
    # Check cooldown
    if ! check_cooldown "$alert_type"; then
        echo "Alert $alert_type is in cooldown period"
        return 1
    fi
    
    # Send to Telegram
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\": \"$TELEGRAM_CHAT_ID\", \"text\": \"$message\", \"parse_mode\": \"HTML\"}" \
        "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage")
    
    # Log the alert
    log_alert "$alert_type: $message"
    
    # Check if successful
    if echo "$response" | grep -q '"ok":true'; then
        echo "Telegram alert sent successfully"
        return 0
    else
        echo "Failed to send Telegram alert: $response"
        return 1
    fi
}

# Function to format phase alert message
send_phase_alert() {
    local phase1="$1"
    local phase2="$2"
    local phase3="$3"
    
    local message=" <b>UPS PHASE ALERT</b> 
    
<b>Power Input Status:</b>
• Phase 1: ${phase1}V
• Phase 2: ${phase2}V
• Phase 3: ${phase3}V

 <b>Alert:</b> One or more phases are down!
 Time: $(date '+%Y-%m-%d %H:%M:%S')
 Location: UPS Room"

    send_telegram_message "$message" "$ALERT_PHASE_DOWN"
}

# Function to format load alert message
send_load_alert() {
    local load="$1"
    
    local message=" <b>UPS HIGH LOAD ALERT</b>
    
 <b>Current Load:</b> ${load}%
 <b>Status:</b> UPS is under high load
 <b>Recommendation:</b> Reduce connected equipment
 Time: $(date '+%Y-%m-%d %H:%M:%S')"

    send_telegram_message "$message" "$ALERT_HIGH_LOAD"
}

# Function to format frequency alert message
send_freq_alert() {
    local frequency="$1"
    
    local message=" <b>UPS FREQUENCY ALERT</b> 
    
 <b>Input Frequency:</b> ${frequency}Hz
 <b>Issue:</b> Input frequency is abnormal
 <b>Possible Causes:</b> Generator or unstable mains
 Time: $(date '+%Y-%m-%d %H:%M:%S')"

    send_telegram_message "$message" "$ALERT_FREQ_ISSUE"
}

# Function to format temperature alert message
send_temp_alert() {
    local temperature="$1"
    
    local message=" <b>UPS TEMPERATURE ALERT</b> 
    
 <b>Current Temperature:</b> ${temperature}°C
 <b>Status:</b> UPS is running hot
 <b>Recommendation:</b> Check ventilation/cooling
 Time: $(date '+%Y-%m-%d %H:%M:%S')"

    send_telegram_message "$message" "$ALERT_HIGH_TEMP"
}

# Function to format flag alert message
send_flag_alert() {
    local flags="$1"
    local flag_bits=""
    
    # Convert to binary representation
    printf -v flag_bits "%08d" $(echo "obase=2; $flags" | bc)
    
    local message=" <b>UPS STATUS FLAG CHANGE</b>
    
 <b>Flags (Binary):</b> ${flag_bits}
 <b>Flag Interpretation:</b>
• Bit 7 (MSB): $([ ${flag_bits:0:1} -eq 1 ] && echo " Utility Fail" || echo " Utility OK")
• Bit 6: $([ ${flag_bits:1:1} -eq 1 ] && echo " Battery Low" || echo " Battery OK")
• Bit 5: $([ ${flag_bits:2:1} -eq 1 ] && echo " Bypass/Boost" || echo " Normal")
• Bit 4: $([ ${flag_bits:3:1} -eq 1 ] && echo " UPS Failed" || echo " UPS OK")
• Bit 3: $([ ${flag_bits:4:1} -eq 1 ] && echo " Test in Progress" || echo " No Test")
• Bit 2: $([ ${flag_bits:5:1} -eq 1 ] && echo " Shutdown Active" || echo " Normal")
• Bit 1: $([ ${flag_bits:6:1} -eq 1 ] && echo "Beeper On" || echo " Beeper Off")
• Bit 0 (LSB): $([ ${flag_bits:7:1} -eq 1 ] && echo " On Battery" || echo " On Mains")

 Time: $(date '+%Y-%m-%d %H:%M:%S')"

    send_telegram_message "$message" "$ALERT_FLAG_CHANGE"
}

# Main script logic
case "$1" in
    "phase")
        if [ $# -eq 4 ]; then
            send_phase_alert "$2" "$3" "$4"
        else
            echo "Usage: $0 phase <phase1> <phase2> <phase3>"
            exit 1
        fi
        ;;
    "load")
        if [ $# -eq 2 ]; then
            send_load_alert "$2"
        else
            echo "Usage: $0 load <load_percentage>"
            exit 1
        fi
        ;;
    "freq")
        if [ $# -eq 2 ]; then
            send_freq_alert "$2"
        else
            echo "Usage: $0 freq <frequency>"
            exit 1
        fi
        ;;
    "temp")
        if [ $# -eq 2 ]; then
            send_temp_alert "$2"
        else
            echo "Usage: $0 temp <temperature>"
            exit 1
        fi
        ;;
    "flag")
        if [ $# -eq 2 ]; then
            send_flag_alert "$2"
        else
            echo "Usage: $0 flag <flag_value>"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {phase|load|freq|temp|flag} [parameters]"
        echo "Examples:"
        echo "  $0 phase 121.8 121.8 0.0"
        echo "  $0 load 85"
        echo "  $0 freq 0.0"
        echo "  $0 temp 45.5"
        echo "  $0 flag 5"
        exit 1
        ;;
esac

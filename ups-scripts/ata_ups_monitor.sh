#!/bin/bash
DEVICE="/dev/ttyUSB0"

# Set serial parameters
sudo stty -F $DEVICE 2400 cs8 -cstopb -parenb -ixon -ixoff raw

echo "=============================================="
echo "    ATA Hipower UPS Monitor"
echo "=============================================="

# Get identification info
echo -ne "I\r" | sudo tee $DEVICE > /dev/null
sleep 0.5
ID_RESPONSE=$(timeout 2 sudo cat $DEVICE)
echo "Identification: $ID_RESPONSE"

echo ""
echo "=== Real-time Status ==="
echo "Press Ctrl+C to exit"
echo ""

while true; do
    # Get status
    echo -ne "Q1\r" | sudo tee $DEVICE > /dev/null
    sleep 0.5
    STATUS_RESPONSE=$(timeout 2 sudo cat $DEVICE)
    
    # Parse the status response
    if [[ "$STATUS_RESPONSE" =~ \(([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9.]+)\ ([0-9]+) ]]; then
        clear
        echo "=============================================="
        echo "    ATA Hipower UPS Monitor - $(date)"
        echo "=============================================="
        echo "Identification: $ID_RESPONSE"
        echo ""
        echo "=== Current Status ==="
        echo "Input Voltage Phase 1: ${BASH_REMATCH[1]} V"
        echo "Input Voltage Phase 2: ${BASH_REMATCH[2]} V" 
        echo "Input Voltage Phase 3: ${BASH_REMATCH[3]} V"
        echo "Load Level: ${BASH_REMATCH[4]} %"
        echo "Frequency: ${BASH_REMATCH[5]} Hz"
        echo "Battery Voltage: ${BASH_REMATCH[6]} V"
        echo "Temperature: ${BASH_REMATCH[7]} °C"
        echo "Status Flags: ${BASH_REMATCH[8]} (binary: $(echo "obase=2;${BASH_REMATCH[8]}" | bc))"
        
        # Decode status flags (common UPS status bits)
        FLAGS=${BASH_REMATCH[8]}
        echo ""
        echo "=== Status Interpretation ==="
        if [ $((FLAGS & 1)) -ne 0 ]; then echo "✓ Utility Power OK"; else echo "✗ Utility Power Failed"; fi
        if [ $((FLAGS & 2)) -ne 0 ]; then echo "✓ Battery Charging"; else echo "✗ Battery Not Charging"; fi
        if [ $((FLAGS & 4)) -ne 0 ]; then echo "⚠ Low Battery"; else echo "✓ Battery OK"; fi
        if [ $((FLAGS & 8)) -ne 0 ]; then echo "⚡ UPS Online"; else echo "🔌 UPS on Bypass"; fi
        if [ $((FLAGS & 16)) -ne 0 ]; then echo "🔧 Test in Progress"; fi
        if [ $((FLAGS & 32)) -ne 0 ]; then echo "🚨 Alarm Active"; fi
    else
        echo "Failed to parse status: $STATUS_RESPONSE"
    fi
    
    echo ""
    echo "Next update in 5 seconds..."
    sleep 5
done

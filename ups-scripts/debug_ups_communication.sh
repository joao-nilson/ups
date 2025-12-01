#!/bin/bash
DEVICE="/dev/ttyUSB0"

echo "=== UPS Communication Debug ==="
echo "Testing exact timing and response patterns..."
echo ""

sudo stty -F $DEVICE 2400 cs8 -cstopb -parenb raw

# Test 1: Single command with precise timing
echo "Test 1: Single command with 8-second wait"
sudo timeout 2 cat $DEVICE > /dev/null 2>&1  # Clear
echo -ne "Q1\r" | sudo tee $DEVICE > /dev/null
echo "Waiting 8 seconds for complete response..."
for i in {1..8}; do
    echo "Second $i:"
    RESPONSE=$(timeout 1 sudo cat $DEVICE)
    if [ -n "$RESPONSE" ]; then
        echo "  -> $RESPONSE"
    else
        echo "  -> (no data)"
    fi
done

echo ""
echo "Test 2: Multiple rapid commands"
for i in {1..3}; do
    echo "Attempt $i:"
    sudo timeout 1 cat $DEVICE > /dev/null 2>&1
    echo -ne "Q1\r" | sudo tee $DEVICE > /dev/null
    sleep 6
    RESPONSE=$(timeout 2 sudo cat $DEVICE)
    echo "  Response: $RESPONSE"
    echo "  Length: ${#RESPONSE} characters"
    echo ""
done

echo "=== Debug Complete ==="

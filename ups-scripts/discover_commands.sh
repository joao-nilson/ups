#!/bin/bash
DEVICE="/dev/ttyUSB0"

# Set to 2400 baud
sudo stty -F $DEVICE 2400 cs8 -cstopb -parenb -ixon -ixoff raw

echo "Testing single letter commands A-Z, 0-9..."
echo "=========================================="

# Test letters A-Z
for cmd in {A..Z}; do
    echo -ne "Testing: $cmd\r" | sudo tee $DEVICE
    sleep 1
    response=$(timeout 2 sudo cat $DEVICE | head -5)
    if [ -n "$response" ] && [ "$response" != "NAK" ]; then
        echo "COMMAND FOUND: '$cmd' -> $response"
    fi
done

# Test numbers 0-9
for cmd in {0..9}; do
    echo -ne "Testing: $cmd\r" | sudo tee $DEVICE
    sleep 1
    response=$(timeout 2 sudo cat $DEVICE | head -5)
    if [ -n "$response" ] && [ "$response" != "NAK" ]; then
        echo "COMMAND FOUND: '$cmd' -> $response"
    fi
done

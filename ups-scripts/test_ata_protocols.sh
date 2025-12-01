#!/bin/bash
DEVICE="/dev/ttyUSB0"

# Set to 2400 baud (we know this works)
sudo stty -F $DEVICE 2400 cs8 -cstopb -parenb -ixon -ixoff raw

echo "Testing different command formats at 2400 baud..."
echo "=================================================="

# Test 1: Simple commands with CR
for cmd in "Q1" "D" "I" "STAT" "STATUS" "#IDN?" "*IDN?" "VER" "INFO"; do
    echo "Testing: $cmd"
    echo -e "$cmd\r" | sudo tee $DEVICE
    sleep 2
    timeout 3 sudo cat $DEVICE | head -10
    echo "---"
done

# Test 2: Try binary/hex commands
echo "Testing binary commands..."
echo -ne "\x01\x03\x00\x00\x00\x01\x84\x0A" | sudo tee $DEVICE  # Modbus query
sleep 2
timeout 3 sudo cat $DEVICE | hexdump -C

# Test 3: Try just carriage return
echo "Testing carriage return only..."
echo -ne "\r" | sudo tee $DEVICE
sleep 2
timeout 3 sudo cat $DEVICE | head -10

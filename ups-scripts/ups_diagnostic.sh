#!/bin/bash
echo "=== UPS Diagnostic ==="
echo "1. Checking devices..."
ls -la /dev/ttyUSB*
echo ""

echo "2. Checking USB devices..."
lsusb | grep -i qinheng
echo ""

echo "3. Checking kernel messages..."
dmesg | grep -i ttyUSB | tail -5
echo ""

echo "4. Testing serial communication..."
DEVICE="/dev/ttyUSB1"

if [ -c "$DEVICE" ]; then
    echo "Device $DEVICE exists"
    sudo stty -F $DEVICE 2400 cs8 -cstopb -parenb
    
    echo "Testing 'I' command..."
    sudo timeout 1 cat $DEVICE > /dev/null  # Clear buffer
    echo -ne "I\r" | sudo tee $DEVICE
    sleep 2
    RESPONSE=$(timeout 3 sudo cat $DEVICE)
    echo "Response: '$RESPONSE'"
    
    echo "Testing 'Q1' command..."
    sudo timeout 10 cat $DEVICE > /dev/null  # Clear buffer
    echo -ne "Q1\r" | sudo tee $DEVICE
    sleep 10
    RESPONSE=$(timeout 3 sudo cat $DEVICE)
    echo "Response: '$RESPONSE'"
else
    echo "ERROR: Device $DEVICE not found!"
fi

echo ""
echo "5. Checking log directory..."
ls -la /var/log/ups/ 2>/dev/null || echo "Log directory doesn't exist"

#!/bin/bash
DEVICE="/dev/ttyUSB0"
BAUD_RATES="1200 2400 4800 9600 19200 38400 57600 115200"

for baud in $BAUD_RATES; do
    echo "======================================"
    echo "Testing $baud baud rate..."
    echo "======================================"
    
    # Configure serial port
    sudo stty -F $DEVICE $baud cs8 -cstopb -parenb -ixon -ixoff
    
    # Send common UPS commands and listen for response
    echo -e "\r" | sudo tee $DEVICE
    sleep 1
    echo "Q1" | sudo tee $DEVICE
    sleep 1
    echo "STATUS" | sudo tee $DEVICE
    sleep 1
    echo "Y" | sudo tee $DEVICE
    sleep 1
    
    # Listen for any response
    timeout 5 sudo cat $DEVICE | head -20
    echo
done

#!/bin/bash
DEVICE="/dev/ttyUSB0"
sudo stty -F $DEVICE 2400 cs8 -cstopb -parenb

while true; do
    clear
    echo "=== ATA Hipower UPS Monitor ==="
    echo "Last update: $(date)"
    echo ""
    
    # Get status
    echo -ne "Q1\r" | sudo tee $DEVICE > /dev/null
    sleep 1
    status=$(timeout 2 sudo cat $DEVICE)
    echo "Status: $status"
    
    # Get identification
    echo -ne "I\r" | sudo tee $DEVICE > /dev/null
    sleep 1
    id=$(timeout 2 sudo cat $DEVICE)
    echo "ID: $id"
    
    sleep 5
done

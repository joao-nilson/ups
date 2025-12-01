#!/bin/bash
DEVICE="/dev/ttyUSB0"
sudo stty -F $DEVICE 2400 cs8 -cstopb -parenb

# Test two-character commands
commands=("Q2" "Q3" "Q4" "Q5" "Q6" "Q7" "Q8" "Q9" "QS" "QB" "QT" "QV" "QF" "QL" "ST" "RS" "TE" "DI" "DA")

for cmd in "${commands[@]}"; do
    echo -ne "Testing: $cmd\r" | sudo tee $DEVICE
    sleep 1
    response=$(timeout 2 sudo cat $DEVICE | head -5)
    echo "Command: $cmd -> $response"
    echo "---"
done

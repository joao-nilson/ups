#!/usr/bin/env python3
import pip
import time
import datetime
import sys
import subprocess
import sqlite3

try:
    import serial 
    from serial import Serial, SerialException
except ImportError:
    print("pyserial not installed correctly")
    sys.exit(1)

#Compilation&Execution:
#   gcc -o ups_mon ups_monitor.c -I/usr/include/python3.9 -lpython3.9
#   python ups_reader.py


def main():
    #list devices
    dev_output = subprocess.check_output(['ls', '/dev'], text=True)
    #filter for serial devices and if there is mode than one serial device conected, select the first one
    serial_devices = [line for line in dev_output.splitlines() if 'ttyUSB' in line]
    if serial_devices:
        device = f'/dev/{serial_devices[0]}'
        print(f"Selected serial device: {device}")
    else:
        print("No serial device found")

    log_dir = '/var/log/ups/'
    
    try:
        # Configure serial port
        ser = serial.Serial(
            port=device,
            baudrate=2400,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=2,
            xonxoff=False,
            rtscts=False
        )
        
        print(f"Connected to {device}")
        
        while True:
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            
            # Clear buffer
            ser.reset_input_buffer()
            
            # Send command
            ser.write(b'Q1\r')
            time.sleep(0.5)
            
            # Read response with multiple attempts
            full_response = ""
            for attempt in range(10):
                try:
                    chunk = ser.read_all().decode('ascii', errors='ignore')
                    if chunk:
                        full_response += chunk
                        print(f"Chunk {attempt}: {chunk.strip()}")
                    time.sleep(0.5)
                except Exception as e:
                    print(f"Read error: {e}")
                
                # Check if we have complete data
                if full_response.count(' ') >= 7:  # Should have 8 values = 7 spaces
                    break
            
            print(f"Full response: {full_response}")
            
            # Start the C program as a subprocess
            process = subprocess.Popen(["./ups_db"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)

            # Send the full_response to C program
                #use stdin to send full response
            process.stdin.write(full_response)
            process.stdin.flush()
            process.stdin.close()

                #get output
            stdout = process.stdout.read()
            stderr = process.stderr.read()

            # Print output from C program
            print("C program output:", stdout)
            if stderr:
                print("C program error:", stderr)
            
            conn = sqlite3.connect('/var/log/ups/ups-log.db')
            cursor = conn.cursor()

            #create table if not exist
            cursor.execute("""CREATE TABLE IF NOT EXISTS status(timestamp TEXT, vphase1 TEXT, vphase2 TEXT, vphase3 TEXT, load TEXT, frequency TEXT, vbattery TEXT, temperature TEXT, flags TEXT)""")

            # Parse response
            if '(' in full_response and full_response.count(' ') >= 7:
                try:
                    # Extract values between parentheses
                    start = full_response.index('(') + 1
                    end = full_response.index(')') if ')' in full_response else len(full_response)
                    data_str = full_response[start:end].strip()
                    values = data_str.split()
                    
                    if len(values) >= 8:
                        v1, v2, v3, load, freq, batt, temp, flags = values[:8]
                        line = f"{timestamp},{v1},{v2},{v3},{load},{freq},{batt},{temp},{flags}"
                        print(f"PARSED: {line}")
                        try:
                            cursor.execute(
                                "INSERT INTO status VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                (timestamp, v1, v2, v3, load, freq, batt, temp, flags)
                            )
                            conn.commit()
                        except Exception as e:
                            print("SQLite error: did not write to bd (full)")
                    elif len(values) >= 6:
                        v1, v2, v3, load, freq, batt = values[:6]
                        line = f"{timestamp},{v1},{v2},{v3},{load},{freq},{batt},UNKNOWN,UNKNOWN"
                        print(f"PARTIAL: {line}")
                        try:
                            cursor.execute(
                                "INSERT INTO status VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                (timestamp, v1, v2, v3, load, freq, batt, "UNKNOWN", "UNKNOWN")
                            )
                            conn.commit()
                        except Exception as e:
                            print("SQLite error: did not write to db (6val)")
                    else:
                        print(f"INCOMPLETE: Only {len(values)} values")
                        try:
                            cursor.execute(
                                "INSERT INTO status VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                (timestamp, "UNKNOWN", "UNKNOWN", "UNKNOWN", "UNKNOWN", "UNKNOWN", "UNKNOWN", "UNKNOWN", "UNKNOWN")
                            )
                            conn.commit()
                        except Exception as e:
                            print("SQLite did not write to db")

                except Exception as e:
                    print("Could not parse response")


            conn.close()                    
            print(f"Waiting 30 seconds... ({datetime.datetime.now().strftime('%H:%M:%S')})")
            print("="*50)
            time.sleep(30)
            
    except serial.SerialException as e:
        print(f"Serial port error: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        print("Stopped by user")
        if 'ser' in locals():
            ser.close()

if __name__ == "__main__":
    main()



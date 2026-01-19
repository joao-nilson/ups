#include <Python.h>	
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string.h>
#include <time.h>
#include <stdbool.h>

#define SCRIPT_DIR "./alerts"
#define PHASE_ALERT_SCRIPT SCRIPT_DIR "phases_alert.sh"
#define LOAD_ALERT_SCRIPT SCRIPT_DIR "load_alert.sh"
#define FREQ_ALERT_SCRIPT SCRIPT_DIR "freq_alert.sh"
#define TEMP_ALERT_SCRIPT SCRIPT_DIR "temp_alert.sh"
#define FLAG_ALERT_SCRIPT SCRIPT_DIR "flag_alert.sh"

typedef struct {
    char *serial_response;
    char *tokens[8];
    int token_count;
    int is_valid;
} ups_d;

//constructor
void init_ups_d(ups_d *ups) {
    ups->serial_response = NULL;
    for(int i = 0; i < 8; i++)
	    ups->tokens[i] = NULL;
    ups->token_count = 0;
    ups->is_valid = false;
}

//destructor
void cleanup_ups_d(ups_d *ups) {
    if (ups->serial_response != NULL) {
        free(ups->serial_response);
	ups->serial_response = NULL;
    }
    for(int i = 0; i<ups->token_count && i<8; i++)
        if(ups->tokens[i] != NULL) {
	    free(ups->tokens[i]);
	    ups->tokens[i] = NULL;
	}
    ups->token_count = 0;
    ups->is_valid = false;
}

char * py_input(){
    char *buffer = malloc(1024);
    if(buffer == NULL){
        printf("ERROR(ups_db.c): Failed to alocate buffer for python serial responce");
	return NULL;
    }

    size_t bytes_read = 0;
    int counter;

    while(bytes_read < 1023 && (counter = getchar()) != EOF && counter != '\n') {
    	buffer[bytes_read++] = counter;
    }
    buffer[bytes_read] = '\0';

    if(bytes_read > 0) {
    	printf("Reveived response: %s\n", buffer);
    	return buffer;
    } else {
    	printf("No response received");
	free(buffer);
        return NULL;
    }
    return buffer;
}

int parse_serial(ups_d *ups, int num_tokens) {
    if (ups->serial_response == NULL) {
        printf("Error: No serial response to parse");
        return -1;
    }

    //size of the string of serial response
    char buffer[1024];
    int j = 0;

    //copy serial response to buffer without parenthesis
    if(ups->serial_response[0] == '(')
    {
        for(int i = 1; i < strlen(ups->serial_response) && ups->serial_response[i] != ')'; i++)
	{
	    buffer[j++] = ups->serial_response[i];
	}
	buffer[j] = '\0';
    }
    else
    	strcpy(buffer, ups->serial_response);
    
    printf("Parsing buffer: %s\n", buffer);

    //parse tokens
    int token_count = 0;
    char *token = strtok(buffer, " ");
    while(token != NULL && token_count < num_tokens) {
        ups->tokens[token_count] = malloc(strlen(token) + 1);
        if(ups->tokens[token_count] == NULL) {
            printf("Error allocating memory for token\n");
            return -1;
        }
        strcpy(ups->tokens[token_count], token);
        printf("Token %d: %s\n", token_count, ups->tokens[token_count]);
        token_count++;
        token = strtok(NULL, " ");
    }

    return token_count;
}

int acquire_serial_data(ups_d *ups) {
    init_ups_d(ups);

    ups->serial_response = py_input();
    if(ups->serial_response == NULL) {
	ups->is_valid = false;
        return 0;
    }

    ups->token_count = parse_serial(ups, 8);

    if (ups->token_count != 8) {
        printf("Error: Expected 8 tokens, got: %i \0", ups->token_count);
	printf("Data format should be: voltage1 voltage2 voltage3 load freq battery temp status\n");
	ups->is_valid = false;
	return 0;
    }

    ups->is_valid = true;
    return 1;
}

void print_ups_data(ups_d *ups) {
    if (ups->is_valid == false){
	printf("No valid UPS response available\n");
	return;
    }
    printf("Serial response: %s \n", ups->serial_response);
    printf("Number of tokens: %i \n", ups->token_count);
    for(int i = 0; i < ups->token_count && i < 8; i++)
        printf("Token %i: %s \n", i, ups->tokens[i]);
}

int execute_script_with_input(const char *script_path, const char *input_data) {
    char command[512];
    FILE *fp;
    int result;

    // Create command to pipe input to script
    snprintf(command, sizeof(command), "echo \"%s\" | %s", input_data, script_path);

    printf("Executing: %s\n", command);

    // Execute the command
    result = system(command);

    if (result == -1) {
        printf("Error executing script: %s\n", script_path);
        return -1;
    }

    return result;
}

int is_phase_down(float phase_voltage) {
    return (phase_voltage == 0.0);
}



//maybe switch to void and instead of returning sens is_ok to the telegram alert logic
//to be implemented: phases_aler.yml on alertmanager and telegram_bot
void triphase_status(ups_d *ups) {
    float phases[3];
    int phases_down_count = 0;
    char input_data[256];

    for(int i = 0; i < 3; i++) {
	phases[i] = strtof(ups->tokens[i], NULL);
	if (is_phase_down(phases[i])) {
	    printf("Phase %i is down: %.1fV\n", i);
	    phases_down_count++;
	}
    
    }

    if (phases_down_count > 0) {
        snprintf(input_data, sizeof(input_data), "%.1f %.1f %.1f", phases[0], phases[1], phases[2]);
        execute_script_with_input(PHASE_ALERT_SCRIPT, input_data);
    } else {
        printf("All phases OK: %.1fV, %.1fV, %.1fV\n", phases[0], phases[1], phases[2]);
    }

}

// awk -F',' '{print $5}' logs/ups_data.csv.1
// ^
// |
// command to list load values of the csv files
int high_load(ups_d *ups) {
    char input_data[64];
    int load = atoll(ups->tokens[3]);
    snprintf(input_data, sizeof(input_data), "%.0f", load);
    printf("Load: %.0f%%\n", load);

    execute_script_with_input(LOAD_ALERT_SCRIPT, input_data);
//    if (load >= 70)
//	    printf("High nobreak load: %f%\n", load);
//    //send load value to its alert
//    return load;
}

void check_frequency_and_alert(ups_d *ups) {
    float frequency;
    char input_data[64];

    frequency = strtof(ups->tokens[4], NULL);
    snprintf(input_data, sizeof(input_data), "%.1f", frequency);

    printf("Frequency: %.1f Hz\n", frequency);

    // Check for abnormal frequency (0 Hz or outside normal range)
    if (frequency == 0.0 || frequency < 58.0 || frequency > 62.0) {
        execute_script_with_input(FREQ_ALERT_SCRIPT, input_data);
    }
}

void check_temperature_and_alert(ups_d *ups) {
    float temperature;
    char input_data[64];

    temperature = strtof(ups->tokens[6], NULL);
    snprintf(input_data, sizeof(input_data), "%.1f", temperature);

    printf("Temperature: %.1f°C\n", temperature);

    // Always send temperature to script (script decides if alert is needed)
    execute_script_with_input(TEMP_ALERT_SCRIPT, input_data);
}

void check_flags_and_alert(ups_d *ups) {
    char *flag_string = ups->tokens[7];
    char input_data[64];

    // Remove any whitespace or newlines from flag string
    char *flag_clean = flag_string;
    while (*flag_clean && (*flag_clean == ' ' || *flag_clean == '\n' || *flag_clean == '\r')) {
        flag_clean++;
    }

    // Copy only the first 8 characters (binary flag string)
    char flag_bits[9] = {0};
    strncpy(flag_bits, flag_clean, 8);
    flag_bits[8] = '\0';

    printf("Status flags: %s\n", flag_bits);

    // Convert binary string to decimal for the script
    long flag_decimal = strtol(flag_bits, NULL, 2);
    snprintf(input_data, sizeof(input_data), "%ld", flag_decimal);

    // Always send flags to script (script tracks changes)
    execute_script_with_input(FLAG_ALERT_SCRIPT, input_data);
}

// Parse and display flags (optional, for debugging)
void parse_and_display_flags(ups_d *ups) {
    char *flag_string = ups->tokens[7];

    // Remove any whitespace
    char *flag_clean = flag_string;
    while (*flag_clean && (*flag_clean == ' ' || *flag_clean == '\n' || *flag_clean == '\r')) {
        flag_clean++;
    }

    printf("\n=== UPS Status Flags Analysis ===\n");
    printf("Raw flags: %s\n", flag_clean);

    if (strlen(flag_clean) >= 8) {
        printf("Bit 7 (Utility): %c - %s\n", flag_clean[0], flag_clean[0] == '1' ? " Utility Fail" : " Utility OK");
        printf("Bit 6 (Battery): %c - %s\n", flag_clean[1], flag_clean[1] == '1' ? " Battery Low" : " Battery OK");
        printf("Bit 5 (Boost): %c - %s\n", flag_clean[2], flag_clean[2] == '1' ? " Bypass/Boost" : " Normal");
        printf("Bit 4 (UPS): %c - %s\n", flag_clean[3], flag_clean[3] == '1' ? " UPS Failed" : " UPS OK");
        printf("Bit 3 (Test): %c - %s\n", flag_clean[4], flag_clean[4] == '1' ? " Test in Progress" : " No Test");
        printf("Bit 2 (Shutdown): %c - %s\n", flag_clean[5], flag_clean[5] == '1' ? " Shutdown Active" : " Normal");
        printf("Bit 1 (Beeper): %c - %s\n", flag_clean[6], flag_clean[6] == '1' ? " Beeper On" : " Beeper Off");
        printf("Bit 0 (Power): %c - %s\n", flag_clean[7], flag_clean[7] == '1' ? " On Battery" : " On Mains");
    }
    printf("================================\n\n");
}


float get_freq(ups_d *ups) {
    float hz = strtof(ups->tokens[4], NULL);
    return hz;
}

float get_bat_v(ups_d *ups) {
    float v = strtof(ups->tokens[5], NULL);
    return v;
}

float get_temp(ups_d *ups) {
    float t = strtof(ups->tokens[6], NULL);
    return t;
}

//f = 00000001
//  = 10000001
//    ^^^^^^^^
//    ||||||||
//    |||||||bit0 (least significant)
//    ||||||bit1
//    |||||bit2
//    ||||bit3
//    |||bit4
//    ||bit5
//    |bit6
//    bit7 (most significant)
//void flags(char *f, int n) {
//    //f = {7,6,5,4,3,2,1,0}
//    //so, f[0] is the most significant bit
//    //and f[7] is the least significant bit
//    switch(f) {
//	case f[7] != 1: //f0
//	    printf("NOBREAK FLAG UP: Utility power not ok");
//	    break;
//	case f[6] != 0: //f1
//	    printf("NOBREAK FLAG UP: Charging battery");
//	    break;
//	case f[5] != 0: //f2
//	    printf("NOBREAK FLAG UP: Low battery");
//	    break;
//	case f[4] != 0: //f3
//	    printf("NOBREAK FLAG UP: Nobreak mode - offline");
//	    break;
//	case f[3] != 0: //f4
//	    printf("NOBREAK FLAG UP: Test mode active, test in progress");
//	    break;
//	case f[2] != 0: //f5
//	    printf("NOBREAK FLAG UP: Alarm active");
//	    break;
//	case f[1] != 0: //f6
//	    printf("NOBREAK FLAG UP: FLAG-6 unknown meaning");
//	    break;
//        case f[0] != 0: //f7
//            printf("NOBREAK FLAG UP: No power input");
//	    break;
//	default:
//	    printf("NOBREAK FLAG UP: Utility power ok");
//	    printf("NOBREAK FLAG UP: Battery not charging");
//	    printf("NOBREAK FLAG UP: Battery not low");
//	    printf("NOBREAK FLAG UP: Nobreak mode - online");
//	    printf("NOBREAK FLAG UP: Test mode inactive");
//	    printf("NOBREAK FLAG UP: Alarm inactive");
//	    printf("NOBREAK FLAG UP: FLAG-6 unknown meaning");
//	    printf("NOBREAK FLAG UP: Power input OK");
//	    break;
//    }
//}

int main() {
    ups_d ups_data;

    if (!acquire_serial_data(&ups_data)) {
        printf("Failed to acquire serial data\n");
        return 1;
    }

    triphase_status(&ups_data);
    high_load(&ups_data);
    check_frequency_and_alert(&ups_data);
    check_temperature_and_alert(&ups_data);
    check_flags_and_alert(&ups_data);
    get_bat_v(&ups_data);
    parse_and_display_flags(&ups_data);

    print_ups_data(&ups_data);
    

    cleanup_ups_d(&ups_data);
    printf("Data processing completed\n");

    return 0;
}


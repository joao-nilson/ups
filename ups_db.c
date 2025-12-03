#include <Python.h>	
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string.h>
#include <time.h>
#include <stdbool.h>

//TODO:
//	- logic to understant each value (probably in new file)
//	- integrate with telegram bot
//	- put everything in a github repo (low priority)

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


//maybe switch to void and instead of returning sens is_ok to the telegram alert logic
//to be implemented: phases_aler.yml on alertmanager and telegram_bot
bool triphase_status(ups_d *ups) {
    float phases[3];
    for(int i = 0; i < 3; i++)
	    phases[i] = strtof(ups->tokens[i]);
    
    bool is_ok = true;
    
    if (phases[0] == 0.0 || phases[1] == 0.0 || phases[2] == 0.0) {
        is_ok = false;
	printf("One or more input phases is 0.\n
		Power input is down.\n");
    }
    return is_ok;
}

// awk -F',' '{print $5}' logs/ups_data.csv.1
// ^
// |
// command to list load values of the csv files
int high_load(ups_d *ups) {
    int load = atoll(ups->tokens[3]);
    if (load >= 70)
	    printf("High nobreak load: %f%\n", load);
    //send load value to its alert
    return load;
}

float get_freq(ups_d *ups) {
    float hz = strtof(ups->tokens[4]);
    return hz;
}

float get_bat_v(ups_d *ups) {
    float v = strtof(ups->tokens[5]);
    return v;
}

float get_temp(ups_d *ups) {
    float t = strtof(ups->tokens[6]);
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
void flags(char *f, int n) {
    //f = {7,6,5,4,3,2,1,0}
    //so, f[0] is the most significant bit
    //and f[7] is the least significant bit
    switch(f) {
	case f[7] != 1: //f0
	    printf("NOBREAK FLAG UP: Utility power not ok");
	    break;
	case f[6] != 0: //f1
	    printf("NOBREAK FLAG UP: Charging battery");
	    break;
	case f[5] != 0: //f2
	    printf("NOBREAK FLAG UP: Low battery");
	    break;
	case f[4] != 0: //f3
	    printf("NOBREAK FLAG UP: Nobreak mode - offline");
	    break;
	case f[3] != 0: //f4
	    printf("NOBREAK FLAG UP: Test mode active, test in progress");
	    break;
	case f[2] != 0: //f5
	    printf("NOBREAK FLAG UP: Alarm active");
	    break;
	case f[1] != 0: //f6
	    printf("NOBREAK FLAG UP: FLAG-6 unknown meaning");
	    break;
        case f[0] != 0: //f7
            printf("NOBREAK FLAG UP: No power input");
	    break;
	default:
	    printf("NOBREAK FLAG UP: Utility power ok");
	    printf("NOBREAK FLAG UP: Battery not charging");
	    printf("NOBREAK FLAG UP: Battery not low");
	    printf("NOBREAK FLAG UP: Nobreak mode - online");
	    printf("NOBREAK FLAG UP: Test mode inactive");
	    printf("NOBREAK FLAG UP: Alarm inactive");
	    printf("NOBREAK FLAG UP: FLAG-6 unknown meaning");
	    printf("NOBREAK FLAG UP: Power input OK");
	    break;
    }
}

int main() {
    ups_d ups_data;

    if (!acquire_serial_data(&ups_data)) {
        printf("Failed to acquire serial data\n");
        return 1;
    }
    
    //print_ups_data(&ups_data);
    //Treat tokens:
    triphase_status(&ups_data);
    int load = high_load(); // if the load gets bigger, send alert
    float frequency = get_freq(&ups_data); // if input line frequency == 0, send alert
    float temp = get_temp(); // monitor nobreak temp and alert if gets high
    
    flags(ups_data.tokens[7], 8); // if a flag changes status send out a alert


    cleanup_ups_d(&ups_data);
    printf("Data processing completed\n");

    return 0;
}


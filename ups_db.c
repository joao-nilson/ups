#include <Python.h>	
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>
#include <string.h>
#include <time.h>
#include <stdbool.h>

//TODO:
//	- logic to understant each value (probably in new file)
//	- integrate with telegram bot
//	- put everything in a github repo (low priority)

char * py_input(){
    char *buffer = malloc(1024);
    if(buffer == NULL){
        printf("ERROR(ups_db.c): Failed to alocate buffer for python serial responce");
	return NULL;
    }

    size_t bytes_read = 0;
    int counter;

    while(bytes_read < 2023 && (counter = getchar()) != EOF && counter != '\n') {
    	buffer[bytes_read++] = counter;
    }
    buffer[bytes_read] = '\0';


// if (fgets(buffer, 1024, stdin) != NULL) {
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

int parse_serial(char serial_data[], char *tokens[], int num_tokens) {
    //size of the string of serial response
    char buffer[1024];
    int j = 0;

    //copy serial response to buffer without parenthesis
    if(serial_data[0] == '(')
    {
        for(int i = 1; i < strlen(serial_data) && serial_data[i] != ')'; i++)
	{
	    buffer[j++] = serial_data[i];
	}
	buffer[j] = '\0';
    }
    else
    	strcpy(buffer, serial_data);
    
    printf("Parsing buffer: %s\n", buffer);

    //parse tokens
    int token_count = 0;
    char *token = strtok(buffer, " ");
    while(token != NULL && token_count < num_tokens) {
        tokens[token_count] = malloc(strlen(token) + 1);
        if(tokens[token_count] == NULL) {
            printf("Error allocating memory for token\n");
            return -1;
        }
        strcpy(tokens[token_count], token);
        printf("Token %d: %s\n", token_count, tokens[token_count]);
        token_count++;
        token = strtok(NULL, " ");
    }

    return token_count;
}

char * get_timestamp()
{
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    char *timestamp = malloc(64);
    strftime(timestamp, sizeof(timestamp), "%d-%m-%Y %H:%M:%S", t);
    return timestamp;
}

int main() {
    //reveive serial data response from python program
    char *status_response = py_input();
    if(status_response == NULL) {
        return 1;
    }

    char *parsed_tokens[9];
    int token_count = parse_serial(status_response, parsed_tokens, 11);
    
    if(token_count != 8) {
        printf("Error: Expected exactly 8 tokens from serial response, got %d\n", token_count);
        printf("Data format should be: voltage1 voltage2 voltage3 load freq battery temp status\n");
        free(status_response);
        for(int i = 0; i < token_count; i++)
            free(parsed_tokens[i]);
	return 1;
    }


    sqlite3 *db;
    //Open database
    int rc = sqlite3_open("/var/log/ups/logs-sqlite.db", &db);
    if (rc != SQLITE_OK)
    {
        fprintf(stderr,"Error: Cannot open database: %s\n", sqlite3_errmsg(db));
//	free_db(db, status_response, parsed_tokens, token_count, 1);
	free(status_response);
	for(int i = 0; i < token_count; i++) {
            free(parsed_tokens[i]);
        }
	return 1;
    }
    
    const char *sql = "CREATE TABLE IF NOT EXISTS status ("
	    	      "timestamp TEXT, "
		      "voltage_phase1 TEXT, "
		      "voltage_phase2 TEXT, "
		      "voltage_phase3 TEXT, "
		      "load_percent TEXT, "
		      "frequency TEXT, "
		      "battery_voltage TEXT, "
		      "temperature TEXT, "
		      "status_flags TEXT);";
    rc = sqlite3_exec(db, sql, NULL, NULL, NULL);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Failed to create table: %s\n", sqlite3_errmsg(db));
//	free_db(db, status_response, parsed_tokens, token_count, 0);
        sqlite3_close(db);
        free(status_response);
        for(int i = 0; i < token_count; i++) {
            free(parsed_tokens[i]);
        }
	return 1;
    }


    //Prepare sql statement
    sqlite3_stmt *stmt;
    const char *insert_sql = "INSERT INTO status (timestamp, voltage_phase1, voltage_phase2, voltage_phase3, load_percent, frequency, battery_voltage, temperature, status_flags) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
    
    rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Failed to prepare statement: %s\n", sqlite3_errmsg(db));
//	free_db(db, status_response, parsed_tokens, token_count, 0);
        sqlite3_close(db);
        free(status_response);
        for(int i = 0; i < token_count; i++) {
            free(parsed_tokens[i]);
        }
        return 1;
    }

    char *timestamp = get_timestamp();
    sqlite3_bind_text(stmt, 1, timestamp, -1, SQLITE_STATIC);

    //Bind values to parameters
    //sqlite3_bind_text(stmt, 1, "some text", -1, SQLITE_STATIC);
    //		statement,first colum, text, idk, idk
    for(int i = 0; i < 8; i++)
    {
        if(i < token_count && parsed_tokens[i] != NULL) {
            sqlite3_bind_text(stmt, i + 2, parsed_tokens[i], -1, SQLITE_STATIC);
        } else {
            sqlite3_bind_null(stmt, i + 2);
        }

    }
    
    //Execute statement
    rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
	fprintf(stderr, "Execution failed: %s\n", sqlite3_errmsg(db));
	sqlite3_finalize(stmt);
        sqlite3_close(db);
        free(status_response);
        for(int i = 0; i < token_count; i++) {
            free(parsed_tokens[i]);
        }

	return 1;
    }

    //Finalize statement
    sqlite3_finalize(stmt);
    //close db
    sqlite3_close(db);

//    free_db(db, status_response, parsed_tokens, token_count, 1);
    free(status_response);
    for(int i = 0; i < token_count; i++) {
        free(parsed_tokens[i]);
    }

    printf("Data successfully inserted into database\n");

    return 0;
}


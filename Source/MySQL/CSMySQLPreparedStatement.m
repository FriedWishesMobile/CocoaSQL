//
//  CSMySQLPreparedStatement.m
//  CocoaSQL
//
//  Created by xant on 4/6/10.
//  Copyright 2010 CocoaSQL.org. All rights reserved.
//

#import "CSMySQLPreparedStatement.h"
#import "CSMySQLDatabase.h"
#import "CSQLBindValue.h"
#include <mysql_time.h>

static id translate(MYSQL_BIND *bind)
{
    id value = nil;
    MYSQL_TIME *dt = NULL;
    time_t time = 0;
    struct tm ut;

    // XXX - actual implementation uses only strings and blobs
    switch(bind->buffer_type)
    {
        case MYSQL_TYPE_FLOAT:
            value = [NSNumber numberWithFloat:*((float *)bind->buffer)];
            break;
        case MYSQL_TYPE_SHORT:
            value = [NSNumber numberWithShort:*((short *)bind->buffer)];
            break;
        case MYSQL_TYPE_LONG:
            value = [NSNumber numberWithLong:*((long *)bind->buffer)];
            break;
        case MYSQL_TYPE_INT24:
            value = [NSNumber numberWithLongLong:*((int *)bind->buffer)];
            break;
        case MYSQL_TYPE_LONGLONG:
            value = [NSNumber numberWithLongLong:*((long long *)bind->buffer)];
            break;
        case MYSQL_TYPE_DOUBLE:
            value = [NSNumber numberWithDouble:*((double *)bind->buffer)];
        case MYSQL_TYPE_TINY:
            value = [NSNumber numberWithChar:*((char *)bind->buffer)];
            break;
        case MYSQL_TYPE_DECIMAL:
            /* TODO - convert mysql type decimal */
             break;
        case MYSQL_TYPE_TIMESTAMP:
        case MYSQL_TYPE_DATETIME:
        case MYSQL_TYPE_DATE:
        case MYSQL_TYPE_TIME:
        case MYSQL_TYPE_YEAR:
        case MYSQL_TYPE_NEWDATE:
            // convert the MYSQL_TIME structure to epoch
            // so that we can than build an NSDate object on top of it
            dt = (MYSQL_TIME *)bind->buffer;
            memset(&ut, 0, sizeof(ut));
            ut.tm_year = dt->year-1900;
            ut.tm_mon = dt->month-1;
            ut.tm_mday = dt->day;
            ut.tm_hour = dt->hour;
            ut.tm_min = dt->minute;
            ut.tm_sec = dt->second;
            time = mktime(&ut);
            value = [NSDate dateWithTimeIntervalSince1970:time];
            break;
        // XXX - unsure if varchars are returned with a fixed-length of 3 bytes or as a string
        case MYSQL_TYPE_VARCHAR:
        case MYSQL_TYPE_VAR_STRING:
        case MYSQL_TYPE_STRING:
            value = [NSString stringWithUTF8String:(char *)bind->buffer];
            break;
        case MYSQL_TYPE_BIT:
            value = [NSNumber numberWithChar:*((char *)bind->buffer) & 0x01];
            break;
        case MYSQL_TYPE_TINY_BLOB:
        case MYSQL_TYPE_BLOB:
        case MYSQL_TYPE_LONG_BLOB:
            value = [NSData dataWithBytes:bind->buffer length:bind->buffer_length];
            break;
    }
    return value;
}

@implementation CSMySQLPreparedStatement

@synthesize statement;

#pragma mark -
#pragma mark Internal Binds storage management
- (MYSQL_BIND *)createResultBindsForFields:(MYSQL_FIELD *)fields Count:(int)columnCount
{
    numFields = columnCount;
    resultBinds = calloc(columnCount, sizeof(MYSQL_BIND));
    for (int i = 0; i < columnCount; i++) {
#if 0
        // everything apart blobs will be stringified
        if (fields[i].type == MYSQL_TYPE_BLOB || fields[i].type == MYSQL_TYPE_LONG_BLOB
            || fields[i].type == MYSQL_TYPE_TINY_BLOB)
        {
            resultBinds[i].buffer_type = MYSQL_TYPE_BLOB;
            resultBinds[i].buffer = calloc(1, MAX_BLOB_WIDTH);
            resultBinds[i].buffer_length = MAX_BLOB_WIDTH;
        } else {
            resultBinds[i].buffer_type = MYSQL_TYPE_STRING;
            resultBinds[i].buffer = calloc(1, 1024); // XXX 
            resultBinds[i].buffer_length = 1024;
        }
#else
        // more strict datatype mapping
        resultBinds[i].buffer_type = fields[i].type;
        switch(fields[i].type) {
            case MYSQL_TYPE_FLOAT:
                resultBinds[i].buffer = calloc(1, sizeof(float));
                break;
            case MYSQL_TYPE_SHORT:
                resultBinds[i].buffer = calloc(1, sizeof(short));
                break;
            case MYSQL_TYPE_LONG:
                resultBinds[i].buffer = calloc(1, sizeof(long));
                break;
            case MYSQL_TYPE_INT24:
                resultBinds[i].buffer = calloc(1, sizeof(int));
                break;
            case MYSQL_TYPE_LONGLONG:
                resultBinds[i].buffer = calloc(1, sizeof(long long));
                break;
            case MYSQL_TYPE_DOUBLE:
                resultBinds[i].buffer = calloc(1, sizeof(double));
            case MYSQL_TYPE_TINY:
                resultBinds[i].buffer = calloc(1, sizeof(char));
                break;
            case MYSQL_TYPE_DECIMAL:
                /* TODO - convert mysql type decimal */
                break;
                // XXX - unsure if varchars are returned with a fixed-length of 3 bytes or as a string
            case MYSQL_TYPE_VARCHAR:
            case MYSQL_TYPE_VAR_STRING:
            case MYSQL_TYPE_STRING:
                resultBinds[i].buffer = calloc(1, 1024); // perhaps oversized (isn't 256 max_string_size?)
                resultBinds[i].buffer_length = 1024;
                break;
            case MYSQL_TYPE_BIT:
                resultBinds[i].buffer = calloc(1, 1);
                break;
            case MYSQL_TYPE_TINY_BLOB:
            case MYSQL_TYPE_BLOB:
            case MYSQL_TYPE_LONG_BLOB:
                resultBinds[i].buffer = calloc(1, MAX_BLOB_WIDTH);
                resultBinds[i].buffer_length = MAX_BLOB_WIDTH;
                break;
                
            case MYSQL_TYPE_TIMESTAMP:
            case MYSQL_TYPE_DATETIME:
            case MYSQL_TYPE_DATE:
            case MYSQL_TYPE_TIME:
            case MYSQL_TYPE_NEWDATE:
#if 1
                // handle datetime & friends using the MYSQL_TIME structure
                resultBinds[i].buffer = calloc(1, sizeof(MYSQL_TIME));
                resultBinds[i].buffer_length = sizeof(MYSQL_TIME);
#else
                // handle dates as strings (mysql will convert them for us if we provide
                // a MYSQL_TYPE_STRING as buffer_type
                resultBinds[i].buffer_type = MYSQL_TYPE_STRING; // override the type
                // 23 characters for datetime strings of the type YYYY-MM-DD hh:mm:ss.xxx 
                // (assuming that microseconds will be supported soon or later)
                resultBinds[i].buffer = calloc(1, 23);
                resultBinds[i].buffer_length = 23;
#endif
                break;
        }
#endif
    }
    return resultBinds;
}

- (void)destroyResultBinds
{
    for (int i = 0; i < numFields; i++)
        free(resultBinds[i].buffer);
    free(resultBinds);
    resultBinds = nil;
    numFields = 0;
}

#pragma mark -
#pragma mark Initializers

- (id)initWithDatabase:(CSMySQLDatabase *)aDatabase error:(NSError **)error
{
    [super init];
    resultBinds = nil;
    numFields = 0;
    self.database = aDatabase;
    self.statement = mysql_stmt_init((MYSQL *)aDatabase.databaseHandle);
    if (!self.statement) {
        if (error) {
            NSMutableDictionary *errorDetail = [NSMutableDictionary dictionaryWithCapacity:1];
            [errorDetail setObject:[NSString stringWithFormat:@"%s", mysql_error((MYSQL *)database.databaseHandle)] 
                            forKey:@"errorMessage"];
            // XXX - which errorcode should be used here?
            *error = [NSError errorWithDomain:@"CSQLPreparedStatement" code:501 userInfo:errorDetail];
        }
        // XXX - I'm unsure if returning nil here is safe, 
        //       since an instance has been already alloc'd
        //       so if used with the idiom [[class alloc] init]
        //       the alloc'd pointer will be leaked
        return nil;
    }
    return self;
}

- (id)initWithDatabase:(CSMySQLDatabase *)aDatabase andSQL:(NSString *)sql error:(NSError **)error
{
    if ([self initWithDatabase:aDatabase]) {
        if (![self setSQL:sql error:error]) {
            mysql_stmt_close(statement);
            statement = nil;
            // XXX - I'm unsure if returning nil here is safe, 
            //       since an instance has been already alloc'd
            //       so if used with the idiom [[class alloc] init]
            //       the alloc'd pointer will be leaked
            return nil;
        }
        return self;
    }
    // same here
    return nil;
}

- (BOOL)setSQL:(NSString *)sql error:(NSError **)error
{
    int errorCode = mysql_stmt_prepare(statement, [sql UTF8String], [sql length]);
    if (errorCode != 0) {
        if (error) {
            NSMutableDictionary *errorDetail;
            errorDetail = [NSMutableDictionary dictionary];
            NSString *errorMessage = [NSString stringWithFormat:@"%s", 
                                      mysql_error((MYSQL *)database.databaseHandle)];
            [errorDetail setObject:errorMessage forKey:@"errorMessage"];
            *error = [NSError errorWithDomain:@"CSMySQL" code:errorCode userInfo:errorDetail];
        }
        return NO;
    }
    return YES;
}

- (void)dealloc
{
    if (self.statement)
        mysql_stmt_close(statement);
    if (resultBinds)
        [self destroyResultBinds];
    [super dealloc];
}

#pragma mark -
#pragma mark Execute messages

- (BOOL)executeWithValues:(NSArray *)values error:(NSError **)error
{
    unsigned long bindParameterCount = mysql_stmt_param_count(self.statement);

    if (bindParameterCount > 0) {
        MYSQL_BIND *params = calloc(bindParameterCount, sizeof(MYSQL_BIND));

        if (!values || [values count] < bindParameterCount) {
            NSMutableDictionary *errorDetail;
            errorDetail = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"Expected %i value(s), %i provided", bindParameterCount, [values count]], @"errorMessage", nil];
            *error = [NSError errorWithDomain:@"CSMySQL" code:100 userInfo:errorDetail];
            return NO;
        }
        
        long *lStorage = calloc(bindParameterCount, sizeof(long));
        int  lStorageCount = 0;
        double *dStorage = calloc(bindParameterCount, sizeof(double));
        int  dStorageCount = 0;
        BOOL success = NO;

        for (int i = 0; i < bindParameterCount; i++) {
            CSQLBindValue *value = [values objectAtIndex:i];
            switch ([value type]) {
                case CSQLInteger:
                    lStorage[lStorageCount] = [value longValue];
                    params[i].buffer_type = MYSQL_TYPE_LONG;
                    params[i].buffer = &lStorage[lStorageCount];
                    params[i].param_number = i;
                    lStorageCount++;
                    break;
                case CSQLDouble:
                    dStorage[lStorageCount] = [value doubleValue];
                    params[i].buffer_type = MYSQL_TYPE_DOUBLE;
                    params[i].buffer = &dStorage[dStorageCount];
                    dStorageCount++;
                    break;
                case CSQLText:
                    params[i].buffer_type = MYSQL_TYPE_STRING;
                    params[i].buffer = (void *)[[value stringValue] UTF8String]; // XXX
                    params[i].buffer_length = [[value stringValue] length];  // XXX
                    break;
                case CSQLBlob:
                    params[i].buffer_type = MYSQL_TYPE_BLOB;
                    params[i].buffer = (void *)[[value dataValue] bytes];
                    params[i].buffer_length = [[value dataValue] length];
                    break;
                case CSQLNull:
                    params[i].buffer_type = MYSQL_TYPE_NULL;
                    break;
                default:
                    break;
            }
        }

        if (mysql_stmt_bind_param(self.statement, params) == 0) {
            if (mysql_stmt_execute(self.statement) == 0) {
                canFetch = YES;
                success = YES;
            }
        }
        free(lStorage);
        free(dStorage);
        free(params);
        if (!success) {
            if (error) {
                NSMutableDictionary *errorDetail = [NSMutableDictionary dictionaryWithCapacity:1];
                NSString *errorMessage = [NSString stringWithFormat:@"%s", mysql_error(database.databaseHandle)];
                [errorDetail setObject:errorMessage forKey:@"errorMessage"];
                *error = [NSError errorWithDomain:@"CSMySQL" code:101 userInfo:errorDetail];
            }
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)execute:(NSError **)error
{
    return [self executeWithValues:nil error:error];
}

#pragma mark -
#pragma mark Fetch messages

- (void)fetchRowWithBinds:(MYSQL_BIND *)binds error:(NSError **)error
{
    if (mysql_stmt_bind_result(statement, binds) != 0) {
        canFetch = NO;
        if (error) {
            NSMutableDictionary *errorDetail;
            errorDetail = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                           [NSString stringWithFormat:@"%s", mysql_error(database.databaseHandle)], 
                           @"errorMessage", nil];
            *error = [NSError errorWithDomain:@"CSMySQL" code:101 userInfo:errorDetail];
        }
    }
    int ret = mysql_stmt_fetch(statement);
    if (ret != 0){
        canFetch = NO;
        // find a way to notify that data truncation happened
        if (error && ret != MYSQL_NO_DATA && ret != MYSQL_DATA_TRUNCATED) {  
            NSMutableDictionary *errorDetail;
            errorDetail = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                           [NSString stringWithFormat:@"%s", mysql_error(database.databaseHandle)], 
                           @"errorMessage", nil];
            *error = [NSError errorWithDomain:@"CSMySQL" code:102 userInfo:errorDetail];
        }
    }
    
}

- (NSArray *)fetchRowAsArray:(NSError **)error
{
    if (canFetch == NO) {
        return nil;
    }
    MYSQL_FIELD *fields = mysql_fetch_fields(mysql_stmt_result_metadata(statement));
    if (!resultBinds)
        resultBinds = [self createResultBindsForFields:fields Count:mysql_stmt_field_count(statement)];
    [self fetchRowWithBinds:resultBinds error:error];
    if (!canFetch) {
        [self destroyResultBinds];
        resultBinds = nil;
        numFields = 0;
        return nil;
    }
    NSMutableArray *row = [NSMutableArray arrayWithCapacity:numFields];
    for (int i = 0; i < numFields; i++) {
        // convert dates here (remember we are taking them out of mysql as strings, 
        // since conversion to NSDate is easier)
        [row addObject:translate(&resultBinds[i])];
    }
    return row;
}

- (NSDictionary *)fetchRowAsDictionary:(NSError **)error
{
    int i;
    NSMutableDictionary *row = nil;
    
    if (canFetch == NO)
        return nil;
    
    numFields = mysql_stmt_field_count(statement);
    MYSQL_FIELD *fields = mysql_fetch_fields(mysql_stmt_result_metadata(statement));
    if (!resultBinds)
        resultBinds = [self createResultBindsForFields:fields Count:mysql_stmt_field_count(statement)];

    [self fetchRowWithBinds:resultBinds error:error];
    if (canFetch) {
        row = [NSMutableDictionary dictionaryWithCapacity:numFields];
        for (i = 0; i < numFields; i++) 
            [row setObject:translate(&resultBinds[i]) forKey:[NSString stringWithFormat:@"%s", fields[i].name]];
    } else {
        [self destroyResultBinds];
        resultBinds = nil;
        numFields = 0;
        return nil;
    }
    return row;
}

- (int)affectedRows
{
    return mysql_stmt_affected_rows(statement);
}

@end

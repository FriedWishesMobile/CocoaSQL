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

static id translate(MYSQL_BIND *bind)
{
    id value;
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
            value = [NSNumber numberWithLongLong:*((long long *)bind->buffer)<<8];
            break;
        case MYSQL_TYPE_LONGLONG:
            value = [NSNumber numberWithLongLong:*((long long *)bind->buffer)];
            break;
        case MYSQL_TYPE_DOUBLE:
            value = [NSNumber numberWithDouble:*((double *)bind->buffer)];
        case MYSQL_TYPE_TINY:
            break;
        case MYSQL_TYPE_STRING:
            value = [NSString stringWithUTF8String:(char *)bind->buffer];
            break;
        case MYSQL_TYPE_BLOB:
            break;
    }
    return value;
}

@implementation CSMySQLPreparedStatement


- (id)initWithDatabase:(CSMySQLDatabase *)aDatabase
{
    self.database = aDatabase;
    statement = mysql_stmt_init([aDatabase MySQLDatabase]);
}
- (id)initWithDatabase:(CSMySQLDatabase *)aDatabase andSQL:(NSString *)sql error:(NSError **)error
{
    [super init];
    self.database = aDatabase;
    statement = mysql_stmt_init([aDatabase MySQLDatabase]);
    int errorCode = mysql_stmt_prepare(statement, [sql UTF8String], [sql length]);
    if (errorCode != 0) {
        NSMutableDictionary *errorDetail;
        errorDetail = [NSMutableDictionary dictionary];
        NSString *errorMessage = [NSString stringWithFormat:@"%s", mysql_error([aDatabase MySQLDatabase])];
        [errorDetail setObject:errorMessage forKey:@"errorMessage"];
        *error = [NSError errorWithDomain:@"CSMySQL" code:errorCode userInfo:errorDetail];
        return nil;
    }
    return self;
}


- (void)dealloc
{
    if (statement)
        mysql_stmt_close(statement);
    [super dealloc];
}

#pragma mark -
#pragma mark Execute messages

- (BOOL)executeWithValues:(NSArray *)values error:(NSError **)error
{
    unsigned long bindParameterCount = mysql_stmt_param_count(statement);

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

        if (mysql_stmt_bind_param(statement, params) == 0) {
            if (mysql_stmt_execute(statement) == 0) {
                canFetch = YES;
                success = YES;
            }
        }
        free(lStorage);
        free(dStorage);
        free(params);
        if (!success) {
            NSMutableDictionary *errorDetail = [NSMutableDictionary dictionaryWithCapacity:1];
            NSString *errorMessage = [NSString stringWithFormat:@"%s", mysql_error([(CSMySQLDatabase *)database MySQLDatabase])];
            [errorDetail setObject:errorMessage forKey:@"errorMessage"];
            *error = [NSError errorWithDomain:@"CSMySQL" code:101 userInfo:errorDetail];
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

- (NSArray *)fetchRowAsArray:(NSError **)error
{
    if (canFetch == NO) {
        return nil;
    }
    int columnCount = mysql_stmt_field_count(statement);
    MYSQL_BIND *resultBindings = calloc(columnCount, sizeof(MYSQL_BIND));
    mysql_stmt_bind_result(statement, resultBindings);
    mysql_stmt_fetch(statement);
    NSMutableArray *row = [NSMutableArray arrayWithCapacity:columnCount];
    for (int i = 0; i < columnCount; i++) {
        [row addObject:translate(&resultBindings[i])];
    }
    free(resultBindings);
    return row;
}

- (NSDictionary *)fetchRowAsDictionary:(NSError **)error
{
    int columnCount;
    //const char *columnName;
    id value;
    NSMutableDictionary *row;
    
    if (canFetch == NO) {
        return nil;
    }
    
    columnCount = mysql_stmt_field_count(statement);
    row = [NSMutableDictionary dictionaryWithCapacity:columnCount];
    MYSQL_BIND *resultBindings = calloc(columnCount, sizeof(MYSQL_BIND));
    mysql_stmt_bind_result(statement, resultBindings);
    mysql_stmt_fetch(statement);
    MYSQL_FIELD *fields = mysql_fetch_fields(mysql_stmt_result_metadata(statement));

    for (int i = 0; i < columnCount; i++) {
        value = translate(&resultBindings[i]);
        [row setObject:value forKey:[NSString stringWithFormat:@"%s", fields[i].name]];
        
    }
    free(resultBindings);
    return row;
}

- (int)affectedRows
{
    return mysql_stmt_affected_rows(statement);
}

@end

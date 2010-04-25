//
//
//  This file is part of CocoaSQL
//
//  CocoaSQL is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Lesser General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  CocoaSQL is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with CocoaSQL.  If not, see <http://www.gnu.org/licenses/>.
//
//  CSQLPostgreSQLPreparedStatement.h by Igor Sutton on 4/13/10.
//

#import "CSPostgreSQLDatabase.h"
#import "CSPostgreSQLPreparedStatement.h"
#import "CSQLResultValue.h"
#include <libpq-fe.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <string.h>
#include <libkern/OSByteOrder.h>

//
// TODO: Find the proper way to wire PostgreSQL basic data types.
//
#define BYTEAOID   17
#define CHAROID    18
#define TEXTOID    25
#define INT8OID    20
#define INT2OID    21
#define INT4OID    23
#define NUMERICOID 1700
#define VARCHAROID 1043

#define FLOAT4OID 700
#define FLOAT8OID 701

#define DATEOID        1082
#define TIMEOID        1083
#define TIMESTAMPOID   1114
#define TIMESTAMPTZOID 1184

@interface CSPostgreSQLBindsStorage : NSObject
{
    int numParams;
    int *paramTypes;
    int *paramLengths;
    int *paramFormats;
    char **paramValues;
    int resultFormat;
    
    CSPostgreSQLPreparedStatement *statement;
    
    PGresult *result;
}

@property (readonly, assign) int numParams;
@property (readonly, assign) int *paramTypes;
@property (readonly, assign) int *paramLengths;
@property (readonly, assign) int *paramFormats;
@property (readonly, assign) char **paramValues;
@property (readonly, assign) int resultFormat;

- (id)initWithStatement:(CSPostgreSQLPreparedStatement *)aStatement andValues:(NSArray *)values;
- (BOOL)bindValue:(id)aValue toColumn:(int)index;
- (BOOL)setValues:(NSArray *)values;

@end

@implementation CSPostgreSQLBindsStorage

@synthesize numParams;
@synthesize paramTypes;
@synthesize paramLengths;
@synthesize paramFormats;
@synthesize paramValues;
@synthesize resultFormat;

- (id)initWithStatement:(CSPostgreSQLPreparedStatement *)aStatement andValues:(NSArray *)values
{
    if ([self init]) {
        resultFormat = 1;
        statement = [aStatement retain];
        numParams = 0;
        paramValues = nil;
        paramLengths = nil;
        paramFormats = nil;
        paramTypes = nil;
        [self setValues:values];
    }
    return self;
}

- (BOOL)bindValue:(id)aValue toColumn:(int)index
{
    int type = PQftype(statement.statement, index);

    if ([[aValue class] isSubclassOfClass:[NSNumber class]]) {
        switch (type) {
            case FLOAT8OID:
                paramValues[index] = (char *)[aValue pointerValue];
                break;
            case FLOAT4OID:
                paramValues[index] = (char *)[aValue pointerValue];
                break;
            case INT2OID:
            case INT4OID:
            case INT8OID:
                *(paramValues[index]) = ((uint32_t)htonl(*((uint32_t *)[aValue pointerValue])));
                break;
            default:
                paramValues[index] = (char *)[[aValue stringValue] UTF8String];
                break;
        }        
    }
    else if ([[aValue class] isSubclassOfClass:[NSString class]]) {
        if (resultFormat) {
            paramFormats[index] = 1;
            paramLengths[index] = [aValue length];
            paramValues[index] = (char *)[[aValue dataUsingEncoding:NSUTF8StringEncoding] bytes];
        }
        else {
            paramValues[index] = (char *)[aValue cStringUsingEncoding:NSUTF8StringEncoding];
        }
    }
    else if ([[aValue class] isSubclassOfClass:[NSData class]]) {
        if (resultFormat) {
            paramFormats[index] = 1; // binary
            paramLengths[index] = [aValue length];
        }
        paramValues[index] = (char *)[aValue bytes];
    }
    else if ([[aValue class] isSubclassOfClass:[NSDate class]]) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        switch (type) {
            case DATEOID:
                [formatter setDateFormat:((CSPostgreSQLDatabase *)statement.database).dateStyle];
                break;
            case TIMEOID:
                [formatter setDateFormat:((CSPostgreSQLDatabase *)statement.database).timeStyle];
                break;
            case TIMESTAMPOID:
            case TIMESTAMPTZOID:
            default:
                [formatter setDateFormat:((CSPostgreSQLDatabase *)statement.database).timestampStyle];
                break;
        }
        paramValues[index] = (char *)[[formatter stringFromDate:aValue] UTF8String]; 
        [formatter release];
    }
    else if ([[aValue class] isSubclassOfClass:[NSNull class]]) {
        paramFormats[index] = 1;
        paramValues[index] = '\0';
    }
    
    return YES;
}

- (BOOL)setValues:(NSArray *)values
{
    if (!values)
        return NO;
    
    numParams = [values count];
    paramValues = malloc([values count] * sizeof(char *));
    paramLengths = calloc([values count], sizeof(int));
    paramFormats = calloc([values count], sizeof(int));
    paramTypes = calloc([values count], sizeof(int));
    
    for (int i = 0; i < [values count]; i++) {
        [self bindValue:[values objectAtIndex:i] toColumn:i];
    }
    
    return YES;
    
}

- (void)dealloc
{
    free(paramValues);
    free(paramLengths);
    free(paramFormats);
    free(paramTypes);
    [statement release];
    [super dealloc];
}

@end

@interface CSPostgreSQLRow : NSObject
{
    int row;
    int numFields;
    CSPostgreSQLPreparedStatement *statement;
}

@property (readwrite) int row;
@property (readonly) int numFields;
@property (readwrite,retain) CSPostgreSQLPreparedStatement *statement;

+ (id)rowWithStatement:(CSPostgreSQLPreparedStatement *)aStatement andRow:(int)index;
- (id)initWithStatement:(CSPostgreSQLPreparedStatement *)aStatement andRow:(int)index;
- (id)objectForColumn:(int)index;
- (id)nameForColumn:(int)index;
- (BOOL)isNull:(int)index;

@end

@implementation CSPostgreSQLRow

@synthesize row;
@synthesize numFields;
@synthesize statement;

+ (id)rowWithStatement:(CSPostgreSQLPreparedStatement *)aStatement andRow:(int)index
{
    return [[[self alloc] initWithStatement:aStatement andRow:index] autorelease];
}

- (id)initWithStatement:(CSPostgreSQLPreparedStatement *)aStatement andRow:(int)index
{
    if (self = [super init]) {
        self.row = index;
        self.statement = aStatement;
        numFields = PQnfields(statement.statement);
    }
    
    return self;
}

- (BOOL)isBinary:(int)index
{
    return PQfformat(statement.statement, index) == 1;
}

- (int)lengthForColumn:(int)index
{
    return PQgetlength(statement.statement, row, index);
}

- (int)typeForColumn:(int)index
{
    return PQftype(statement.statement, index);
}

- (char *)valueForColumn:(int)index
{
    return PQgetvalue(statement.statement, row, index);
}

- (BOOL)isNull:(int)index
{
    return (PQgetisnull(statement.statement, row, index) == 1);
}

- (id)objectForColumn:(int)index
{
    CSQLResultValue *aValue = nil;

    int length_ = [self lengthForColumn:index];
    char *value_ = [self valueForColumn:index];
    
    if ([self isNull:index]) {
        return [CSQLResultValue valueWithNull];
    }
    
    if ([self isBinary:index]) {

        static NSDate *POSTGRES_EPOCH_DATE = nil;
        
        if (!POSTGRES_EPOCH_DATE)
            POSTGRES_EPOCH_DATE = [NSDate dateWithString:@"2000-01-01 00:00:00 +0000"];
        
        union {
            float f;
            uint32_t i;
        } floatValue;

        union {
            double d;
            uint64_t i;
        } doubleValue;
        
        switch ([self typeForColumn:index]) {
            case BYTEAOID:
                aValue = [CSQLResultValue valueWithData:[NSData dataWithBytes:value_ length:length_]];
                break;
            case CHAROID:
            case TEXTOID:
            case VARCHAROID:
                aValue = [CSQLResultValue valueWithUTF8String:value_];
                break;
            case INT8OID:
                aValue = [CSQLResultValue valueWithNumber:[NSNumber numberWithLong:OSSwapConstInt64(*((uint64_t *)value_))]];
                break;
            case INT4OID:
                aValue = [CSQLResultValue valueWithNumber:[NSNumber numberWithInt:OSSwapConstInt32(*((uint32_t *)value_))]];
                break;
            case INT2OID:
                aValue = [CSQLResultValue valueWithNumber:[NSNumber numberWithShort:OSSwapConstInt16(*((uint16_t *)value_))]];
                break;
            case FLOAT4OID:
                floatValue.i = OSSwapConstInt32(*((uint32_t *)value_));
                aValue = [CSQLResultValue valueWithNumber:[NSNumber numberWithFloat:floatValue.f]];
                break;
            case FLOAT8OID:
                doubleValue.i = OSSwapConstInt64(*((uint64_t *)value_));
                aValue = [CSQLResultValue valueWithNumber:[NSNumber numberWithDouble:doubleValue.d]];
                break;
                
                //
                // Both TIMESTAMPOID and TIMESTAMPTZOID are sent either as int64 if compiled
                // with timestamp as integers or double (float8 in PostgreSQL speak) if the compile
                // option was disabled. Basically here we're assuming int64 which are microseconds since
                // POSTGRES_EPOCH_DATE (2000-01-01).
                //
                
            case TIMESTAMPTZOID:
            case TIMESTAMPOID:
                aValue = [CSQLResultValue valueWithDate:[NSDate dateWithTimeInterval:((double)OSSwapConstInt64(*((uint64_t *)value_))/1000000) 
                                                                           sinceDate:POSTGRES_EPOCH_DATE]];
                break;
            case DATEOID:
                aValue = [CSQLResultValue valueWithDate:[[NSDate dateWithString:@"2000-01-01 00:00:00 +0000"] 
                                                         dateByAddingTimeInterval:OSSwapConstInt32(*((uint32_t *)value_)) * 24 * 3600]];
                break;
            default:
                break;
        }
    }            
    else {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        NSString *dateAsString = nil;
        NSDate *date = nil;
        
        switch ([self typeForColumn:index]) {
            case BYTEAOID:
                aValue = [CSQLResultValue valueWithData:[NSData dataWithBytes:value_ length:length_]];
                break;
            case FLOAT4OID:
            case FLOAT8OID:
                aValue = [CSQLResultValue valueWithNumber:[NSNumber numberWithDouble:atof(value_)]];
                break;
            case DATEOID:
                [formatter setDateFormat:@"yyyy-MM-dd"];
                dateAsString = [NSString stringWithUTF8String:value_];
                aValue = [CSQLResultValue valueWithDate:[formatter dateFromString:dateAsString]];
                break;
            case TIMESTAMPTZOID:
                [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ssZZZ"];
                dateAsString = [NSString stringWithUTF8String:value_];
                date = [formatter dateFromString:dateAsString];
                aValue = [CSQLResultValue valueWithDate:date];
                break;
            case TIMESTAMPOID:
                [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                dateAsString = [NSString stringWithUTF8String:value_];
                date = [formatter dateFromString:dateAsString];
                aValue = [CSQLResultValue valueWithDate:date];
                break;
            case CHAROID:
            case TEXTOID:
            case VARCHAROID:
            case INT2OID:
            case INT4OID:
            case INT8OID:
            default:
                aValue = [CSQLResultValue valueWithUTF8String:value_];
                break;
        }
        [formatter release];
    }    
    return aValue;
}

- (id)nameForColumn:(int)index
{
    return [NSString stringWithUTF8String:PQfname(statement.statement, index)];
}

- (NSArray *)rowAsArray
{
    NSMutableArray *row_ = [NSMutableArray arrayWithCapacity:numFields];
    for (int i = 0; i < numFields; i++) {
        [row_ addObject:[self objectForColumn:i]];
    }
    return row_;
}

- (NSDictionary *)rowAsDictionary
{
    NSMutableDictionary *row_ = [NSMutableDictionary dictionaryWithCapacity:numFields];
    for (int i = 0; i < numFields; i++) {
        [row_ setObject:[self objectForColumn:i] forKey:[self nameForColumn:i]];
    }
    return row_;
}

- (void)dealloc
{
    [statement release];
    [super dealloc];
}

@end


@implementation CSPostgreSQLPreparedStatement

- (BOOL)handleResultStatus:(PGresult *)result error:(NSError **)error
{
    BOOL returnValue = YES;
    BOOL clearResult = YES;
    
    switch (PQresultStatus(result)) {
        case PGRES_FATAL_ERROR:
            canFetch = NO;
            returnValue = NO;
            [self getError:error];
            break;
        case PGRES_COMMAND_OK:
            canFetch = NO;
            break;
        case PGRES_TUPLES_OK:
            canFetch = YES;
            clearResult = NO;
            statement = result;
        default:
            break;
    }
    
    if (clearResult) {
        PQclear(result);
        result = nil;
    }
    
    return returnValue;
}

- (CSQLPreparedStatement *)prepareStatementWithDatabase:(CSQLDatabase *)aDatabase andSQL:(NSString *)sql error:(NSError **)error
{
    CSPostgreSQLPreparedStatement *statement_ = [self initWithDatabase:aDatabase andSQL:sql error:error];
    return statement_;
}

- (id)initWithDatabase:(CSQLDatabase *)aDatabase error:(NSError **)error
{
    return [self initWithDatabase:aDatabase andSQL:nil error:error];
}

- (id)initWithDatabase:(CSQLDatabase *)aDatabase andSQL:(NSString *)sql error:(NSError **)error
{
    if ([self init]) {
        database = [aDatabase retain];
        
        PGresult *result = PQprepare(database.databaseHandle, 
                                     "", 
                                     [sql UTF8String], 0, nil);

        if (![self handleResultStatus:result error:error]) {
            [self release];
            self = nil;
        }
    }

    return self;
}

- (id)init
{
    if (self = [super init]) {
        currentRow = 0;
        binds = nil;
        row = nil;
    }
    return self;
}

- (BOOL)executeWithValues:(NSArray *)values error:(NSError **)error
{
    if (!binds)
        binds = [[[CSPostgreSQLBindsStorage alloc] initWithStatement:self andValues:values] retain];
    else
        [binds setValues:values];

    
    PGresult *result = PQexecPrepared(database.databaseHandle, 
                                      "", 
                                      [binds numParams], 
                                      (const char **)[binds paramValues], 
                                      [binds paramLengths], 
                                      [binds paramFormats], 
                                      [binds resultFormat]);
    
    
    return [self handleResultStatus:result error:error];
}

- (BOOL)finish:(NSError **)error
{
    if (statement) {
        PQclear(statement);
        statement = nil;
    }
    return YES;
}

- (void)getError:(NSError **)error
{
    if (error) {
        NSMutableDictionary *errorDetail = [NSMutableDictionary dictionaryWithCapacity:1];
        NSString *errorMessage = [NSString stringWithFormat:@"%s", PQerrorMessage(database.databaseHandle)];
        [errorDetail setObject:errorMessage forKey:NSLocalizedDescriptionKey];
        *error = [NSError errorWithDomain:[[self class] description] code:100 userInfo:errorDetail];
    }
}

- (id)fetchRowWithSelector:(SEL)aSelector error:(NSError **)error
{
    if (!canFetch || currentRow == PQntuples(statement)) {
        canFetch = NO;
        return nil;
    }
    
    if (row) {
        [row setRow:currentRow++];
    }
    else {
        row = [[CSPostgreSQLRow rowWithStatement:self andRow:currentRow++] retain];
    }

    return [row performSelector:aSelector];
}

- (NSDictionary *)fetchRowAsDictionary:(NSError **)error
{
    return [self fetchRowWithSelector:@selector(rowAsDictionary) error:error];
}

- (NSArray *)fetchRowAsArray:(NSError **)error
{
    return [self fetchRowWithSelector:@selector(rowAsArray) error:error];
}

- (void)dealloc
{
    if (statement) {
        PQclear(statement);
        statement = nil;
    }
    if (row)
        [row release];
    if (binds)
        [binds release];
    [database release];
    [super dealloc];
}

@end

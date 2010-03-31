//
//  CSQLDatabaseTests.m
//  CocoaSQL
//
//  Created by Igor Sutton on 3/31/10.
//  Copyright 2010 CocoaSQL.org. All rights reserved.
//

#import "CSQLDatabaseTests.h"


@implementation CSQLDatabaseTests

#define TEST_DB @"test.db"

- (void)setUp
{
    NSError *error = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if ([fm fileExistsAtPath:[TEST_DB stringByExpandingTildeInPath]]) {
        [fm removeItemAtPath:[TEST_DB stringByExpandingTildeInPath] error:nil];
    }
    
    database = [[CSQLDatabase databaseWithDriver:@"SQLite"
                                         options:[NSMutableDictionary dictionaryWithObjectsAndKeys:TEST_DB, @"path", nil]
                                           error:&error] retain];
    
    STAssertNil(error, @"We shouldn't have an error here: %@", error);
    STAssertNotNil(database, @"Database should not be nil.");    
}

- (void)tearDown
{
    [database release];
}

- (void)testExecuteSQL
{
    NSError *error = nil;
    BOOL success;
    
    success = [database executeSQL:@"CREATE TABLE t (i INT, v VARCHAR)"
                             error:&error];
    
    STAssertNil(error, 
                [NSString stringWithFormat:@"We shouldn't have an error here: %@", 
                 [[error userInfo] objectForKey:@"errorMessage"]]);
    STAssertTrue(success, @"SQL executed with success");
}

@end

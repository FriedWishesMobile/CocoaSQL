//
//  CSQLBindValue.h
//  CocoaSQL
//
//  Created by Igor Sutton on 3/29/10.
//  Copyright 2010 CocoaSQL.org. All rights reserved.
//

#import <Cocoa/Cocoa.h>

typedef enum {
    CSQLInteger,
    CSQLDouble,
    CSQLText,
    CSQLBlob,
    CSQLNull
} CSQLBindValueType;

@interface CSQLBindValue : NSObject {
    CSQLBindValueType type;
    id value;
}

/*
 
 CSQLBindValue *bv;
 
 // Sets type to CSQLInteger, value to NSNumber.
 bv = [CSQLBindValue bindValueWithInt:1];
 
 // Sets type to CSQLDouble, value to NSNumber.
 bv = [CSQLBindValue bindValueWithDouble:1.0];
 
 // Sets type to CSQLText, value to NSString (copies string).
 bv = [CSQLBindValue bindValueWithString:@"Foobar"];
 
 NSString *text = @"Foobar";
 
 // Sets type to CSQLBlob, value to NSData (copies from input).
 bv = [CSQLBindValue bindValueWithData:[text dataUsingEncoding:NSUTF8StringEncoding]];
 
 */

+ (id)bindValueWithInt:(int)aValue;
+ (id)bindValueWithDouble:(double)aValue;
+ (id)bindValueWithString:(NSString *)aValue;
+ (id)bindValueWithData:(NSData *)aValue;
+ (id)bindValueWithNull;

- (id)initWithInt:(int)aValue;
- (id)initWithDouble:(double)aValue;
- (id)initWithString:(NSString *)aValue;
- (id)initWithData:(NSData *)aValue;
- (id)initWithNull;

- (CSQLBindValueType)type;

- (int)intValue;
- (double)doubleValue;
- (NSString *)stringValue;
- (NSData *)dataValue;

@end

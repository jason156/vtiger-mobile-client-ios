//
//  Parser.m
//  VTFunctionalitiesApp
//
//  Created by Giovanni on 11/30/13.
//  Copyright (c) 2013 gixWorks. All rights reserved.
//

#import "ResponseParser.h"
#import "Model.h"
#import "NetworkOperationManager.h"

//Module names constants
NSString* const kVTModuleCalendar = @"Calendar";
NSString* const kVTModuleAccounts = @"Accounts";
NSString* const kVTModuleContacts = @"Contacts";
NSString* const kVTModuleLeads = @"Leads";
NSString* const kVTModulePotentials = @"Potentials";
NSString* const kVTModuleHelpDesk = @"HelpDesk";
NSString* const kVTModuleProducts = @"Products";

//Error Key
NSString* const kErrorKey = @"error";

//Other
NSString* const kMinimumRequiredVersion = @"5.2.0";

@implementation ResponseParser

+ (NSDictionary*)parseLogin:(NSDictionary *)JSON
{
    
    NSMutableDictionary *parseResult = [[NSMutableDictionary alloc] init];
    /*
     Structure of returned result is: @ { "@error" : @{@"message" : ... the message ...} }
     */
    __block NSString *version;
    __block NSString *mobile_version;
    __block NSString *userid;
    
    version = [[[JSON valueForKeyPath:@"result"] valueForKeyPath:@"login"] valueForKeyPath:@"vtiger_version"] ;
    mobile_version = [[[JSON valueForKeyPath:@"result"] valueForKeyPath:@"login"] valueForKeyPath:@"mobile_module_version"] ;
    userid = [[[JSON valueForKeyPath:@"result"] valueForKeyPath:@"login"] valueForKeyPath:@"userid"] ;
    
    @try {
        if ([kMinimumRequiredVersion compare:version options:NSNumericSearch] == NSOrderedDescending) {
            // actualVersion is lower than the requiredVersion
            NSString *message = [NSString stringWithFormat:NSLocalizedString(@"vTiger Version (%@) lower than minimum required (%@)", @"vTiger Version (%@) lower than minimum required (%@) "), version, kMinimumRequiredVersion];
            NSDictionary *errorInfo = [NSDictionary dictionaryWithObjectsAndKeys:message, @"message", nil];
            [parseResult setObject:errorInfo forKey:kErrorKey];
            return parseResult;
        }
        else if(!mobile_version)
        {
            // actualVersion is lower than the requiredVersion
            NSDictionary *errorInfo = [NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Mobile Module Not Installed", @"Mobile Module Not Installed "), @"message", nil];
            [parseResult setObject:errorInfo forKey:kErrorKey];
            return  parseResult;
        }
        else {
            //Everything is OK
            //Get info about timezones for server and user
            NSString *timezoneServer = [parseResult objectForKey:@"crm_tz"];
            if (timezoneServer == nil) {
                timezoneServer = [[NSTimeZone defaultTimeZone] name];
            }
            else{
                NSTimeZone *tz = [NSTimeZone timeZoneWithAbbreviation:timezoneServer];
                timezoneServer = [tz name];
            }
            [parseResult setObject:timezoneServer forKey:@"crm_tz"];
            
            NSString *timezoneUser = [parseResult objectForKey:@"user_tz"];
            if (timezoneUser == nil) {
                timezoneUser = [[NSTimeZone defaultTimeZone] name];
            }
            else{
                NSTimeZone *tz = [NSTimeZone timeZoneWithAbbreviation:timezoneUser];
                timezoneUser = [tz name];
            }
            
            [parseResult setObject:timezoneUser forKey:@"user_tz"];
            
            
            //Check if we have some modules
            //Loop through the modules in the returned JSON
            NSArray *modules = [JSON valueForKeyPath:@"result.modules"];
            if (modules != nil) {
                [modules enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    NSDictionary *field = (NSDictionary*)obj;
                    [Module modelObjectWithDictionary:field]; //Should already add to Context
                }];
                
            }
            
            //Finally I save
            //Save the record in the datasource
            __block NSError *saveError;
            [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreWithCompletion:^(BOOL success, NSError *error) {
                saveError = error;
            }];
            
            
        }
        
    }
    @catch (NSException *exception) {
        NSLog(@"%@ %@ Exception: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), [exception description]);
        [parseResult setObject:[exception description] forKey:kErrorKey];
    }
    
    return parseResult;
}

+ (NSDictionary*)parseCalendarSync:(NSDictionary *)JSON
{
    BOOL success = [[JSON objectForKey:@"success"] boolValue];
    NSDictionary *sync = [JSON valueForKeyPath:@"result.sync"];
    NSString *nextSyncToken;
    if ([[sync objectForKey:@"nextSyncToken"] isKindOfClass:[NSString class]]) {
        nextSyncToken = [sync objectForKey:@"nextSyncToken"];
    }
    else{
        nextSyncToken = [[sync objectForKey:@"nextSyncToken"] stringValue];
    }
    NSArray *deletedRecords = [sync objectForKey:@"deleted"];
    NSArray *updatedRecords = [sync objectForKey:@"updated"];
    NSInteger nextPage = [[sync objectForKey:@"nextPage"] integerValue];
    
    NSLog(@"%@ %@ Deleted Records: %ld Updated Records: %ld", NSStringFromClass([self class]), NSStringFromSelector(_cmd), (unsigned long)[deletedRecords count], (unsigned long)[updatedRecords count]);
    
    if (success != YES) {
        NSDictionary *error = [NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Sync was not successful", @"Synchronization was not successful"), @"message", nil];
        return [NSDictionary dictionaryWithObjectsAndKeys:error, kErrorKey, nil];
    }
    
    //1- Do something with the synctoken, save it in AppData
    //...
    //2- Go through the deleted records, get the IDs and remove them from database
    //...
    //3- Go through the updated records, create entities and save them
    
    for (NSDictionary* entity in updatedRecords) { //Main loop, we are going through each entitiy
        //A- Prepare the main elements of each record: the identifier and the blocks
        NSString *identifier = [entity objectForKey:@"id"];
        NSArray *blocks = [entity objectForKey:@"blocks"];
        NSMutableDictionary *entityFields = [[NSMutableDictionary alloc] init];
        NSMutableDictionary *entityCustomFields = [[NSMutableDictionary alloc] init];
        [entityFields setObject:identifier forKey:@"id"];
        for (NSDictionary* block in blocks) {
            //This is the loop for each block of fields
            NSArray *fields = [block objectForKey:@"fields"];
            for (NSDictionary* field in fields) {
                //C- Extract all the fields from the returned JSON
                NSString* fieldName = [field objectForKey:@"name"];
                [entityFields setObject:[field objectForKey:@"value"] forKey:fieldName];
                if ([fieldName hasPrefix:@"cf_"]) {
                    //it's a custom field
                    [entityCustomFields setObject:field forKey:fieldName];
                }
            }
        }
        //D - create the item, using the fields from the Dictionary. The item is already added to persistent storage.
        [Activity modelObjectWithDictionary:entityFields customFields:entityCustomFields];
    }   //end main loop
    
    //E- Parse through Deleted Records, which is just an Array of record IDs
    for (NSString* identifier in deletedRecords) {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"crm_id = %@",identifier];
        [Activity MR_deleteAllMatchingPredicate:predicate];
    }
    
    //F- Save to Core Data (or whatever) the array of items
    __block NSError *saveError;
    [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreWithCompletion:^(BOOL success, NSError *error) {
        saveError = error;
    }];
    
    //G- if nextPage != 0 means that we have another page of records to sync
    if (nextPage != 0) {
        [[NetworkOperationManager sharedInstance] syncCalendarFromPage:[NSNumber numberWithInteger:nextPage]];
    }
    
    //H- If Save went OK, set the next synctoken
    if (saveError == nil) {
        SyncToken *token = [SyncToken MR_createEntity];
        token.token = nextSyncToken;
        token.module = kVTModuleCalendar;
        token.datetime = [NSDate date];
        [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreAndWait];
    }
    
    
    return [NSDictionary dictionaryWithObjectsAndKeys:saveError,kErrorKey, nil];
}

+ (NSDictionary*)parseFetchRecord:(NSDictionary*)JSON
{
    NSManagedObject *returnedRecord = nil;
    BOOL success = [[JSON objectForKey:@"success"] boolValue];
    if (success != YES) {
        NSDictionary *error = [NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Login was not successful", @"Login was not successful"), @"message", nil];
        return [NSDictionary dictionaryWithObjectsAndKeys:error, kErrorKey, nil];
    }
    
    NSDictionary *record = [JSON valueForKeyPath:@"result.record"];
    //Record already contains the field in Key-Value format
    
    //To create the new entity, we need to decode the type
    NSString *module = [self decodeRecordType:[record objectForKey:@"id"]];
    if ([module isEqualToString:kVTModuleCalendar]) {
        returnedRecord = [Activity modelObjectWithDictionary:record];
    }
    else if([module isEqualToString:kVTModuleAccounts]){
        returnedRecord = [Account modelObjectWithDictionary:record];
    }
    else if([module isEqualToString:kVTModuleContacts]){
        returnedRecord = [Contact modelObjectWithDictionary:record];
    }
    else if([module isEqualToString:kVTModuleLeads]){
        returnedRecord = [Lead modelObjectWithDictionary:record];
    }
    else if([module isEqualToString:kVTModulePotentials]){
        returnedRecord = [Potential modelObjectWithDictionary:record];
    }
    else if([module isEqualToString:kVTModuleHelpDesk]){
        returnedRecord = [Ticket modelObjectWithDictionary:record];
    }
    else if([module isEqualToString:kVTModuleProducts]){
        returnedRecord = [Product modelObjectWithDictionary:record];
    }
    else{
        NSDictionary* userInfo = [[NSDictionary alloc] initWithObjectsAndKeys:returnedRecord, @"record", @"%@ %@ No Module Handler found", NSStringFromClass([self class]), NSStringFromSelector(_cmd), kErrorKey, nil];
        return  userInfo;
    }
    
    //Save the record in the datasource
    __block NSError *saveError;
    [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreWithCompletion:^(BOOL success, NSError *error) {
        saveError = error;
    }];
    
    NSDictionary* userInfo = [[NSDictionary alloc] initWithObjectsAndKeys:returnedRecord, @"record", saveError, kErrorKey, nil];
    return userInfo;
}

+ (NSDictionary*)parseFetchRecordsWithGrouping:(NSDictionary*)JSON forModule:(NSString*)module
{
    BOOL success = [[JSON objectForKey:@"success"] boolValue];
    NSArray *records = [JSON valueForKeyPath:@"result.records"];
    
    if (success != YES) {
        NSDictionary *error = [NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Sync was not successful", @"Synchronization was not successful"), @"message", nil];
        return [NSDictionary dictionaryWithObjectsAndKeys:error, kErrorKey, nil];
    }
    
    //Go through the records
    for (NSDictionary *entity in records) { //Main loop, we are going through each entitiy
        //A- Prepare the main elements of each record: the identifier and the blocks
        NSString *identifier = [entity objectForKey:@"id"];
        NSArray *blocks = [entity objectForKey:@"blocks"];
        //B- prepare a dictionary to contain the values that will be stored in the Entity properties
        NSMutableDictionary *entityFields = [[NSMutableDictionary alloc] init];
        [entityFields setObject:identifier forKey:@"id"];
        for (NSDictionary *block in blocks) {
            NSArray *fields = [block objectForKey:@"fields"];
            for (NSDictionary *field in fields) {
                //C- Extract all the fields from the returned JSON
                [entityFields setObject:[field objectForKey:@"value"] forKey:[field objectForKey:@"name"]];
            }
        }
        //D - create the items starting from the dictionary
        if ([module isEqualToString:kVTModuleCalendar]) {
            [Activity modelObjectWithDictionary:entityFields];
        }
        if ([module isEqualToString:kVTModuleAccounts]) {
            [Account modelObjectWithDictionary:entityFields];
        }
        if ([module isEqualToString:kVTModuleContacts]) {
            [Contact modelObjectWithDictionary:entityFields];
        }
        if ([module isEqualToString:kVTModuleLeads]) {
            [Lead modelObjectWithDictionary:entityFields];
        }
        if ([module isEqualToString:kVTModulePotentials]) {
            [Potential modelObjectWithDictionary:entityFields];
        }
        if ([module isEqualToString:kVTModuleHelpDesk]) {
            [Ticket modelObjectWithDictionary:entityFields];
        }
        if ([module isEqualToString:kVTModuleProducts]) {
            [Product modelObjectWithDictionary:entityFields];
        }
    }
    
    //E- Save to Core Data (or whatever) the array of items
    __block NSError *saveError;
    [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreWithCompletion:^(BOOL success, NSError *error) {
        saveError = error;
    }];
    
    //TODO: I could just send the notification here of finished parsing directly to ViewController
    return [NSDictionary dictionaryWithObjectsAndKeys:saveError,kErrorKey, nil];
}



#pragma mark - Utility Methods

/**
 Returns the name of the Module based on the record passed
 
 @param method The record id to decode, in the format MODULExRECORD_ID e.g. 1x1223
 */
+ (NSString*)decodeRecordType:(NSString*)record
{
    NSString *m = [[record componentsSeparatedByString:@"x"] objectAtIndex:0];
    Module *module = [Module MR_findFirstByAttribute:@"crm_id" withValue:m];
    if (module != nil) {
        return module.crm_name;
    }
    return nil;
}


@end
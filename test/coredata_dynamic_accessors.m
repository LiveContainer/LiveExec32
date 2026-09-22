#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdio.h>

static unsigned checks, failures;
static void check(const char *name, BOOL result) {
    printf("coredata-dynamic-%s: %s\n", name, result ? "PASS" : "FAIL");
    fflush(stdout);
    ++checks;
    failures += !result;
}

@interface LC32ManagedRecordBase : NSManagedObject
@property(nonatomic, retain) NSString *sessionId;
@end
@implementation LC32ManagedRecordBase
@dynamic sessionId;
@end

@interface LC32ManagedRecord : LC32ManagedRecordBase
@property(nonatomic, retain) NSString *URL;
@property(nonatomic, retain) NSNumber *timestamp;
@property(nonatomic, retain) LC32ManagedRecord *partner;
@end
@implementation LC32ManagedRecord
@dynamic URL, timestamp, partner;
@end

@interface LC32ManagedObserver : NSObject {
@public
    unsigned changes;
    BOOL correctChange;
}
@end
@implementation LC32ManagedObserver
- (void)observeValueForKeyPath:(NSString *)key ofObject:(id)object
        change:(NSDictionary *)change context:(void *)context {
    ++changes;
    correctChange = [key isEqual:@"sessionId"] &&
        [[change objectForKey:NSKeyValueChangeOldKey] isEqual:@"session-one"] &&
        [[change objectForKey:NSKeyValueChangeNewKey] isEqual:@"session-two"];
}
@end

static NSAttributeDescription *attribute(NSString *name, NSAttributeType type) {
    NSAttributeDescription *result = [[[NSAttributeDescription alloc] init] autorelease];
    result.name = name;
    result.attributeType = type;
    result.optional = YES;
    return result;
}

int main(void) {
    @autoreleasepool {
        NSManagedObjectModel *model = [[[NSManagedObjectModel alloc] init] autorelease];
        NSEntityDescription *entity = [[[NSEntityDescription alloc] init] autorelease];
        entity.name = @"Record";
        entity.managedObjectClassName = @"LC32ManagedRecord";
        NSRelationshipDescription *partner = [[[NSRelationshipDescription alloc] init] autorelease];
        partner.name = @"partner";
        partner.destinationEntity = entity;
        partner.minCount = 0;
        partner.maxCount = 1;
        partner.optional = YES;
        partner.inverseRelationship = partner;
        entity.properties = @[
            attribute(@"sessionId", NSStringAttributeType),
            attribute(@"URL", NSStringAttributeType),
            attribute(@"timestamp", NSInteger64AttributeType), partner];
        model.entities = @[entity];
        NSPersistentStoreCoordinator *coordinator = [[[NSPersistentStoreCoordinator alloc]
            initWithManagedObjectModel:model] autorelease];
        NSError *error = nil;
        check("store", [coordinator addPersistentStoreWithType:NSInMemoryStoreType
            configuration:nil URL:nil options:nil error:&error] != nil && !error);
        NSManagedObjectContext *context = [[[NSManagedObjectContext alloc]
            initWithConcurrencyType:NSMainQueueConcurrencyType] autorelease];
        context.persistentStoreCoordinator = coordinator;
        LC32ManagedRecord *record = [NSEntityDescription
            insertNewObjectForEntityForName:@"Record" inManagedObjectContext:context];
        check("guest-subclass", [record isKindOfClass:[LC32ManagedRecord class]]);
        record.sessionId = @"session-one";
        check("string-getter", [record.sessionId isEqual:@"session-one"]);
        check("kvc-sees-setter", [[record valueForKey:@"sessionId"] isEqual:@"session-one"]);
        record.URL = @"https://example.invalid/record";
        check("uppercase-key", [record.URL isEqual:@"https://example.invalid/record"]);
        record.timestamp = @4294967301LL;
        check("boxed-int64", record.timestamp.longLongValue == 4294967301LL);
        LC32ManagedObserver *observer = [[[LC32ManagedObserver alloc] init] autorelease];
        [record addObserver:observer forKeyPath:@"sessionId"
            options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew context:NULL];
        [record setValue:@"session-two" forKey:@"sessionId"];
        check("kvo-once", observer->changes == 1);
        check("kvo-values", observer->correctChange);
        [record removeObserver:observer forKeyPath:@"sessionId"];
        check("getter-sees-kvc", [record.sessionId isEqual:@"session-two"]);
        LC32ManagedRecord *other = [NSEntityDescription
            insertNewObjectForEntityForName:@"Record" inManagedObjectContext:context];
        other.sessionId = @"other-session";
        record.partner = other;
        check("relationship", record.partner == other);
        check("inverse", other.partner == record);
        check("save", [context save:&error] && !error);
        NSManagedObjectID *objectID = [[record objectID] retain];
        [context reset];
        record = (LC32ManagedRecord *)[context objectWithID:objectID];
        check("fault", record.isFault);
        check("fault-getter", [record.sessionId isEqual:@"session-two"]);
        check("fault-number", record.timestamp.longLongValue == 4294967301LL);
        check("fault-relationship", [record.partner.sessionId isEqual:@"other-session"]);
        check("fault-inverse", record.partner.partner == record);
        record.partner = nil;
        check("relationship-clear", record.partner == nil);
        record.sessionId = nil;
        check("nil-setter", record.sessionId == nil);
        check("updated", record.isUpdated);
        [objectID release];
    }
    printf("coredata-dynamic: %u checks, %u failures\n", checks, failures);
    return failures ? 1 : 0;
}

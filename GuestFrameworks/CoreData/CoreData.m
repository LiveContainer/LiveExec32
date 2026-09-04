#import <CoreData/CoreData.h>
#import <Foundation/Foundation+LC32.h>
#import <objc/runtime.h>

/*
 * Core Data option/store constants are Objective-C strings on both sides of
 * the bridge.  Resolve the native constants so dictionary lookups performed
 * by host Core Data see the exact host keys while preserving the ARM32 export
 * locations expected by the guest loader.
 */
LC32_CONST_STR_DECL(NSString *const NSInferMappingModelAutomaticallyOption)
LC32_CONST_STR_DECL(NSString *const NSMigratePersistentStoresAutomaticallyOption)
LC32_CONST_STR_DECL(NSString *const NSSQLiteStoreType)
LC32_CONST_STR_DECL(NSString *const NSAddedPersistentStoresKey)
LC32_CONST_STR_DECL(NSString *const NSAffectedObjectsErrorKey)
LC32_CONST_STR_DECL(NSString *const NSAffectedStoresErrorKey)
LC32_CONST_STR_DECL(NSString *const NSBinaryStoreType)
LC32_CONST_STR_DECL(NSString *const NSDeletedObjectsKey)
LC32_CONST_STR_DECL(NSString *const NSDetailedErrorsKey)
LC32_CONST_STR_DECL(NSString *const NSIgnorePersistentStoreVersioningOption)
LC32_CONST_STR_DECL(NSString *const NSInMemoryStoreType)
LC32_CONST_STR_DECL(NSString *const NSInsertedObjectsKey)
LC32_CONST_STR_DECL(NSString *const NSInvalidatedAllObjectsKey)
LC32_CONST_STR_DECL(NSString *const NSInvalidatedObjectsKey)
LC32_CONST_STR_DECL(NSString *const NSManagedObjectContextDidSaveNotification)
LC32_CONST_STR_DECL(NSString *const NSManagedObjectContextObjectsDidChangeNotification)
LC32_CONST_STR_DECL(NSString *const NSManagedObjectContextQueryGenerationKey)
LC32_CONST_STR_DECL(NSString *const NSManagedObjectContextWillSaveNotification)
LC32_CONST_STR_DECL(NSString *const NSMigrationDestinationObjectKey)
LC32_CONST_STR_DECL(NSString *const NSMigrationEntityMappingKey)
LC32_CONST_STR_DECL(NSString *const NSMigrationEntityPolicyKey)
LC32_CONST_STR_DECL(NSString *const NSMigrationManagerKey)
LC32_CONST_STR_DECL(NSString *const NSMigrationPropertyMappingKey)
LC32_CONST_STR_DECL(NSString *const NSMigrationSourceObjectKey)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreConnectionPoolMaxSizeKey)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreCoordinatorStoresDidChangeNotification)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreCoordinatorStoresWillChangeNotification)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreCoordinatorWillRemoveStoreNotification)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreDidImportUbiquitousContentChangesNotification)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreFileProtectionKey)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreForceDestroyOption)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreOSCompatibility)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreRebuildFromUbiquitousContentOption)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreRemoveUbiquitousMetadataOption)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreSaveConflictsErrorKey)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreTimeoutOption)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreUbiquitousContainerIdentifierKey)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreUbiquitousContentNameKey)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreUbiquitousContentURLKey)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreUbiquitousPeerTokenOption)
LC32_CONST_STR_DECL(NSString *const NSPersistentStoreUbiquitousTransitionTypeKey)
LC32_CONST_STR_DECL(NSString *const NSReadOnlyPersistentStoreOption)
LC32_CONST_STR_DECL(NSString *const NSRefreshedObjectsKey)
LC32_CONST_STR_DECL(NSString *const NSRemovedPersistentStoresKey)
LC32_CONST_STR_DECL(NSString *const NSSQLiteAnalyzeOption)
LC32_CONST_STR_DECL(NSString *const NSSQLiteErrorDomain)
LC32_CONST_STR_DECL(NSString *const NSSQLiteManualVacuumOption)
LC32_CONST_STR_DECL(NSString *const NSSQLitePragmasOption)
LC32_CONST_STR_DECL(NSString *const NSStoreModelVersionHashesKey)
LC32_CONST_STR_DECL(NSString *const NSStoreModelVersionIdentifiersKey)
LC32_CONST_STR_DECL(NSString *const NSStoreTypeKey)
LC32_CONST_STR_DECL(NSString *const NSStoreUUIDKey)
LC32_CONST_STR_DECL(NSString *const NSUUIDChangedPersistentStoresKey)
LC32_CONST_STR_DECL(NSString *const NSUpdatedObjectsKey)
LC32_CONST_STR_DECL(NSString *const NSValidationKeyErrorKey)
LC32_CONST_STR_DECL(NSString *const NSValidationObjectErrorKey)
LC32_CONST_STR_DECL(NSString *const NSValidationPredicateErrorKey)
LC32_CONST_STR_DECL(NSString *const NSValidationValueErrorKey)

/* The latest public Core Data version number in the iOS 10.3 SDK. */
double NSCoreDataVersionNumber = NSCoreDataVersionNumber_iPhoneOS_9_3;

id NSErrorMergePolicy;
id NSMergeByPropertyStoreTrumpMergePolicy;
id NSMergeByPropertyObjectTrumpMergePolicy;
id NSOverwriteMergePolicy;
id NSRollbackMergePolicy;

/*
 * The predefined merge policies are process-lifetime singletons. Allocate
 * their guest mirrors directly during framework initialization: asking a
 * native singleton for -guest_self here may call back into the guest while
 * dyld is still running constructors and has no resumable startup PC.
 */
@interface LC32CoreDataMergePolicyProxy : NSMergePolicy
@end

@implementation LC32CoreDataMergePolicyProxy
- (id)retain { return self; }
- (oneway void)release {}
- (id)autorelease { return self; }
- (NSUInteger)retainCount { return NSUIntegerMax; }
@end

static id LC32CreateCoreDataMergePolicyProxy(const char *symbolName) {
    Class cls = objc_getClass("LC32CoreDataMergePolicyProxy");
    id guestObject = cls ? class_createInstance(cls, 0) : nil;
    const uint64_t hostObject = LC32Dlsym(symbolName, NO);
    if(!guestObject || !hostObject) abort();
    [guestObject bindHostSelf:hostObject];
    return guestObject;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
__attribute__((constructor)) static void LC32InitializeCoreDataConstants(void) {
    LC32LoadHostFramework("CoreData");
    LC32_CONST_STR_INIT(NSInferMappingModelAutomaticallyOption);
    LC32_CONST_STR_INIT(NSMigratePersistentStoresAutomaticallyOption);
    LC32_CONST_STR_INIT(NSSQLiteStoreType);
    LC32_CONST_STR_INIT(NSAddedPersistentStoresKey);
    LC32_CONST_STR_INIT(NSAffectedObjectsErrorKey);
    LC32_CONST_STR_INIT(NSAffectedStoresErrorKey);
    LC32_CONST_STR_INIT(NSBinaryStoreType);
    LC32_CONST_STR_INIT(NSDeletedObjectsKey);
    LC32_CONST_STR_INIT(NSDetailedErrorsKey);
    LC32_CONST_STR_INIT(NSIgnorePersistentStoreVersioningOption);
    LC32_CONST_STR_INIT(NSInMemoryStoreType);
    LC32_CONST_STR_INIT(NSInsertedObjectsKey);
    LC32_CONST_STR_INIT(NSInvalidatedAllObjectsKey);
    LC32_CONST_STR_INIT(NSInvalidatedObjectsKey);
    LC32_CONST_STR_INIT(NSManagedObjectContextDidSaveNotification);
    LC32_CONST_STR_INIT(NSManagedObjectContextObjectsDidChangeNotification);
    LC32_CONST_STR_INIT(NSManagedObjectContextQueryGenerationKey);
    LC32_CONST_STR_INIT(NSManagedObjectContextWillSaveNotification);
    LC32_CONST_STR_INIT(NSMigrationDestinationObjectKey);
    LC32_CONST_STR_INIT(NSMigrationEntityMappingKey);
    LC32_CONST_STR_INIT(NSMigrationEntityPolicyKey);
    LC32_CONST_STR_INIT(NSMigrationManagerKey);
    LC32_CONST_STR_INIT(NSMigrationPropertyMappingKey);
    LC32_CONST_STR_INIT(NSMigrationSourceObjectKey);
    LC32_CONST_STR_INIT(NSPersistentStoreConnectionPoolMaxSizeKey);
    LC32_CONST_STR_INIT(NSPersistentStoreCoordinatorStoresDidChangeNotification);
    LC32_CONST_STR_INIT(NSPersistentStoreCoordinatorStoresWillChangeNotification);
    LC32_CONST_STR_INIT(NSPersistentStoreCoordinatorWillRemoveStoreNotification);
    LC32_CONST_STR_INIT(NSPersistentStoreDidImportUbiquitousContentChangesNotification);
    LC32_CONST_STR_INIT(NSPersistentStoreFileProtectionKey);
    LC32_CONST_STR_INIT(NSPersistentStoreForceDestroyOption);
    LC32_CONST_STR_INIT(NSPersistentStoreOSCompatibility);
    LC32_CONST_STR_INIT(NSPersistentStoreRebuildFromUbiquitousContentOption);
    LC32_CONST_STR_INIT(NSPersistentStoreRemoveUbiquitousMetadataOption);
    LC32_CONST_STR_INIT(NSPersistentStoreSaveConflictsErrorKey);
    LC32_CONST_STR_INIT(NSPersistentStoreTimeoutOption);
    LC32_CONST_STR_INIT(NSPersistentStoreUbiquitousContainerIdentifierKey);
    LC32_CONST_STR_INIT(NSPersistentStoreUbiquitousContentNameKey);
    LC32_CONST_STR_INIT(NSPersistentStoreUbiquitousContentURLKey);
    LC32_CONST_STR_INIT(NSPersistentStoreUbiquitousPeerTokenOption);
    LC32_CONST_STR_INIT(NSPersistentStoreUbiquitousTransitionTypeKey);
    LC32_CONST_STR_INIT(NSReadOnlyPersistentStoreOption);
    LC32_CONST_STR_INIT(NSRefreshedObjectsKey);
    LC32_CONST_STR_INIT(NSRemovedPersistentStoresKey);
    LC32_CONST_STR_INIT(NSSQLiteAnalyzeOption);
    LC32_CONST_STR_INIT(NSSQLiteErrorDomain);
    LC32_CONST_STR_INIT(NSSQLiteManualVacuumOption);
    LC32_CONST_STR_INIT(NSSQLitePragmasOption);
    LC32_CONST_STR_INIT(NSStoreModelVersionHashesKey);
    LC32_CONST_STR_INIT(NSStoreModelVersionIdentifiersKey);
    LC32_CONST_STR_INIT(NSStoreTypeKey);
    LC32_CONST_STR_INIT(NSStoreUUIDKey);
    LC32_CONST_STR_INIT(NSUUIDChangedPersistentStoresKey);
    LC32_CONST_STR_INIT(NSUpdatedObjectsKey);
    LC32_CONST_STR_INIT(NSValidationKeyErrorKey);
    LC32_CONST_STR_INIT(NSValidationObjectErrorKey);
    LC32_CONST_STR_INIT(NSValidationPredicateErrorKey);
    LC32_CONST_STR_INIT(NSValidationValueErrorKey);

    /* Preserve singleton identity while exposing ordinary guest pointers. */
    NSErrorMergePolicy = LC32CreateCoreDataMergePolicyProxy(
        "NSErrorMergePolicy");
    NSMergeByPropertyStoreTrumpMergePolicy =
        LC32CreateCoreDataMergePolicyProxy(
            "NSMergeByPropertyStoreTrumpMergePolicy");
    NSMergeByPropertyObjectTrumpMergePolicy =
        LC32CreateCoreDataMergePolicyProxy(
            "NSMergeByPropertyObjectTrumpMergePolicy");
    NSOverwriteMergePolicy = LC32CreateCoreDataMergePolicyProxy(
        "NSOverwriteMergePolicy");
    NSRollbackMergePolicy = LC32CreateCoreDataMergePolicyProxy(
        "NSRollbackMergePolicy");
}
#pragma clang diagnostic pop

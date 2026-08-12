#import <CoreData/CoreData.h>
#import <Foundation/Foundation+LC32.h>

/*
 * Core Data option/store constants are Objective-C strings on both sides of
 * the bridge.  Resolve the native constants so dictionary lookups performed
 * by host Core Data see the exact host keys while preserving the ARM32 export
 * locations expected by the guest loader.
 */
LC32_CONST_STR_DECL(NSString *const NSInferMappingModelAutomaticallyOption)
LC32_CONST_STR_DECL(NSString *const NSMigratePersistentStoresAutomaticallyOption)
LC32_CONST_STR_DECL(NSString *const NSSQLiteStoreType)

__attribute__((constructor)) static void LC32InitializeCoreDataConstants(void) {
    LC32_CONST_STR_INIT(NSInferMappingModelAutomaticallyOption);
    LC32_CONST_STR_INIT(NSMigratePersistentStoresAutomaticallyOption);
    LC32_CONST_STR_INIT(NSSQLiteStoreType);
}

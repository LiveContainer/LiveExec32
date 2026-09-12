#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

/* Keep these CF-backed adapters for the legacy owned error strings and the
 * property-list-specific output rules, rather than generic object copyback. */
static id LC32ReadPropertyList(NSData *data,
        NSPropertyListReadOptions options, NSPropertyListFormat *format,
        CFErrorRef *error) {
    CFPropertyListFormat parsedFormat = 0;
    CFPropertyListRef result = CFPropertyListCreateWithData(
        kCFAllocatorDefault, (CFDataRef)data, (CFOptionFlags)options,
        format ? &parsedFormat : NULL, error);
    /* NSPropertyListFormat is unsigned whereas CFPropertyListFormat is
     * signed. Do not alias their pointers or publish a format on failure. */
    if(result && format) *format = (NSPropertyListFormat)parsedFormat;
    return [(id)result autorelease];
}

static void LC32ReturnPropertyListError(CFErrorRef error,
        NSError **outError) {
    if(!error) return;
    if(outError) *outError = [(NSError *)error autorelease];
    else CFRelease(error);
}

static void LC32ReturnPropertyListErrorDescription(CFErrorRef error,
        NSString **outDescription) {
    if(!error) return;
    /* Unlike NSError ** APIs, the deprecated errorDescription: methods
     * transfer ownership of the error string to their caller. */
    if(outDescription)
        *outDescription = (NSString *)CFErrorCopyDescription(error);
    CFRelease(error);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

@implementation NSPropertyListSerialization (LC32PropertyLists)

+ (NSData *)dataWithPropertyList:(id)propertyList
                         format:(NSPropertyListFormat)format
                        options:(NSPropertyListWriteOptions)options
                          error:(NSError **)outError {
    CFErrorRef error = NULL;
    CFDataRef data = CFPropertyListCreateData(kCFAllocatorDefault,
        (CFPropertyListRef)propertyList, (CFPropertyListFormat)format,
        (CFOptionFlags)options, outError ? &error : NULL);
    LC32ReturnPropertyListError(error, outError);
    return [(NSData *)data autorelease];
}

+ (id)propertyListWithData:(NSData *)data
                   options:(NSPropertyListReadOptions)options
                    format:(NSPropertyListFormat *)format
                     error:(NSError **)outError {
    CFErrorRef error = NULL;
    id result = LC32ReadPropertyList(data, options, format,
        outError ? &error : NULL);
    LC32ReturnPropertyListError(error, outError);
    return result;
}

+ (NSData *)dataFromPropertyList:(id)propertyList
                         format:(NSPropertyListFormat)format
               errorDescription:(NSString **)outDescription {
    CFErrorRef error = NULL;
    CFDataRef data = CFPropertyListCreateData(kCFAllocatorDefault,
        (CFPropertyListRef)propertyList, (CFPropertyListFormat)format,
        0, outDescription ? &error : NULL);
    LC32ReturnPropertyListErrorDescription(error, outDescription);
    return [(NSData *)data autorelease];
}

+ (id)propertyListFromData:(NSData *)data
          mutabilityOption:(NSPropertyListMutabilityOptions)options
                    format:(NSPropertyListFormat *)format
          errorDescription:(NSString **)outDescription {
    CFErrorRef error = NULL;
    id result = LC32ReadPropertyList(data, options, format,
        outDescription ? &error : NULL);
    LC32ReturnPropertyListErrorDescription(error, outDescription);
    return result;
}

@end

#pragma clang diagnostic pop

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

/// The small subset of Objective-C method metadata needed by GenerateShimObjC.
///
/// This deliberately does not use NSMethodSignature: several valid iOS 10
/// encodings contain arrays, bitfields, or C++ types that NSMethodSignature
/// rejects. Captured plist entries can also describe APIs absent from the host.
@interface LC32ObjCMethod : NSObject

@property(nonatomic, assign, readonly) SEL selector;
@property(nonatomic, copy, readonly) NSString *selectorString;
@property(nonatomic, assign, readonly) BOOL isInstanceMethod;
@property(nonatomic, assign, readonly) NSUInteger numberOfArguments;
@property(nonatomic, assign, readonly) const char *returnType;
@property(nonatomic, copy, readonly) NSString *typeEncoding;
@property(nonatomic, assign, readonly) BOOL hasCompleteTypeEncoding;

+ (nullable instancetype)method:(Method)method
               isInstanceMethod:(BOOL)isInstanceMethod;

+ (nullable instancetype)methodWithSelector:(SEL)selector
                               typeEncoding:(const char *)typeEncoding
                           isInstanceMethod:(BOOL)isInstanceMethod;

- (const char *)argumentTypeAtIndex:(NSUInteger)index;

@end

/// Converts one Objective-C type encoding into a source-level type name.
FOUNDATION_EXPORT NSString *LC32ReadableTypeForEncoding(const char *encoding);

NS_ASSUME_NONNULL_END

#import <JavaScriptCore/JavaScriptCore.h>
#import <Foundation/Foundation+LC32.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

const JSClassDefinition kJSClassDefinitionEmpty = { 0 };

/* Bind guest proxies to the native framework's canonical object constants. */
#define LC32_JAVASCRIPTCORE_OBJECT_CONSTANTS(X) \
    X(JSPropertyDescriptorConfigurableKey) \
    X(JSPropertyDescriptorEnumerableKey) \
    X(JSPropertyDescriptorGetKey) \
    X(JSPropertyDescriptorSetKey) \
    X(JSPropertyDescriptorValueKey) \
    X(JSPropertyDescriptorWritableKey)

#define LC32_DECLARE_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_DECL(__typeof__(name) name)
LC32_JAVASCRIPTCORE_OBJECT_CONSTANTS(LC32_DECLARE_OBJECT_CONSTANT)
#undef LC32_DECLARE_OBJECT_CONSTANT

__attribute__((constructor))
static void LC32InitializeJavaScriptCoreObjectConstants(void) {
    LC32LoadHostFramework("JavaScriptCore");
#define LC32_INITIALIZE_OBJECT_CONSTANT(name) LC32_CONST_STR_INIT(name);
    LC32_JAVASCRIPTCORE_OBJECT_CONSTANTS(LC32_INITIALIZE_OBJECT_CONSTANT)
#undef LC32_INITIALIZE_OBJECT_CONSTANT
}

#undef LC32_JAVASCRIPTCORE_OBJECT_CONSTANTS

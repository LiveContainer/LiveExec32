#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdint.h>
#include <stdio.h>
#include <dlfcn.h>

extern "C" uint32_t lc32_arm_callback(uint32_t);
extern "C" uint32_t lc32_arm_call(uint32_t (*)(uint32_t), uint32_t);
extern "C" uint32_t (*volatile lc32_arm_callback_pointer)(uint32_t);
extern "C" __attribute__((noinline)) uint32_t lc32_thumb_export(uint32_t x) { return x + 7; }

static unsigned failures;
static void check(bool pass, const char *name) {
    printf("guest-linker-%s: %s\n", name, pass ? "PASS" : "FAIL");
    if(!pass) failures++;
}

@interface LC32LinkerFixture : NSObject
+ (int)answer;
@end
@implementation LC32LinkerFixture
+ (int)answer { return 42; }
@end

class Base {
public:
    virtual int answer() { return 41; }
    virtual ~Base() = default;
};
class Derived : public Base {
public:
    int answer() override { return 42; }
};
__attribute__((noinline)) static int dispatch(Base *object) { return object->answer(); }

int main(void) {
    @autoreleasepool {
        check(!((uintptr_t)lc32_arm_callback_pointer & 1) && lc32_arm_callback_pointer(1) == 14,
              "arm-pointer-preserved");
        check(lc32_arm_callback(1) == 14 && lc32_arm_call(lc32_thumb_export, 1) == 25,
              "arm-thumb-interworking");
        Method method = class_getClassMethod(LC32LinkerFixture.class, @selector(answer));
        check(((uintptr_t)method_getImplementation(method) & 1) && [LC32LinkerFixture answer] == 42,
              "objc-imp");
        int (^globalBlock)(int) = ^(int x) { return x + 1; };
        int captured = 11;
        int (^capturingBlock)(int) = ^(int x) { return x + captured; };
        check(globalBlock(41) == 42 && capturingBlock(31) == 42, "block-invoke");
        Base *object = new Derived;
        check(dispatch(object) == 42, "cpp-vtable");
        delete object;
        try { throw 42; } catch(int value) { check(value == 42, "cpp-exception"); }
        typedef uint32_t (*Callback)(uint32_t);
        Callback symbol = (Callback)dlsym(RTLD_DEFAULT, "lc32_thumb_export");
        check(symbol && ((uintptr_t)symbol & 1) && symbol(35) == 42, "exported-thumb");
    }
    printf("guest-linker-mixed: %s\n", failures ? "FAIL" : "PASS");
    return failures != 0;
}

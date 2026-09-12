#include "LC32ObjCTrace.h"

#include <stdio.h>
#include <stdlib.h>

#ifndef LC32_TEST_EXPECT_ENABLED
#error Define LC32_TEST_EXPECT_ENABLED for this test.
#endif

_Static_assert(LC32ObjCTraceEnabled() == LC32_TEST_EXPECT_ENABLED,
    "The trace check must be a compile-time constant with the expected value");

static int traceArguments;

static int evaluateTraceArgument(void) {
    return ++traceArguments;
}

int main(void) {
    // A runtime variable must not override the flag in either direction.
    if(setenv("LC32_OBJC_TRACE", LC32_TEST_EXPECT_ENABLED ? "0" : "1", 1))
        return 1;

    if(LC32ObjCTraceEnabled())
        printf("Objective-C trace argument=%d\n", evaluateTraceArgument());
    else if(LC32_TEST_EXPECT_ENABLED)
        return 1;

    if(traceArguments != LC32_TEST_EXPECT_ENABLED) {
        fprintf(stderr, "FAIL: Objective-C trace argument evaluation\n");
        return 1;
    }
    printf("PASS: compile-time Objective-C tracing %s\n",
        LC32_TEST_EXPECT_ENABLED ? "enabled" : "disabled");
    return 0;
}

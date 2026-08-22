#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <LC32/LC32.h>

#include <math.h>
#include <stdio.h>
#include <string.h>

@interface NSObject (LC32ScalarPointerBridgeTest)
- (uint64_t)host_self;
@end

static BOOL LC32InvokeScannerPointer(NSScanner *scanner, SEL selector,
                                     double *canonicalValue) {
    return (BOOL)LC32InvokeHostSelector(
        [scanner host_self], LC32GetHostSelector(selector),
        LC32HostFloatingIndirectArgument(canonicalValue), (uint64_t)0);
}

static int LC32Check(const char *name, BOOL passed, double value) {
    printf("%s: %s (%.17g)\n", name, passed ? "PASS" : "FAIL", value);
    return passed ? 0 : 1;
}

int main(void) {
    @autoreleasepool {
        int failed = 0;

        /* NSScanner exposes genuine native ^f and ^d arguments. Both travel
         * through the same canonical double cell used by generated shims. */
        NSScanner *scanner = [NSScanner scannerWithString:@"12.75 913.125"];
        double floatCell = 0.0;
        const BOOL scannedFloat = LC32InvokeScannerPointer(
            scanner, @selector(scanFloat:), &floatCell);
        failed += LC32Check("native-float-pointer",
            scannedFloat && fabs(floatCell - 12.75) < 0.0001, floatCell);

        double doubleCell = 0.0;
        const BOOL scannedDouble = LC32InvokeScannerPointer(
            scanner, @selector(scanDouble:), &doubleCell);
        failed += LC32Check("native-double-pointer",
            scannedDouble && fabs(doubleCell - 913.125) < 0.0000001,
            doubleCell);

        NSScanner *nullScanner = [NSScanner scannerWithString:@"44"];
        const BOOL scannedWithNull = LC32InvokeScannerPointer(
            nullScanner, @selector(scanFloat:), NULL);
        failed += LC32Check("nullable-floating-pointer",
            scannedWithNull, scannedWithNull);

        NSScanner *decimalScanner =
            [NSScanner scannerWithString:@"12.75 invalid"];
        NSDecimal decimal = {};
        const BOOL scannedDecimal = [decimalScanner scanDecimal:&decimal];
        failed += LC32Check("native-decimal-pointer",
            scannedDecimal && decimal._exponent == -2 &&
                decimal._length == 1 && !decimal._isNegative &&
                decimal._mantissa[0] == 1275,
            decimal._mantissa[0]);

        NSDecimalNumber *decimalNumber =
            [NSDecimalNumber decimalNumberWithDecimal:decimal];
        failed += LC32Check("decimal-aggregate-argument",
            fabs(decimalNumber.doubleValue - 12.75) < 0.0000001,
            decimalNumber.doubleValue);

        NSDecimalNumber *initializedDecimalNumber =
            [[NSDecimalNumber alloc] initWithDecimal:decimal];
        failed += LC32Check("decimal-init-aggregate-argument",
            fabs(initializedDecimalNumber.doubleValue - 12.75) < 0.0000001,
            initializedDecimalNumber.doubleValue);
        [initializedDecimalNumber release];

        NSDecimal unchangedDecimal = decimal;
        const BOOL scannedInvalidDecimal =
            [decimalScanner scanDecimal:&unchangedDecimal];
        failed += LC32Check("failed-decimal-preserves-output",
            !scannedInvalidDecimal &&
                memcmp(&decimal, &unchangedDecimal, sizeof(decimal)) == 0,
            unchangedDecimal._mantissa[0]);

        NSScanner *nullDecimalScanner =
            [NSScanner scannerWithString:@"88"];
        const BOOL scannedNullDecimal =
            [nullDecimalScanner scanDecimal:NULL];
        failed += LC32Check("nullable-decimal-pointer",
            scannedNullDecimal && nullDecimalScanner.isAtEnd,
            scannedNullDecimal);

        /* This is the original generator regression: ARM32 declares the
         * CGFloat output as ^f, while the native ARM64 UIKit method is ^d. */
        float actualFontSize = -1.0f;
        const CGSize measured = [@"LiveExec32 scalar pointer bridge"
            sizeWithFont:[UIFont systemFontOfSize:24.0f]
            minFontSize:8.0f
            actualFontSize:&actualFontSize
            forWidth:90.0f
            lineBreakMode:NSLineBreakByWordWrapping];
        failed += LC32Check("arm32-cgfloat-to-native-cgfloat-pointer",
            isfinite(actualFontSize) && actualFontSize >= 8.0f &&
                actualFontSize <= 24.0f && isfinite(measured.width) &&
                isfinite(measured.height) && measured.width >= 0.0f &&
                measured.height >= 0.0f,
            actualFontSize);

        return failed ? 1 : 0;
    }
}

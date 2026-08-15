#import <UIKit/UIKit.h>

#include <math.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        NSString *text = @"LiveExec32 legacy text sizing";
        UIFont *font = [UIFont systemFontOfSize:24.0f];

        CGFloat actualWide = -1.0f;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        const CGSize wide = [text
            sizeWithFont:font
            minFontSize:8.0f
            actualFontSize:&actualWide
            forWidth:1000.0f
            lineBreakMode:NSLineBreakByTruncatingTail];

        CGFloat actualNarrow = -1.0f;
        const CGSize narrow = [text
            sizeWithFont:font
            minFontSize:8.0f
            actualFontSize:&actualNarrow
            forWidth:80.0f
            lineBreakMode:NSLineBreakByTruncatingTail];

        const CGSize withoutOutput = [text
            sizeWithFont:font
            minFontSize:8.0f
            actualFontSize:NULL
            forWidth:80.0f
            lineBreakMode:NSLineBreakByTruncatingTail];
#pragma clang diagnostic pop

        const BOOL widePassed = wide.width > 0.0f &&
            wide.height > 0.0f &&
            fabs((double)(actualWide - font.pointSize)) < 0.01;
        const BOOL narrowPassed = narrow.width > 0.0f &&
            narrow.width <= 80.01f && narrow.height > 0.0f &&
            actualNarrow >= 7.99f && actualNarrow <= font.pointSize;
        const BOOL nullPassed = withoutOutput.width > 0.0f &&
            withoutOutput.width <= 80.01f && withoutOutput.height > 0.0f;

        printf("legacy-string-size-wide: %s (%g,%g actual=%g)\n",
               widePassed ? "PASS" : "FAIL",
               wide.width, wide.height, actualWide);
        printf("legacy-string-size-narrow: %s (%g,%g actual=%g)\n",
               narrowPassed ? "PASS" : "FAIL",
               narrow.width, narrow.height, actualNarrow);
        printf("legacy-string-size-null-output: %s (%g,%g)\n",
               nullPassed ? "PASS" : "FAIL",
               withoutOutput.width, withoutOutput.height);
        return widePassed && narrowPassed && nullPassed ? 0 : 1;
    }
}

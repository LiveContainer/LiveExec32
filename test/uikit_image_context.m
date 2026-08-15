#import <UIKit/UIKit.h>

#include <stdio.h>

int main(void) {
    @autoreleasepool {
        UIGraphicsBeginImageContextWithOptions(
            CGSizeMake(4.0f, 3.0f), YES, 2.0f);
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        const BOOL imagePassed = image != nil &&
            image.size.width == 4.0f && image.size.height == 3.0f;
        printf("image-context-options: %s (%g,%g)\n",
               imagePassed ? "PASS" : "FAIL",
               image.size.width, image.size.height);

        NSData *jpeg = UIImageJPEGRepresentation(image, 0.75f);
        const BOOL jpegPassed = jpeg.length > 0;
        printf("image-jpeg-representation: %s (%lu bytes)\n",
               jpegPassed ? "PASS" : "FAIL",
               (unsigned long)jpeg.length);
        return imagePassed && jpegPassed ? 0 : 1;
    }
}

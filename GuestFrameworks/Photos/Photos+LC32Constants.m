#import <Photos/Photos.h>

#define LC32_PHOTOS_STRING(symbol, value) \
    NSString *const LC32_PHOTOS_##symbol __asm__("_" #symbol) = value;

LC32_PHOTOS_STRING(PHContentEditingInputCancelledKey,
    @"PHContentEditingInputCancelledKey")
LC32_PHOTOS_STRING(PHContentEditingInputErrorKey,
    @"PHContentEditingInputErrorKey")
LC32_PHOTOS_STRING(PHContentEditingInputResultIsInCloudKey,
    @"PHContentEditingInputResultIsInCloudKey")
LC32_PHOTOS_STRING(PHImageCancelledKey, @"PHImageCancelledKey")
LC32_PHOTOS_STRING(PHImageErrorKey, @"PHImageErrorKey")
LC32_PHOTOS_STRING(PHImageResultIsDegradedKey,
    @"PHImageResultIsDegradedKey")
LC32_PHOTOS_STRING(PHImageResultIsInCloudKey, @"PHImageResultIsInCloudKey")
LC32_PHOTOS_STRING(PHImageResultRequestIDKey, @"PHImageResultRequestIDKey")
LC32_PHOTOS_STRING(PHLivePhotoInfoCancelledKey,
    @"PHLivePhotoInfoCancelledKey")
LC32_PHOTOS_STRING(PHLivePhotoInfoErrorKey, @"PHLivePhotoInfoErrorKey")
LC32_PHOTOS_STRING(PHLivePhotoInfoIsDegradedKey,
    @"PHLivePhotoInfoIsDegradedKey")

#undef LC32_PHOTOS_STRING

const CGSize LC32_PHImageManagerMaximumSize
    __asm__("_PHImageManagerMaximumSize") = {-1.0f, -1.0f};

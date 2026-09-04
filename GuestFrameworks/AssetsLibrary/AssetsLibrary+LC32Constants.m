#import <AssetsLibrary/AssetsLibrary.h>
#import <Foundation/Foundation+LC32.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

/* Bind guest proxies to the native framework's canonical object constants. */
#define LC32_ASSETSLIBRARY_OBJECT_CONSTANTS(X) \
    X(ALAssetLibraryDeletedAssetGroupsKey) \
    X(ALAssetLibraryInsertedAssetGroupsKey) \
    X(ALAssetLibraryUpdatedAssetGroupsKey) \
    X(ALAssetLibraryUpdatedAssetsKey) \
    X(ALAssetPropertyAssetURL) \
    X(ALAssetPropertyDate) \
    X(ALAssetPropertyDuration) \
    X(ALAssetPropertyLocation) \
    X(ALAssetPropertyOrientation) \
    X(ALAssetPropertyRepresentations) \
    X(ALAssetPropertyType) \
    X(ALAssetPropertyURLs) \
    X(ALAssetTypePhoto) \
    X(ALAssetTypeUnknown) \
    X(ALAssetTypeVideo) \
    X(ALAssetsGroupPropertyName) \
    X(ALAssetsGroupPropertyPersistentID) \
    X(ALAssetsGroupPropertyType) \
    X(ALAssetsGroupPropertyURL) \
    X(ALAssetsLibraryChangedNotification) \
    X(ALAssetsLibraryErrorDomain) \
    X(ALErrorInvalidProperty)

#define LC32_DECLARE_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_DECL(__typeof__(name) name)
LC32_ASSETSLIBRARY_OBJECT_CONSTANTS(LC32_DECLARE_OBJECT_CONSTANT)
#undef LC32_DECLARE_OBJECT_CONSTANT

__attribute__((constructor))
static void LC32InitializeAssetsLibraryObjectConstants(void) {
    LC32LoadHostFramework("AssetsLibrary");
#define LC32_INITIALIZE_OBJECT_CONSTANT(name) LC32_CONST_STR_INIT(name);
    LC32_ASSETSLIBRARY_OBJECT_CONSTANTS(LC32_INITIALIZE_OBJECT_CONSTANT)
#undef LC32_INITIALIZE_OBJECT_CONSTANT
}

#undef LC32_ASSETSLIBRARY_OBJECT_CONSTANTS

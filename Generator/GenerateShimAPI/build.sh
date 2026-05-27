set -e
cd `dirname $0`

MACOSX_SDK_DIR="$(xcrun -sdk macosx --show-sdk-path)"
CATALYST_FLAGS="-target arm64-apple-ios-macabi -isysroot $MACOSX_SDK_DIR -isystem $MACOSX_SDK_DIR/System/iOSSupport/usr/include -iframework $MACOSX_SDK_DIR/System/iOSSupport/System/Library/Frameworks"

clang $CATALYST_FLAGS main.m -fmodules -framework QuartzCore -g -Wno-deprecated-declarations -o GenerateShimObjC
clang $CATALYST_FLAGS opengles.m -fmodules -framework QuartzCore -g -Wno-deprecated-declarations -o GenerateShimOpenGLES

ldid -S../../entitlements.plist GenerateShimObjC
ldid -S../../entitlements.plist GenerateShimOpenGLES

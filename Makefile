ARCHS := arm64
TARGET := iphone:clang:latest:16.0
GO_EASY_ON_ME := 1
#TARGET_CODESIGN = fastPathSign
PACKAGE_FORMAT := ipa

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = LiveExec32
#TOOL_NAME = LiveExec32

LiveExec32_FILES = \
	main.cpp debugger_server.cpp arm_dynarmic_cp15.cpp dynarmic.cpp filesystem.cpp variables.cpp \
	ap_getparents.c target.c \
	bridge.mm bridge.s log.m \
	HostFrameworks/Foundation/Foundation.mm \
	HostFrameworks/Foundation/NSString.mm \
	HostFrameworks/CoreGraphics/CoreGraphics.mm \
	HostFrameworks/AudioToolbox/AudioToolbox.mm \
	HostFrameworks/OpenAL/OpenAL.mm \
	HostFrameworks/OpenGLES/OpenGLES.mm \
	HostFrameworks/UIKit/UIKit.mm
LiveExec32_CFLAGS = -Iinclude -DDYNARMIC_MASTER
LiveExec32_CCFLAGS = -std=c++17
LiveExec32_LDFLAGS = -L./Resources/Frameworks -ldynarmic
LiveExec32_FRAMEWORKS = AudioToolbox OpenAL OpenGLES
LiveExec32_CODESIGN_FLAGS = -Sentitlements.plist
#LiveExec32_INSTALL_PATH = /usr/local/bin

# include gdbstub. Note that mini-gdbstub doesn't support armv7 but it doesn't care anyways
LiveExec32_CFLAGS += -I./External/mini-gdbstub/include
LiveExec32_LDFLAGS += -L./External/mini-gdbstub/build
LiveExec32_LIBRARIES += gdbstub

before-all::
	$(MAKE) -C External/mini-gdbstub ARCH=rv32 CC="cc -isysroot $(ISYSROOT) -miphoneos-version-min=16.0"

after-all::
	@vtool -arch arm64 -set-build-version 6 11.0 11.0 -replace -output $(THEOS_OBJ_DIR)/LiveExec32.app/LiveExec32{,}
	@vtool -arch arm64 -set-build-version 6 11.0 11.0 -replace -output $(THEOS_OBJ_DIR)/LiveExec32.app/Frameworks/libdynarmic.dylib{,}
	@ldid -S $(THEOS_OBJ_DIR)/LiveExec32.app

internal-clean::
	$(MAKE) -C External/mini-gdbstub clean

include $(THEOS_MAKE_PATH)/application.mk
#include $(THEOS_MAKE_PATH)/tool.mk

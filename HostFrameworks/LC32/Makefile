ARCHS := arm64
TARGET := iphone:clang:latest:16.0
FINALPACKAGE = 1
GO_EASY_ON_ME := 1
STRIP = 0
# Avoid relying on an intermediate signature: the post-link hook signs the
# rewritten framework, and the root app signs its embedded copy again.
TARGET_CODESIGN =

include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = LiveExec32Shared

LiveExec32Shared_FILES = \
	LiveExec32Shared.cpp guest_bootstrap.cpp debugger_server.cpp \
	arm_dynarmic_cp15.cpp dynarmic.cpp dynarmic_syscalls.cpp \
	dynarmic_memory.cpp dynarmic_callbacks.cpp dynarmic_thread_state.cpp \
	dynarmic_native_jit.cpp dynarmic_psynch.cpp dynarmic_workqueue.cpp \
	dynarmic_core.cpp filesystem.cpp variables.cpp ap_getparents.c target.c \
	bridge.mm block_bridge.mm bridge.s log.m \
	../Foundation/Foundation.mm ../Foundation/NSString.mm \
	../CoreFoundation/CoreFoundation.mm ../CFNetwork/CFNetwork.mm \
	../Security/Security.mm ../CoreGraphics/CoreGraphics.mm \
	../CoreText/CoreText.mm ../AudioToolbox/AudioToolbox.mm \
	../OpenAL/OpenAL.mm ../OpenGLES/OpenGLES.mm ../UIKit/UIKit.mm
LiveExec32Shared_CFLAGS = \
	-I. -I../../include -DDYNARMIC_MASTER \
	-I../../External/mini-gdbstub/include
LiveExec32Shared_CCFLAGS = -std=c++17
LiveExec32Shared_LDFLAGS = \
	-L../../Resources/Frameworks -ldynarmic \
	-L../../External/mini-gdbstub/build
LiveExec32Shared_LIBRARIES = gdbstub
LiveExec32Shared_FRAMEWORKS = \
	AudioToolbox CFNetwork GameKit OpenAL OpenGLES Security UIKit
LiveExec32Shared_PUBLIC_HEADERS = LiveExec32Shared.h
LiveExec32Shared_RESOURCE_DIRS = Resources
LiveExec32Shared_INSTALL_PATH = @rpath
LiveExec32Shared_INSTALL = 0

# mini-gdbstub is a static dependency of this framework rather than of the
# launcher, which also keeps direct framework builds complete.
before-LiveExec32Shared-all::
	$(MAKE) -C ../../External/mini-gdbstub ARCH=rv32 CC="cc -isysroot $(ISYSROOT) -miphoneos-version-min=16.0"

# The input dylib still identifies itself through @executable_path. That token
# points at LiveContainer when it loads this app, so make the dependency
# relative to the framework image instead.
after-LiveExec32Shared-all::
	@set -e; \
	binary="$(THEOS_OBJ_DIR)/LiveExec32Shared.framework/LiveExec32Shared"; \
	dependency="$$(otool -L "$$binary" | awk '/libdynarmic\.dylib/{print $$1; exit}')"; \
	if [ -z "$$dependency" ]; then \
		echo "LiveExec32Shared is missing its libdynarmic dependency" >&2; \
		exit 1; \
	fi; \
	if [ "$$dependency" != '@loader_path/../libdynarmic.dylib' ]; then \
		install_name_tool -change "$$dependency" \
			'@loader_path/../libdynarmic.dylib' "$$binary"; \
	fi; \
	ldid -S "$$binary"

internal-clean::
	$(MAKE) -C ../../External/mini-gdbstub clean

include $(THEOS_MAKE_PATH)/framework.mk

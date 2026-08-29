ARCHS := arm64
TARGET := iphone:clang:latest:16.0
FINALPACKAGE = 1
GO_EASY_ON_ME := 1
STRIP = 0
# The root app signs the embedded copy after its optional Catalyst rewrite.
TARGET_CODESIGN =

include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = LiveExec32Shared

DYNARMIC_ROOT := $(abspath ../../External/dynarmic)
DYNARMIC_BUILD_DIR := $(THEOS_PROJECT_DIR)/.theos/obj/dynarmic
DYNARMIC_STATIC_LIBS := \
	$(DYNARMIC_BUILD_DIR)/src/dynarmic/libdynarmic.a \
	$(DYNARMIC_BUILD_DIR)/externals/mcl/src/libmcl.a \
	$(DYNARMIC_BUILD_DIR)/externals/fmt/libfmt.a

LiveExec32Shared_FILES = \
	LiveExec32Shared.cpp guest_bootstrap.cpp debugger_server.cpp \
	crash_exception.mm \
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
	-I. -I$(DYNARMIC_ROOT)/src -I../../include -DDYNARMIC_MASTER \
	-I../../External/mini-gdbstub/include
LiveExec32Shared_CCFLAGS = -std=c++17
crash_exception.mm_CFLAGS = -fobjc-arc
LiveExec32Shared_OBJ_FILES = $(DYNARMIC_STATIC_LIBS)
LiveExec32Shared_LDFLAGS = -L../../External/mini-gdbstub/build
LiveExec32Shared_LIBRARIES = gdbstub
LiveExec32Shared_FRAMEWORKS = \
	AudioToolbox CFNetwork CoreFoundation Foundation GameKit IOKit \
	OpenAL OpenGLES Security UIKit
LiveExec32Shared_PUBLIC_HEADERS = LiveExec32Shared.h
LiveExec32Shared_RESOURCE_DIRS = Resources
LiveExec32Shared_INSTALL_PATH = @rpath
LiveExec32Shared_INSTALL = 0

# mini-gdbstub is a static dependency of this framework rather than of the
# launcher, which also keeps direct framework builds complete.
before-LiveExec32Shared-all:: lc32-dynarmic-static
	$(MAKE) -C ../../External/mini-gdbstub ARCH=rv32 CC="cc -isysroot $(ISYSROOT) -miphoneos-version-min=16.0"

internal-clean::
	$(MAKE) -C ../../External/mini-gdbstub clean

include $(THEOS_MAKE_PATH)/framework.mk

# Theos otherwise treats its before-hook and internal framework build as
# parallel siblings when explicit parallel mode is enabled. Dynarmic must
# finish updating its archives before the framework link is evaluated.
.NOTPARALLEL: internal-framework-all

.PHONY: lc32-dynarmic-static
lc32-dynarmic-static:
	@test -f "$(DYNARMIC_ROOT)/CMakeLists.txt" || { \
		echo "External/dynarmic is missing; initialize the submodule" >&2; \
		exit 1; \
	}
	cmake --no-warn-unused-cli \
		-S "$(DYNARMIC_ROOT)" -B "$(DYNARMIC_BUILD_DIR)" \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DDYNARMIC_USE_BUNDLED_EXTERNALS=ON \
		-DDYNARMIC_FRONTENDS=A32 \
		-DBUILD_TESTING=OFF \
		-DDYNARMIC_TESTS=OFF \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		-DCMAKE_CROSSCOMPILING=true \
		-DCMAKE_SYSTEM_NAME=Darwin \
		-DCMAKE_SYSTEM_PROCESSOR=aarch64 \
		-DCMAKE_OSX_SYSROOT="$(ISYSROOT)" \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
		-DCMAKE_C_FLAGS="-arch arm64"
	cmake --build "$(DYNARMIC_BUILD_DIR)" \
		--target dynarmic --parallel 4
	@for archive in $(DYNARMIC_STATIC_LIBS); do \
		test -f "$$archive" || { \
			echo "Dynarmic build did not produce $$archive" >&2; \
			exit 1; \
		}; \
	done

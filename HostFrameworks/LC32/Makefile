ARCHS := arm64
TARGET := iphone:clang:latest:15.0
FINALPACKAGE = 1
GO_EASY_ON_ME := 1
STRIP = 0
# Theos otherwise pairs STRIP=0 with -O0. Keep symbols for device traces while
# compiling the emulator and bridge hot paths as release code.
OPTFLAG = -O2
# Verbose bridge, loader, memory, and syscall traces are opt-in, independent
# of optimization or debug symbols. Errors remain enabled in every build.
LC32_DEBUG_LOGS ?= 0
# The root app signs the embedded copy after its optional Catalyst rewrite.
TARGET_CODESIGN =

include ../../module-cache.mk
include ../../version.mk

include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = LiveExec32Shared

LC32_BUILD_INFO_HEADER := $(THEOS_PROJECT_DIR)/.theos/LC32BuildInfo.h
# Keep changing Git metadata local to the logging translation unit.
log.m_CFLAGS = -include "$(LC32_BUILD_INFO_HEADER)"

DYNARMIC_ROOT := $(abspath ../../External/dynarmic)
DYNARMIC_BUILD_DIR := $(THEOS_PROJECT_DIR)/.theos/obj/dynarmic
DYNARMIC_STATIC_LIBS := \
	$(DYNARMIC_BUILD_DIR)/src/dynarmic/libdynarmic.a \
	$(DYNARMIC_BUILD_DIR)/externals/mcl/src/libmcl.a \
	$(DYNARMIC_BUILD_DIR)/externals/fmt/libfmt.a

# CMake 4 split developer diagnostics into author and policy categories and
# made its older aggregate spellings noisy. Keep both the local CMake 3 flow
# and the macOS CI CMake 4 flow quiet without hiding Dynarmic's own messages.
LC32_CMAKE_VERSION := $(shell cmake --version 2>/dev/null | \
	awk 'NR == 1 { print $$3 }')
LC32_CMAKE_MAJOR := $(word 1,$(subst ., ,$(LC32_CMAKE_VERSION)))
LC32_CMAKE_MINOR := $(word 2,$(subst ., ,$(LC32_CMAKE_VERSION)))
LC32_CMAKE_IS_V4_OR_NEWER := $(shell \
	test "$(LC32_CMAKE_MAJOR)" -ge 4 2>/dev/null && echo 1)
LC32_CMAKE_HAS_DIAGNOSTIC_CATEGORIES := $(shell \
	if test "$(LC32_CMAKE_MAJOR)" -gt 4 2>/dev/null; then echo 1; \
	elif test "$(LC32_CMAKE_MAJOR)" -eq 4 2>/dev/null && \
	     test "$(LC32_CMAKE_MINOR)" -ge 4 2>/dev/null; then echo 1; fi)
ifeq ($(LC32_CMAKE_HAS_DIAGNOSTIC_CATEGORIES),1)
DYNARMIC_CMAKE_WARNING_FLAGS := \
	-Wno-author -Wno-policy -Wno-deprecated -Wno-unused-cli
else
DYNARMIC_CMAKE_WARNING_FLAGS := \
	--no-warn-unused-cli -Wno-dev -Wno-deprecated
endif
ifeq ($(LC32_CMAKE_IS_V4_OR_NEWER),1)
DYNARMIC_CMAKE_POLICY_FLAGS := -DCMAKE_POLICY_VERSION_MINIMUM=3.5
else
DYNARMIC_CMAKE_POLICY_FLAGS :=
endif

LiveExec32Shared_FILES = \
	LiveExec32Shared.cpp guest_bootstrap.cpp debugger_server.cpp \
	crash_exception.mm guest_dispatch.mm guest_timer_queue.cpp guest_timers.cpp \
	arm_dynarmic_cp15.cpp dynarmic.cpp dynarmic_syscalls.cpp \
	darwin_file_syscalls.cpp guest_mach_messages.cpp guest_mach_exceptions.cpp \
	dynarmic_memory.cpp dynarmic_callbacks.cpp dynarmic_thread_state.cpp \
	dynarmic_native_jit.cpp dynarmic_psynch.cpp dynarmic_workqueue.cpp \
	dynarmic_core.cpp filesystem.cpp variables.cpp ap_getparents.c target.c \
	bridge.mm block_bridge.mm bridge.s log.m \
	../Foundation/Foundation.mm ../Foundation/NSString.mm \
	../CoreFoundation/CoreFoundation.mm ../CFNetwork/CFNetwork.mm \
	../Security/Security.mm ../CoreGraphics/CoreGraphics.mm \
	../ImageIO/ImageIO.mm \
	../CoreText/CoreText.mm ../CoreMedia/CoreMedia.mm ../CoreVideo/CoreVideo.mm \
	../AudioToolbox/AudioToolbox.mm \
	../Accelerate/Accelerate.mm \
	../OpenAL/OpenAL.mm ../OpenGLES/OpenGLES.mm ../UIKit/UIKit.mm \
	../UIKit/LegacyAutoLayout.mm ../UIKit/LegacyFonts.mm ../UIKit/LegacyAlerts.mm \
	../UIKit/LegacyRotation.mm ../UIKit/LegacyNibLoading.mm
LiveExec32Shared_CFLAGS = \
	-I. -I$(DYNARMIC_ROOT)/src -I../../include -DDYNARMIC_MASTER \
	-I../../External/mini-gdbstub/include -DLC32_DEBUG_LOGS=$(LC32_DEBUG_LOGS)
LiveExec32Shared_CCFLAGS = -std=c++17
crash_exception.mm_CFLAGS = -fobjc-arc
../UIKit/LegacyFonts.mm_CFLAGS = -fobjc-arc
../UIKit/LegacyAlerts.mm_CFLAGS = -fobjc-arc
../UIKit/LegacyRotation.mm_CFLAGS = -fobjc-arc
LiveExec32Shared_OBJ_FILES = $(DYNARMIC_STATIC_LIBS)
LiveExec32Shared_LDFLAGS = -L../../External/mini-gdbstub/build -Wl,-weak-lMobileGestalt
LiveExec32Shared_LIBRARIES = gdbstub
LiveExec32Shared_FRAMEWORKS = \
	Accelerate AudioToolbox CFNetwork CoreFoundation CoreMedia CoreVideo Foundation GameKit IOKit \
	ImageIO OpenAL OpenGLES QuartzCore Security UIKit
LiveExec32Shared_PUBLIC_HEADERS = LiveExec32Shared.h
LiveExec32Shared_RESOURCE_DIRS = Resources
LiveExec32Shared_INSTALL_PATH = @rpath
LiveExec32Shared_INSTALL = 0

# mini-gdbstub is a static dependency of this framework rather than of the
# launcher, which also keeps direct framework builds complete.
before-LiveExec32Shared-all:: lc32-build-info lc32-dynarmic-static
	$(MAKE) -C ../../External/mini-gdbstub ARCH=rv32 CC="cc -isysroot $(ISYSROOT) -miphoneos-version-min=15.0"

.PHONY: lc32-build-info
lc32-build-info:
	/bin/bash "$(LC32_REPO_ROOT)/Scripts/build-info.sh" \
		--root "$(LC32_REPO_ROOT)" --output "$(LC32_BUILD_INFO_HEADER)"

after-LiveExec32Shared-all::
	$(call lc32_stamp_version,$(THEOS_OBJ_DIR)/LiveExec32Shared.framework/Info.plist)

internal-clean::
	$(MAKE) -C ../../External/mini-gdbstub clean

include $(THEOS_MAKE_PATH)/framework.mk

# Theos otherwise treats its before-hook and internal framework build as
# parallel siblings when explicit parallel mode is enabled. Dynarmic must
# finish updating its archives before the framework link is evaluated.
.NOTPARALLEL: internal-framework-all

# The nested CMake build uses a fixed worker count. Its build command drops the
# parent Theos jobserver instead of advertising it and then overriding it.
# Match the framework's iOS 15 minimum and keep libc++ availability enabled.
.PHONY: lc32-dynarmic-static
lc32-dynarmic-static:
	@test -f "$(DYNARMIC_ROOT)/CMakeLists.txt" || { \
		echo "External/dynarmic is missing; initialize the submodule" >&2; \
		exit 1; \
	}
	cmake $(DYNARMIC_CMAKE_WARNING_FLAGS) \
		-S "$(DYNARMIC_ROOT)" -B "$(DYNARMIC_BUILD_DIR)" \
		$(DYNARMIC_CMAKE_POLICY_FLAGS) \
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
		-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
		-DCMAKE_C_FLAGS="-arch arm64"
	env -u MAKEFLAGS cmake --build "$(DYNARMIC_BUILD_DIR)" \
		--target dynarmic --parallel 4
	@for archive in $(DYNARMIC_STATIC_LIBS); do \
		test -f "$$archive" || { \
			echo "Dynarmic build did not produce $$archive" >&2; \
			exit 1; \
		}; \
	done

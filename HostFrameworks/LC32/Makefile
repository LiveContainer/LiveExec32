ARCHS := arm64
TARGET := iphone:clang:latest:15.0
FINALPACKAGE = 1
GO_EASY_ON_ME := 1
STRIP = 0
# Theos otherwise pairs STRIP=0 with -O0. Keep symbols for device traces while
# compiling the emulator and bridge hot paths as release code.
OPTFLAG = -O2
# The root app signs the embedded copy after its optional Catalyst rewrite.
TARGET_CODESIGN =

include ../../module-cache.mk

include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = LiveExec32Shared

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
	crash_exception.mm \
	arm_dynarmic_cp15.cpp dynarmic.cpp dynarmic_syscalls.cpp \
	darwin_file_syscalls.cpp \
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
	$(MAKE) -C ../../External/mini-gdbstub ARCH=rv32 CC="cc -isysroot $(ISYSROOT) -miphoneos-version-min=15.0"

internal-clean::
	$(MAKE) -C ../../External/mini-gdbstub clean

include $(THEOS_MAKE_PATH)/framework.mk

# Theos otherwise treats its before-hook and internal framework build as
# parallel siblings when explicit parallel mode is enabled. Dynarmic must
# finish updating its archives before the framework link is evaluated.
.NOTPARALLEL: internal-framework-all

# The nested CMake build uses a fixed worker count. Its build command drops the
# parent Theos jobserver instead of advertising it and then overriding it.
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
		-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
		-DCMAKE_C_FLAGS="-arch arm64"
	env -u MAKEFLAGS cmake --build "$(DYNARMIC_BUILD_DIR)" \
		--target dynarmic --parallel 4
	@for archive in $(DYNARMIC_STATIC_LIBS); do \
		test -f "$$archive" || { \
			echo "Dynarmic build did not produce $$archive" >&2; \
			exit 1; \
		}; \
	done

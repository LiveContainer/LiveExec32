ARCHS := armv7s
TARGET := iphone:clang:16.5:10.3
FINALPACKAGE = 1
STRIP = 0
.DEFAULT_GOAL := all
GO_EASY_ON_ME = 1

# Theos normally serializes product targets and only parallelizes source files
# within one framework.  Let the top-level guest build fan independent
# frameworks out through GNU Make's shared jobserver; instance submakes retain
# Theos's normal phase ordering.
ifeq ($(THEOS_CURRENT_INSTANCE),)
_THEOS_MAKE_PARALLEL := yes
endif

include guest-sdk.mk

MANUAL_FRAMEWORKS_ROOT := ../GuestFrameworks
GENERATED_FRAMEWORKS_ROOT := $(MANUAL_FRAMEWORKS_ROOT)/.generated
GENERATED_FRAMEWORKS_STAMP := $(GENERATED_FRAMEWORKS_ROOT)/.complete

ifeq ($(strip $(MAKECMDGOALS)),)
LC32_REQUIRE_GENERATED_FRAMEWORKS := 1
else ifneq ($(strip $(filter-out clean generate-shims sdk,$(MAKECMDGOALS))),)
LC32_REQUIRE_GENERATED_FRAMEWORKS := 1
endif

ifeq ($(LC32_REQUIRE_GENERATED_FRAMEWORKS),1)
ifeq ($(wildcard $(GENERATED_FRAMEWORKS_STAMP)),)
$(error Generated guest shims are missing; run gmake -C GuestMakefile generate-shims)
endif
endif

include ../module-cache.mk

ADDITIONAL_CFLAGS = \
  -I$(abspath ../include) \
  -I$(MANUAL_FRAMEWORKS_ROOT) \
  -Wno-deprecated-module-dot-map \
  -F$(ISYSROOT)/System/Library/Frameworks/AVFoundation.framework/Frameworks
ADDITIONAL_LDFLAGS = -fno-autolink -F$(THEOS_OBJ_DIR)
include $(THEOS)/makefiles/common.mk

# THEOS_INSTANCE_NAME is not referenced by the SDK modules. Excluding it from
# their context hash lets every guest framework share the same MRC/ARC PCMs.
LC32_SHARE_GUEST_MODULE_CACHE ?= 1
ifeq ($(LC32_SHARE_GUEST_MODULE_CACHE),1)
MODULESFLAGS += -fmodules-ignore-macro=THEOS_INSTANCE_NAME
endif

BOOTSTRAP_FRAMEWORKS := LC32 AudioToolbox CoreFoundation CoreGraphics CoreText CFNetwork Foundation
manual_framework_dirs = $(patsubst %/,%,$(wildcard $(MANUAL_FRAMEWORKS_ROOT)/*/))
generated_framework_dirs = $(patsubst %/,%,$(wildcard $(GENERATED_FRAMEWORKS_ROOT)/*/))
MANUAL_FRAMEWORKS := $(notdir $(call manual_framework_dirs))
GENERATED_FRAMEWORKS := $(notdir $(call generated_framework_dirs))
GUEST_FRAMEWORKS := $(sort $(MANUAL_FRAMEWORKS) $(GENERATED_FRAMEWORKS))
FRAMEWORK_NAME = $(BOOTSTRAP_FRAMEWORKS) $(filter-out $(BOOTSTRAP_FRAMEWORKS),$(GUEST_FRAMEWORKS))

framework_source_dirs = $(wildcard \
  $(MANUAL_FRAMEWORKS_ROOT)/$(1) \
  $(GENERATED_FRAMEWORKS_ROOT)/$(1))
framework_sources = $(shell find $(call framework_source_dirs,$(1)) \
  \( -iname \*.m -o -iname \*.s \))

# Common variables
$(THEOS_CURRENT_INSTANCE)_FILES = $(call framework_sources,$(THEOS_CURRENT_INSTANCE))
$(THEOS_CURRENT_INSTANCE)_INSTALL_PATH = /System/Library/Frameworks
$(THEOS_CURRENT_INSTANCE)_LDFLAGS = \
  -compatibility_version 1.0.0 \
  -current_version 1.0.0
ifneq ($(THEOS_CURRENT_INSTANCE),LC32)
$(THEOS_CURRENT_INSTANCE)_FRAMEWORKS = LC32
endif

# TODO: symlink instead
#AVFAudio_INSTALL_PATH = /System/Library/Frameworks/AVFoundation.framework/Frameworks
FileProvider_INSTALL_PATH = /System/Library/PrivateFrameworks

LC32_LIBRARIES = objc.A

AVFoundation_LDFLAGS = \
  -compatibility_version 1.0.0 \
  -current_version 2.0.0 \
  -Wl,-reexport_library,$(THEOS_OBJ_DIR)/AVFAudio.framework/AVFAudio

CoreFoundation_FRAMEWORKS = LC32
CoreFoundation_LDFLAGS = \
  -compatibility_version 478.23.0 \
  -current_version 478.23.0 -fno-autolink \
  -Wl,-reexport_library,$(ISYSROOT)/usr/lib/libobjc.A.tbd

Foundation_FRAMEWORKS = LC32
Foundation_FILES = $(filter-out \
  $(GENERATED_FRAMEWORKS_ROOT)/Foundation/NSThread.m, \
  $(call framework_sources,Foundation))
Foundation_LDFLAGS = \
  -compatibility_version 678.24.0 \
  -current_version 678.24.0 \
  -Wl,-reexport_library,$(THEOS_OBJ_DIR)/CoreFoundation.framework/CoreFoundation \
  -Wl,-reexport_library,$(THEOS_OBJ_DIR)/CFNetwork.framework/CFNetwork

AudioToolbox_FRAMEWORKS = LC32
AudioToolbox_LDFLAGS = \
  -compatibility_version 1.0.0 \
  -current_version 1.0.0

CFNetwork_FRAMEWORKS = LC32
CFNetwork_LDFLAGS = \
  -compatibility_version 1.0.0 \
  -current_version 1.0.0

CoreGraphics_FRAMEWORKS = LC32
CoreGraphics_LDFLAGS = \
  -compatibility_version 359.4.0 \
  -current_version 359.4.0

CoreText_FRAMEWORKS = LC32
CoreText_LDFLAGS = \
  -compatibility_version 359.4.0 \
  -current_version 359.4.0

OpenGLES_FRAMEWORKS = LC32
OpenGLES_LDFLAGS = \
  -compatibility_version 1.0.0 \
  -current_version 1.0.0

QuartzCore_FRAMEWORKS = LC32
QuartzCore_LDFLAGS = \
  -compatibility_version 1.6.0 \
  -current_version 1.6.0

# UIKit needs ARC for weak properties
UIKit_CFLAGS = -fobjc-arc
UIKit_FRAMEWORKS = LC32
UIKit_LDFLAGS = \
  -compatibility_version 1.0.0 \
  -current_version 1.0.0

# These SDK headers require ARC for weak Objective-C properties.
MapKit_CFLAGS = -fobjc-arc
StoreKit_CFLAGS = -fobjc-arc
WatchKit_CFLAGS = -fobjc-arc
WebKit_CFLAGS = -fobjc-arc

# Advertising identifiers are intentionally unavailable on current iOS.
# Keep the old API usable without forwarding it to a host selector that has
# been removed from recent simulator runtimes.
AdSupport_FILES = $(filter-out \
  $(GENERATED_FRAMEWORKS_ROOT)/AdSupport/ASIdentifierManager.m, \
  $(call framework_sources,AdSupport))

.PHONY: generate-shims
generate-shims:
	./generate-shims.sh

include $(THEOS_MAKE_PATH)/framework.mk

# Theos can fan framework builds out from internal-all, and its convenience
# targets bypass before-all. Gate both paths so no compiler observes a partial
# or missing SDK, including when parallel building is explicitly enabled.
GUEST_FRAMEWORK_BUILD_TARGETS := $(FRAMEWORK_NAME:=.all.framework.variables)
$(FRAMEWORK_NAME) $(GUEST_FRAMEWORK_BUILD_TARGETS): | $(_THEOS_BUILD_SESSION_FILE)
ifneq ($(strip $(LC32_GUEST_SDK_DEPENDENCY)),)
before-all:: $(LC32_GUEST_SDK_DEPENDENCY)
$(FRAMEWORK_NAME) $(GUEST_FRAMEWORK_BUILD_TARGETS): | $(LC32_GUEST_SDK_DEPENDENCY)
endif

# Preserve Theos's before/internal/after ordering at the top level while the
# framework prerequisites of internal-all run concurrently.  Every guest
# framework links LC32, and the two re-export relationships below consume
# binaries produced by this same build, so encode those ordering constraints.
ifeq ($(THEOS_CURRENT_INSTANCE),)
.NOTPARALLEL: all clean clean-packages stage package install uninstall do commands
$(filter-out LC32,$(FRAMEWORK_NAME)): | LC32
$(filter-out LC32.all.framework.variables,$(GUEST_FRAMEWORK_BUILD_TARGETS)): | \
  LC32.all.framework.variables
Foundation: | CoreFoundation CFNetwork
Foundation.all.framework.variables: | \
  CoreFoundation.all.framework.variables CFNetwork.all.framework.variables
AVFoundation: | AVFAudio
AVFoundation.all.framework.variables: | AVFAudio.all.framework.variables
endif

# Exclude linking against CoreFoundation and Foundation for themselves
ifeq ($(THEOS_CURRENT_INSTANCE), $(filter $(THEOS_CURRENT_INSTANCE), CoreFoundation Foundation))
ifeq ($(_THEOS_CURRENT_OPERATION), compile)
  _THEOS_INTERNAL_LDFLAGS := $(subst -framework Foundation -framework CoreFoundation,,$(_THEOS_INTERNAL_LDFLAGS))
  _THEOS_INTERNAL_LDFLAGS := $(subst -lobjc,,$(_THEOS_INTERNAL_LDFLAGS))
endif
endif

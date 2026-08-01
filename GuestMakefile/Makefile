ARCHS := armv7s
TARGET := iphone:clang:16.5:10.3
ISYSROOT := $(abspath ../../SDKs/iPhoneOS10.3.sdk)
GO_EASY_ON_ME = 1

export CLANG_MODULE_CACHE_PATH := $(CURDIR)/.theos/module-cache

ADDITIONAL_CFLAGS = \
  -I../GuestFrameworks \
  -F$(ISYSROOT)/System/Library/Frameworks/AVFoundation.framework/Frameworks
ADDITIONAL_LDFLAGS = -fno-autolink -F$(THEOS_OBJ_DIR)
include $(THEOS)/makefiles/common.mk

BOOTSTRAP_FRAMEWORKS := LC32 AudioToolbox CoreFoundation CoreGraphics CoreText CFNetwork Foundation
GUEST_FRAMEWORKS := $(notdir $(wildcard ../GuestFrameworks/*))
FRAMEWORK_NAME = $(BOOTSTRAP_FRAMEWORKS) $(filter-out $(BOOTSTRAP_FRAMEWORKS),$(GUEST_FRAMEWORKS))

# Common variables
$(THEOS_CURRENT_INSTANCE)_FILES = $(shell find ../GuestFrameworks/$(THEOS_CURRENT_INSTANCE) \( -iname \*.m -o -iname \*.s \))
$(THEOS_CURRENT_INSTANCE)_INSTALL_PATH = /System/Library/Frameworks
$(THEOS_CURRENT_INSTANCE)_LDFLAGS = \
  -compatibility_version 1.0.0 \
  -current_version 1.0.0
ifneq ($(THEOS_CURRENT_INSTANCE),LC32)
$(THEOS_CURRENT_INSTANCE)_FRAMEWORKS = LC32
endif

AVFAudio_INSTALL_PATH = /System/Library/Frameworks/AVFoundation.framework/Frameworks
FileProvider_INSTALL_PATH = /System/Library/PrivateFrameworks

LC32_LIBRARIES = objc.A

CoreFoundation_FRAMEWORKS = LC32
CoreFoundation_LDFLAGS = \
  -compatibility_version 478.23.0 \
  -current_version 478.23.0 -fno-autolink \
  -Wl,-reexport_library,$(abspath ../tmp/ramdisk/usr/lib/libobjc.A.dylib)

Foundation_FRAMEWORKS = LC32
Foundation_FILES = $(filter-out \
  ../GuestFrameworks/Foundation/NSHTTPCookie.m \
  ../GuestFrameworks/Foundation/NSHTTPCookieStorage.m \
  ../GuestFrameworks/Foundation/NSHTTPURLResponse.m, \
  $(shell find ../GuestFrameworks/Foundation \( -iname \*.m -o -iname \*.s \)))
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

include $(THEOS_MAKE_PATH)/framework.mk

# Exclude linking against CoreFoundation and Foundation for themselves
ifeq ($(THEOS_CURRENT_INSTANCE), $(filter $(THEOS_CURRENT_INSTANCE), CoreFoundation Foundation))
ifeq ($(_THEOS_CURRENT_OPERATION), compile)
  _THEOS_INTERNAL_LDFLAGS := $(subst -framework Foundation -framework CoreFoundation,,$(_THEOS_INTERNAL_LDFLAGS))
  _THEOS_INTERNAL_LDFLAGS := $(subst -lobjc,,$(_THEOS_INTERNAL_LDFLAGS))
endif
endif

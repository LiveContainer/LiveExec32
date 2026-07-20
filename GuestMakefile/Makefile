ARCHS := armv7s
TARGET := iphone:clang:16.5:10.3
GO_EASY_ON_ME = 1

ADDITIONAL_CFLAGS = -I../GuestFrameworks
ADDITIONAL_LDFLAGS = -fno-autolink -F$(THEOS_OBJ_DIR)
LOCAL_INSTALL_PATH = /System/Library/Frameworks
include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = LC32 AudioToolbox CoreFoundation CoreGraphics CoreText Foundation CFNetwork OpenGLES QuartzCore UIKit

# Common variables
$(THEOS_CURRENT_INSTANCE)_FILES = $(shell find ../GuestFrameworks/$(THEOS_CURRENT_INSTANCE) \( -iname \*.m -o -iname \*.s \))

LC32_LIBRARIES = objc.A

CoreFoundation_FRAMEWORKS = LC32
CoreFoundation_LDFLAGS = \
  -compatibility_version 478.23.0 \
  -current_version 478.23.0 -fno-autolink \
  -Wl,-reexport_library,/var/mobile/Documents/TrollExperiments/CProjects/dynarmic/iOS10RAMDisk/usr/lib/libobjc.A.dylib

Foundation_FRAMEWORKS = LC32
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

include $(THEOS_MAKE_PATH)/framework.mk

# Exclude linking against CoreFoundation and Foundation for themselves
ifeq ($(THEOS_CURRENT_INSTANCE), $(filter $(THEOS_CURRENT_INSTANCE), CoreFoundation Foundation))
ifeq ($(_THEOS_CURRENT_OPERATION), compile)
  _THEOS_INTERNAL_LDFLAGS := $(subst -framework Foundation -framework CoreFoundation,,$(_THEOS_INTERNAL_LDFLAGS))
  _THEOS_INTERNAL_LDFLAGS := $(subst -lobjc,,$(_THEOS_INTERNAL_LDFLAGS))
endif
endif

ARCHS := arm64
TARGET := iphone:clang:latest:15.0
FINALPACKAGE = 1
GO_EASY_ON_ME := 1
STRIP = 0
# Sign once after linking; the root app signs its embedded copy again after
# the optional Catalyst rewrite.
TARGET_CODESIGN =

include ../../module-cache.mk

include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = LC32HelpUI

LC32HelpUI_FILES = LC32HelpUI.m
LC32HelpUI_CFLAGS = -fobjc-arc -I.
LC32HelpUI_FRAMEWORKS = UIKit
LC32HelpUI_PUBLIC_HEADERS = LC32HelpUI.h
LC32HelpUI_RESOURCE_DIRS = Resources
LC32HelpUI_INSTALL_PATH = @rpath
LC32HelpUI_INSTALL = 0

after-LC32HelpUI-all::
	@ldid -S "$(THEOS_OBJ_DIR)/LC32HelpUI.framework/LC32HelpUI"

include $(THEOS_MAKE_PATH)/framework.mk

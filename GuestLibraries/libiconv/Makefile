ARCHS := armv7s
TARGET := iphone:clang:16.5:10.3
FINALPACKAGE = 1
GO_EASY_ON_ME = 1
STRIP = 0

LIBRARY_NAME = libiconv.2
libiconv.2_FILES = iconv.c iconv_close.c libiconv_apple.c
libiconv.2_INSTALL_PATH = /usr/lib
libiconv.2_INSTALL = 0
libiconv.2_LDFLAGS = \
	-compatibility_version 7.0.0 \
	-current_version 7.0.0

include ../../GuestMakefile/guest-sdk.mk

include $(THEOS)/makefiles/common.mk

ifneq ($(strip $(LC32_GUEST_SDK_DEPENDENCY)),)
before-all:: $(LC32_GUEST_SDK_DEPENDENCY)
endif

include $(THEOS_MAKE_PATH)/library.mk

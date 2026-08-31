ARCHS := arm64 arm64e
TARGET := iphone:clang:latest:16.0
FINALPACKAGE = 1
STRIP = 0
INSTALL_TARGET_PROCESSES = installd

include ../module-cache.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiveExec32Injector

LiveExec32Injector_FILES = Tweak.x FatMachO.c MachOImage.c AdHocSigner.c
LiveExec32Injector_CFLAGS = -fobjc-arc
LiveExec32Injector_LDFLAGS = -Wl,-dead_strip
LiveExec32Injector_FRAMEWORKS = CoreFoundation Security

include $(THEOS_MAKE_PATH)/tweak.mk

.PHONY: test
test:
	@mkdir -p .theos/obj
	xcrun --sdk macosx clang -std=c11 -Wall -Wextra -Werror \
		FatMachO.c MachOImage.c AdHocSigner.c Tests/FatMachOTests.c \
		-framework CoreFoundation -framework Security \
		-o .theos/obj/FatMachOTests
	.theos/obj/FatMachOTests

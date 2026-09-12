ARCHS := arm64 arm64e
TARGET := iphone:clang:latest:15.0
FINALPACKAGE = 1
STRIP = 0
INSTALL_TARGET_PROCESSES = installd trollstorehelper SpringBoard

# Retain the ARM32 app's reported SDK by default. Set 0 to restore the iOS 11
# SDK floor; the minimum deployment target remains iOS 11 in either mode.
LC32_PRESERVE_GUEST_SDK ?= 1
ifneq ($(LC32_PRESERVE_GUEST_SDK),0)
ifneq ($(LC32_PRESERVE_GUEST_SDK),1)
$(error LC32_PRESERVE_GUEST_SDK must be 0 or 1)
endif
endif
LC32_INJECTOR_SDK_FLAGS := -DLC32_PRESERVE_GUEST_SDK=$(LC32_PRESERVE_GUEST_SDK)

include ../module-cache.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiveExec32Injector

LiveExec32Injector_FILES = SpringBoard.x Tweak.x FatMachO.c MachOImage.c AdHocSigner.c LegacyBundleLayout.c
LiveExec32Injector_CFLAGS = -fobjc-arc $(LC32_INJECTOR_SDK_FLAGS)
LiveExec32Injector_LDFLAGS = -Wl,-dead_strip
LiveExec32Injector_FRAMEWORKS = CoreFoundation Security

include $(THEOS_MAKE_PATH)/tweak.mk

.PHONY: test
test:
	@mkdir -p .theos/obj
	xcrun --sdk macosx clang -std=c11 -Wall -Wextra -Werror \
		$(LC32_INJECTOR_SDK_FLAGS) \
		FatMachO.c MachOImage.c AdHocSigner.c Tests/FatMachOTests.c \
		-framework CoreFoundation -framework Security \
		-o .theos/obj/FatMachOTests
	.theos/obj/FatMachOTests

.PHONY: test-legacy-layout
test-legacy-layout:
	@mkdir -p .theos/obj
	xcrun --sdk macosx clang -std=c11 -Wall -Wextra -Werror \
		LegacyBundleLayout.c MachOImage.c Tests/LegacyBundleLayoutTests.c \
		-o .theos/obj/LegacyBundleLayoutTests
	perl -e 'alarm 30; exec @ARGV; die "exec failed: $$!\n"' \
		.theos/obj/LegacyBundleLayoutTests

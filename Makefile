ARCHS := arm64
TARGET := iphone:clang:latest:16.0
FINALPACKAGE = 1
GO_EASY_ON_ME := 1
PACKAGE_FORMAT := ipa
STRIP = 0
# Signing happens after framework embedding and, for Mac tests, after vtool.
TARGET_CODESIGN =

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = LiveExec32

LiveExec32_FILES = main.c
# LoadEmbeddedFramework appends <name>.framework/<name> to these framework
# roots. The libroot-resolved fallback covers jailbreak prefixes other than
# the common /var/jb layout.
LiveExec32_LDFLAGS = \
	-Wl,-rpath,@executable_path/Frameworks \
	-Wl,-rpath,@loader_path/Frameworks \
	-Wl,-rpath,/var/jb/Applications/LiveExec32.app/Frameworks
LiveExec32_FRAMEWORKS = UIKit
LiveExec32_RESOURCE_DIRS = Resources

SHARED_FRAMEWORK_BUILD := \
	$(CURDIR)/HostFrameworks/LC32/.theos/obj/LiveExec32Shared.framework
HELP_FRAMEWORK_BUILD := \
	$(CURDIR)/HostFrameworks/LC32HelpUI/.theos/obj/LC32HelpUI.framework

# Keep the embedded-only frameworks in independent Theos projects. If they
# were FRAMEWORK_NAME instances here, `make package` would copy them into the
# developer's global $(THEOS_LIBRARY_PATH), even with INSTALL=0.
before-LiveExec32-all::
	$(MAKE) -C HostFrameworks/LC32 all \
		THEOS_PROJECT_DIR="$(CURDIR)/HostFrameworks/LC32" \
		THEOS_CURRENT_INSTANCE= _THEOS_CURRENT_TYPE= \
		_THEOS_CURRENT_OPERATION= THEOS_CURRENT_ARCH=
	$(MAKE) -C HostFrameworks/LC32HelpUI all \
		THEOS_PROJECT_DIR="$(CURDIR)/HostFrameworks/LC32HelpUI" \
		THEOS_CURRENT_INSTANCE= _THEOS_CURRENT_TYPE= \
		_THEOS_CURRENT_OPERATION= THEOS_CURRENT_ARCH=

# The executable discovers these bundles dynamically, so HelpUI launches do
# not initialize Dynarmic or install the runtime's process-wide hooks. vtool
# only touches aggregate copies; restoring the launcher from its architecture
# product also makes Catalyst -> iOS mode switches incremental.
after-LiveExec32-all::
	@set -e; \
	frameworks="$(THEOS_OBJ_DIR)/LiveExec32.app/Frameworks"; \
	mkdir -p "$$frameworks/LiveExec32Shared.framework" \
		"$$frameworks/LC32HelpUI.framework"; \
	rsync -a --delete "$(SHARED_FRAMEWORK_BUILD)/" \
		"$$frameworks/LiveExec32Shared.framework/"; \
	rsync -a --delete "$(HELP_FRAMEWORK_BUILD)/" \
		"$$frameworks/LC32HelpUI.framework/"; \
	cp -a "$(THEOS_OBJ_DIR)/$(firstword $(ARCHS))/LiveExec32.app/LiveExec32" \
		"$(THEOS_OBJ_DIR)/LiveExec32.app/LiveExec32"; \
	rm -f "$$frameworks/libdynarmic.dylib"
ifeq ($(LC32_BUILD_CATALYST),1)
	@set -e; \
	frameworks="$(THEOS_OBJ_DIR)/LiveExec32.app/Frameworks"; \
	for binary in \
		"$(THEOS_OBJ_DIR)/LiveExec32.app/LiveExec32" \
		"$$frameworks/LiveExec32Shared.framework/LiveExec32Shared" \
		"$$frameworks/LC32HelpUI.framework/LC32HelpUI"; do \
		output="$$binary.lc32-vtool"; \
		rm -f "$$output"; \
		vtool -arch arm64 -set-build-version 6 11.0 11.0 \
			-replace -output "$$output" "$$binary"; \
		mv "$$output" "$$binary"; \
	done
endif
	@set -e; \
	frameworks="$(THEOS_OBJ_DIR)/LiveExec32.app/Frameworks"; \
	ldid -S "$$frameworks/LiveExec32Shared.framework"; \
	ldid -S "$$frameworks/LC32HelpUI.framework"; \
	if [ "$(LC32_BUILD_CATALYST)" = 1 ]; then \
		ldid -S "$(THEOS_OBJ_DIR)/LiveExec32.app"; \
	else \
		ldid -Sentitlements.plist \
			"$(THEOS_OBJ_DIR)/LiveExec32.app"; \
	fi

internal-clean::
	$(MAKE) -C HostFrameworks/LC32 clean \
		THEOS_PROJECT_DIR="$(CURDIR)/HostFrameworks/LC32" \
		THEOS_CURRENT_INSTANCE= _THEOS_CURRENT_TYPE= \
		_THEOS_CURRENT_OPERATION= THEOS_CURRENT_ARCH=
	$(MAKE) -C HostFrameworks/LC32HelpUI clean \
		THEOS_PROJECT_DIR="$(CURDIR)/HostFrameworks/LC32HelpUI" \
		THEOS_CURRENT_INSTANCE= _THEOS_CURRENT_TYPE= \
		_THEOS_CURRENT_OPERATION= THEOS_CURRENT_ARCH=

include $(THEOS_MAKE_PATH)/application.mk

# Theos updates an existing IPA with `zip -u`, which retains entries removed
# from the staging tree. Recreate the archive so dependency transitions cannot
# leave obsolete binaries (such as the former libdynarmic.dylib) packaged.
before-package::
	@rm -f "$(_THEOS_IPA_PACKAGE_FILENAME)"

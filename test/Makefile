LC32_HOST_TEST_GOALS := check-guest-bootstrap check-memory-hash
LC32_HOST_ONLY_BUILD := $(if $(strip $(MAKECMDGOALS)),\
  $(if $(strip $(filter-out $(LC32_HOST_TEST_GOALS),$(MAKECMDGOALS))),,1),)

HOST_CXX ?= xcrun --sdk macosx clang++
HOST_CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -pedantic
HOST_TEST_OUTPUT_DIR ?= $(CURDIR)/.theos/host-tests
GUEST_BOOTSTRAP_HOST_TEST := $(HOST_TEST_OUTPUT_DIR)/guest-bootstrap-host
MEMORY_HASH_HOST_TEST := $(HOST_TEST_OUTPUT_DIR)/memory-hash-host

.PHONY: check-guest-bootstrap check-memory-hash
check-guest-bootstrap: $(GUEST_BOOTSTRAP_HOST_TEST)
	"$(GUEST_BOOTSTRAP_HOST_TEST)"

check-memory-hash: $(MEMORY_HASH_HOST_TEST)
	"$(MEMORY_HASH_HOST_TEST)"

$(GUEST_BOOTSTRAP_HOST_TEST): guest_bootstrap_host.cpp \
  ../HostFrameworks/LC32/guest_bootstrap.cpp \
  ../HostFrameworks/LC32/guest_bootstrap.h
	@mkdir -p "$(HOST_TEST_OUTPUT_DIR)"
	$(HOST_CXX) $(HOST_CXXFLAGS) \
		-I"$(abspath ../HostFrameworks/LC32)" \
		guest_bootstrap_host.cpp \
		../HostFrameworks/LC32/guest_bootstrap.cpp -o "$@"

$(MEMORY_HASH_HOST_TEST): guest_memory_hash_host.cpp \
  ../HostFrameworks/LC32/guest_memory_hash.h \
  ../HostFrameworks/LC32/khash.h
	@mkdir -p "$(HOST_TEST_OUTPUT_DIR)"
	$(HOST_CXX) $(HOST_CXXFLAGS) \
		-I"$(abspath ../HostFrameworks/LC32)" \
		guest_memory_hash_host.cpp -o "$@"

# Keep this host-native regression test usable on a clean checkout without
# requiring Theos or bootstrapping the iOS 10.3 guest SDK. Mixed/default goals
# continue through the normal guest-test declarations below.
ifeq ($(strip $(LC32_HOST_ONLY_BUILD)),)

ARCHS := armv7s
TARGET := iphone:clang:16.5:10.3
.DEFAULT_GOAL := all
GO_EASY_ON_ME := 1

include ../GuestMakefile/guest-sdk.mk

# Examples:
#   make -C test                 # build every guest test
#   make -C test vm-copy         # build one test (the lc32- prefix is optional)
#   make -C test check-symbols   # build and audit framework symbol coverage
# Final executables are copied to /private/tmp by default for LiveExec32.

GUEST_FRAMEWORK_DIR ?= $(abspath ../GuestMakefile/.theos/obj/armv7s)
TEST_OUTPUT_DIR ?= /private/tmp
ROOTFS ?= $(abspath ../Resources/RootFS)

include ../module-cache.mk

ADDITIONAL_CFLAGS := -Wno-deprecated-module-dot-map
ADDITIONAL_LDFLAGS := -fno-autolink

include $(THEOS)/makefiles/common.mk

# Keep the declarations compact while still giving Theos one independent
# target (and therefore one dependency graph) per guest executable.
define lc32_test
TOOL_NAME += $(1)
$(1)_FILES := $(2)
$(1)_FRAMEWORKS := $(3)
$(1)_LDFLAGS := -isysroot $(ISYSROOT)
$(1)_INSTALL := 0
$(1)_USE_MODULES := 0
endef

define lc32_guest_test
$(call lc32_test,$(1),$(2),$(3))
$(1)_LDFLAGS += -F$(GUEST_FRAMEWORK_DIR)
GUEST_TESTS += $(1)
endef

# Darwin syscall and Mach ABI tests do not depend on any guest framework.
# `main.m` is a legacy UIApplication demo rather than an assertion-based test;
# its old build_main_only.sh linked an ambient SDK into test/a.out, so it is
# intentionally retired instead of becoming part of this reproducible suite.
$(eval $(call lc32_test,lc32-aes-ioctl-abi,aes_ioctl_abi.c,))
$(eval $(call lc32_test,lc32-bind-abi,bind_abi.c,))
$(eval $(call lc32_test,lc32-connect-nocancel,connect_nocancel.c connect_nocancel.S,))
$(eval $(call lc32_test,lc32-cwd-syscalls,cwd_syscalls.c,))
$(eval $(call lc32_test,lc32-darwin-eperm,darwin_eperm.c,))
$(eval $(call lc32_test,lc32-darwin-safe-syscalls,darwin_safe_syscalls.c,))
$(eval $(call lc32_test,lc32-debugger-stop,debugger_stop_worker.c,))
$(eval $(call lc32_test,lc32-debugger-stop-main,debugger_stop.c,))
$(eval $(call lc32_test,lc32-fcntl-filesigs-return,fcntl_filesigs_return.c,))
$(eval $(call lc32_test,lc32-getsockname-abi,getsockname_abi.c,))
$(eval $(call lc32_test,lc32-getsockopt-abi,getsockopt_abi.c,))
$(eval $(call lc32_test,lc32-host-info,host_info.c,))
$(eval $(call lc32_test,lc32-kqueue-kevent,kqueue_kevent.c,))
$(eval $(call lc32_test,lc32-lseek-abi,lseek_abi.c,))
$(eval $(call lc32_test,lc32-mremap-encrypted,mremap_encrypted.c,))
$(eval $(call lc32_test,lc32-native-pthread-smoke,native_pthread_smoke.c,))
$(eval $(call lc32_test,lc32-recvfrom-abi,recvfrom_abi.c,))
$(eval $(call lc32_test,lc32-setsockopt-abi,setsockopt_abi.c,))
$(eval $(call lc32_test,lc32-socket-accept-abi,socket_accept_abi.c,))
$(eval $(call lc32_test,lc32-sysctl-size-query,sysctl_size_query.c,))
$(eval $(call lc32_test,lc32-vm-allocate-collision,vm_allocate_collision.c,))
$(eval $(call lc32_test,lc32-vm-copy,vm_copy.c,))

# AudioToolbox.
$(eval $(call lc32_guest_test,lc32-audio-file-create-packets,audio_file_create_packets.c,AudioToolbox CoreFoundation LC32))
$(eval $(call lc32_guest_test,lc32-audio-file-smoke,audio_file_smoke.c,AudioToolbox CoreFoundation LC32))
$(eval $(call lc32_guest_test,lc32-audio-queue-input,audio_queue_input.c,AudioToolbox CoreFoundation LC32))
$(eval $(call lc32_guest_test,lc32-audio-queue-output,audio_queue_output.c,AudioToolbox CoreFoundation LC32))
$(eval $(call lc32_guest_test,lc32-audio-session,audio_session.c,AudioToolbox CoreFoundation LC32))
$(eval $(call lc32_guest_test,lc32-audio-unit-output,audio_unit_output.c,AudioToolbox CoreFoundation LC32))

# Foundation, CoreFoundation, and bridge behavior.
$(eval $(call lc32_guest_test,lc32-addressbook-compat,addressbook_compat.m,AddressBook Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-arc-proxy-lifetime,arc_proxy_lifetime.m arc_proxy_lifetime_support.m,Foundation UIKit LC32))
$(eval $(call lc32_guest_test,lc32-block-bridge,block_bridge.m,Foundation LC32))
$(eval $(call lc32_guest_test,lc32-cfdictionary-callbacks,cfdictionary_callbacks.m,Foundation CoreFoundation LC32))
$(eval $(call lc32_guest_test,lc32-cfset-callbacks,cfset_callbacks.m,Foundation CoreFoundation LC32))
$(eval $(call lc32_guest_test,lc32-collection-object-buffers,collection_object_buffers.m,Foundation))
$(eval $(call lc32_guest_test,lc32-collection-variadic,collection_variadic.m,Foundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-attributed-string,corefoundation_attributed_string.m,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-bundle-url,corefoundation_bundle_url.m,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-common-wrappers,corefoundation_common_wrappers.m,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-read-stream,corefoundation_read_stream.m,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-run-loop,corefoundation_run_loop.m,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-run-loop-source,corefoundation_run_loop_source.m,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-run-loop-timer,corefoundation_run_loop_timer.m,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-socket,corefoundation_socket.m,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-stream-host,corefoundation_stream_host.m,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-string-character-set,corefoundation_string_character_set.m,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-string-transform,corefoundation_string_transform.m,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-time-zone,corefoundation_time_zone.m,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-url-propertylist,corefoundation_url_propertylist.m,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-url-common,corefoundation_url_common.m,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-uuid,corefoundation_uuid.c,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-corefoundation-write-stream,corefoundation_write_stream.m,Foundation CoreFoundation))
$(eval $(call lc32_guest_test,lc32-cxx-lifecycle,cxx_lifecycle.mm,Foundation UIKit LC32))
$(eval $(call lc32_guest_test,lc32-data-bytes,data_bytes.m,Foundation))
$(eval $(call lc32_guest_test,lc32-fast-enumeration,fast_enumeration.m,Foundation))
$(eval $(call lc32_test,lc32-foundation-null-utf8,foundation_null_utf8.m,Foundation))
$(eval $(call lc32_guest_test,lc32-guest-proxy-lifetime,guest_proxy_lifetime.m,Foundation LC32))
$(eval $(call lc32_guest_test,lc32-kvo-bridge,kvo_bridge.m,Foundation))
$(eval $(call lc32_guest_test,lc32-nsrange-bridge,nsrange_bridge.m,Foundation LC32))
$(eval $(call lc32_guest_test,lc32-nsvalue-bytes,nsvalue_bytes.m,Foundation))
$(eval $(call lc32_guest_test,lc32-nullable-guest-cstring,nullable_guest_cstring.c,LC32))
$(eval $(call lc32_guest_test,lc32-owned-create-copy,owned_create_copy.m,CoreFoundation))
$(eval $(call lc32_guest_test,lc32-ownership-publication-race,ownership_publication_race.m ownership_publication_race_weak.m,Foundation LC32))
$(eval $(call lc32_guest_test,lc32-pointer-out-params,pointer_out_params.m,Foundation LC32))
$(eval $(call lc32_guest_test,lc32-string-bytes,string_bytes.m,Foundation))
$(eval $(call lc32_guest_test,lc32-string-format,string_format.m,Foundation))
$(eval $(call lc32_guest_test,lc32-string-get-bytes,string_get_bytes.m,Foundation LC32))
$(eval $(call lc32_guest_test,lc32-string-range,string_range.m,Foundation))
$(eval $(call lc32_guest_test,lc32-thread-modes,thread_modes.m,Foundation))
$(eval $(call lc32_guest_test,lc32-thread-perform,thread_perform.m,Foundation))

# Graphics and text.
$(eval $(call lc32_guest_test,lc32-coregraphics-bitmap,coregraphics_bitmap.c,CoreGraphics CoreFoundation LC32))
$(eval $(call lc32_guest_test,lc32-coregraphics-fill-color,coregraphics_fill_color.c,CoreGraphics LC32))
$(eval $(call lc32_guest_test,lc32-coregraphics-geometry,coregraphics_geometry.c,CoreGraphics))
$(eval $(call lc32_guest_test,lc32-coregraphics-gradient,coregraphics_gradient.c,CoreGraphics CoreFoundation LC32))
$(eval $(call lc32_guest_test,lc32-quartzcore-transform,quartzcore_transform.c,QuartzCore CoreGraphics))
$(eval $(call lc32_guest_test,lc32-coretext-bridge,coretext_bridge.m,CoreText CoreGraphics CoreFoundation Foundation))
$(eval $(call lc32_guest_test,lc32-coretext-font-descriptor,coretext_font_descriptor.c,CoreText CoreFoundation Foundation))
$(eval $(call lc32_guest_test,lc32-openal-smoke,openal_smoke.c,OpenAL))
$(eval $(call lc32_guest_test,lc32-opengles-smoke,opengles_smoke.m opengles_es1_smoke.m opengles_es3_smoke.m,Foundation OpenGLES QuartzCore))

# UIKit and aggregate-argument bridges.
$(eval $(call lc32_guest_test,lc32-guest-fp-return,guest_fp_return.m,Foundation UIKit LC32))
$(eval $(call lc32_guest_test,lc32-guest-host-aggregate-arguments,guest_host_aggregate_arguments.m,Foundation UIKit CoreGraphics LC32))
$(eval $(call lc32_guest_test,lc32-scalar-pointer-bridge,scalar_pointer_bridge.m,Foundation UIKit CoreGraphics LC32))
$(eval $(call lc32_guest_test,lc32-text-input-traits,text_input_traits.m,Foundation UIKit LC32))
$(eval $(call lc32_guest_test,lc32-uikit-appearance,uikit_appearance.m,Foundation UIKit LC32))
$(eval $(call lc32_guest_test,lc32-uikit-accessibility,uikit_accessibility.m,Foundation UIKit LC32))
$(eval $(call lc32_guest_test,lc32-uikit-image-context,uikit_image_context.m,Foundation UIKit CoreGraphics LC32))
$(eval $(call lc32_guest_test,lc32-uikit-legacy-device,uikit_legacy_device.m,Foundation UIKit LC32))
$(eval $(call lc32_guest_test,lc32-uikit-legacy-string-sizing,uikit_legacy_string_sizing.m,Foundation UIKit CoreGraphics LC32))
$(eval $(call lc32_guest_test,lc32-uikit-legacy-window-root,uikit_legacy_window_root.m,Foundation UIKit CoreGraphics LC32))
$(eval $(call lc32_guest_test,lc32-uikit-view-load-reentrancy,uikit_view_load_reentrancy.m,Foundation UIKit CoreGraphics LC32))

# Security.
$(eval $(call lc32_guest_test,lc32-security-secitem,security_secitem.m,Foundation Security LC32))

# Per-target and per-source language modes from the old build wrappers.
lc32-addressbook-compat_CFLAGS := -Wno-deprecated-declarations
lc32-arc-proxy-lifetime_CFLAGS := -fobjc-arc -fblocks \
	-I$(abspath ../include)
arc_proxy_lifetime_support.m_CFLAGS := -fno-objc-arc

lc32-ownership-publication-race_CFLAGS := -fobjc-arc
ownership_publication_race.m_CFLAGS := -fno-objc-arc

lc32-block-bridge_CFLAGS := -fblocks
lc32-thread-modes_CFLAGS := -fblocks
lc32-thread-perform_CFLAGS := -fblocks

lc32-corefoundation-attributed-string_CFLAGS := -fno-objc-arc
lc32-corefoundation-bundle-url_CFLAGS := -fno-objc-arc
lc32-corefoundation-common-wrappers_CFLAGS := -fno-objc-arc
lc32-corefoundation-read-stream_CFLAGS := -fno-objc-arc
lc32-corefoundation-run-loop_CFLAGS := -fno-objc-arc
lc32-corefoundation-run-loop-source_CFLAGS := -fno-objc-arc
lc32-corefoundation-run-loop-timer_CFLAGS := -fno-objc-arc
lc32-corefoundation-socket_CFLAGS := -fno-objc-arc
lc32-corefoundation-stream-host_CFLAGS := -fno-objc-arc
lc32-corefoundation-string-character-set_CFLAGS := -fno-objc-arc
lc32-corefoundation-string-transform_CFLAGS := -fno-objc-arc
lc32-corefoundation-time-zone_CFLAGS := -fno-objc-arc
lc32-corefoundation-url-propertylist_CFLAGS := -fno-objc-arc
lc32-corefoundation-url-common_CFLAGS := -fno-objc-arc
lc32-corefoundation-write-stream_CFLAGS := -fno-objc-arc
lc32-coretext-bridge_CFLAGS := -fno-objc-arc
lc32-foundation-null-utf8_CFLAGS := -fno-objc-arc
lc32-uikit-legacy-window-root_CFLAGS := -fno-objc-arc -Wall -Wextra -Werror

lc32-cxx-lifecycle_CCFLAGS := -std=c++14

lc32-guest-proxy-lifetime_CFLAGS := -I$(abspath ../include)
lc32-nsrange-bridge_USE_MODULES := 1
lc32-nsrange-bridge_CFLAGS := -I$(abspath ../GuestFrameworks) -I$(abspath ../include)
lc32-scalar-pointer-bridge_USE_MODULES := 1
lc32-scalar-pointer-bridge_CFLAGS := -I$(abspath ../GuestFrameworks) -I$(abspath ../include)

lc32-audio-file-create-packets_CFLAGS := -Wno-deprecated-declarations
lc32-audio-queue-input_CFLAGS := -Wno-deprecated-declarations
lc32-audio-queue-output_CFLAGS := -Wno-deprecated-declarations -Wno-nonnull
lc32-audio-session_CFLAGS := -Wno-deprecated-declarations
lc32-audio-unit-output_CFLAGS := -Wno-deprecated-declarations
lc32-darwin-eperm_CFLAGS := -Wno-deprecated-declarations
lc32-darwin-safe-syscalls_CFLAGS := -Wno-deprecated-declarations
lc32-mremap-encrypted_CFLAGS := -Wno-deprecated-declarations
lc32-security-secitem_CFLAGS := -Wno-deprecated-declarations -Wno-nonnull
lc32-socket-accept-abi_CFLAGS := -Wno-deprecated-declarations
lc32-uikit-appearance_CFLAGS := -Wno-deprecated-declarations

ABI_TESTS := \
  lc32-aes-ioctl-abi lc32-bind-abi lc32-connect-nocancel lc32-cwd-syscalls \
  lc32-darwin-eperm lc32-darwin-safe-syscalls lc32-debugger-stop \
  lc32-debugger-stop-main lc32-fcntl-filesigs-return lc32-getsockname-abi \
  lc32-getsockopt-abi lc32-host-info lc32-kqueue-kevent lc32-lseek-abi \
  lc32-mremap-encrypted lc32-native-pthread-smoke lc32-recvfrom-abi \
  lc32-setsockopt-abi \
  lc32-socket-accept-abi lc32-sysctl-size-query \
  lc32-vm-allocate-collision lc32-vm-copy
AUDIO_TESTS := $(filter lc32-audio-%,$(TOOL_NAME))
COREFOUNDATION_TESTS := $(filter lc32-corefoundation-%,$(TOOL_NAME))
GRAPHICS_TESTS := $(filter lc32-coregraphics-% lc32-quartzcore-% lc32-coretext-% lc32-openal-% lc32-opengles-%,$(TOOL_NAME))
THREADING_TESTS := lc32-native-pthread-smoke lc32-ownership-publication-race lc32-thread-modes lc32-thread-perform
UIKIT_TESTS := $(filter lc32-uikit-%,$(TOOL_NAME)) lc32-guest-fp-return lc32-guest-host-aggregate-arguments lc32-scalar-pointer-bridge lc32-text-input-traits

include $(THEOS_MAKE_PATH)/tool.mk

# Cover both the normal internal-all fanout and direct per-test targets.
ifneq ($(strip $(LC32_GUEST_SDK_DEPENDENCY)),)
before-all:: $(LC32_GUEST_SDK_DEPENDENCY)
$(TOOL_NAME) $(TOOL_NAME:=.all.tool.variables): | $(LC32_GUEST_SDK_DEPENDENCY)
endif

# Preserve the paths used by the existing LiveExec32 runtime commands while
# retaining Theos' incremental objects under test/.theos.
ifneq ($(strip $(THEOS_CURRENT_INSTANCE)),)
after-$(THEOS_CURRENT_INSTANCE)-all::
	@mkdir -p "$(TEST_OUTPUT_DIR)"
	@install -m 755 "$(THEOS_OBJ_DIR)/$(THEOS_CURRENT_INSTANCE)" \
		"$(TEST_OUTPUT_DIR)/$(THEOS_CURRENT_INSTANCE)"
	@file "$(TEST_OUTPUT_DIR)/$(THEOS_CURRENT_INSTANCE)"
	@otool -L "$(TEST_OUTPUT_DIR)/$(THEOS_CURRENT_INSTANCE)"

ifeq ($(THEOS_CURRENT_INSTANCE),lc32-openal-smoke)
after-$(THEOS_CURRENT_INSTANCE)-all::
	./audit_openal_symbols.sh \
		"$(GUEST_FRAMEWORK_DIR)/OpenAL.framework/OpenAL" "$(ISYSROOT)"
endif
ifeq ($(THEOS_CURRENT_INSTANCE),lc32-opengles-smoke)
after-$(THEOS_CURRENT_INSTANCE)-all::
	SDKROOT="$(ISYSROOT)" ./opengles_symbols.sh \
		"$(GUEST_FRAMEWORK_DIR)/OpenGLES.framework/OpenGLES"
endif
ifeq ($(THEOS_CURRENT_INSTANCE),lc32-security-secitem)
after-$(THEOS_CURRENT_INSTANCE)-all::
	./security_symbols.sh \
		"$(GUEST_FRAMEWORK_DIR)/Security.framework/Security"
endif
else

SHORT_TESTS := $(patsubst lc32-%,%,$(TOOL_NAME))
.PHONY: build list frameworks clean-outputs \
  abi audio corefoundation graphics threading uikit \
  check-symbols check-openal check-opengles check-security check-coretext \
  check-graphics-symbols \
  check-messenger $(SHORT_TESTS)

# Theos' per-instance convenience targets bypass the top-level `all` target,
# which normally creates the Clang module validation stamp first.
$(TOOL_NAME): $(_THEOS_BUILD_SESSION_FILE)

build: all
abi: $(ABI_TESTS)
audio: $(AUDIO_TESTS)
corefoundation: $(COREFOUNDATION_TESTS)
graphics: $(GRAPHICS_TESTS)
threading: $(THREADING_TESTS)
uikit: $(UIKIT_TESTS)

$(foreach tool,$(TOOL_NAME),$(eval $(patsubst lc32-%,%,$(tool)): $(tool)))

list:
	@$(foreach tool,$(TOOL_NAME),printf '%s\n' '$(tool)';)

frameworks:
	$(MAKE) -C ../GuestMakefile

check-openal: lc32-openal-smoke
check-opengles: lc32-opengles-smoke
check-security: lc32-security-secitem
check-coretext: lc32-coretext-font-descriptor
	./coretext_font_descriptor_symbols.sh \
		"$(GUEST_FRAMEWORK_DIR)/CoreText.framework/CoreText"
check-graphics-symbols: lc32-coregraphics-bitmap lc32-quartzcore-transform \
  lc32-uikit-accessibility
	GUEST_FRAMEWORK_DIR="$(GUEST_FRAMEWORK_DIR)" \
		./graphics_compat_symbols.sh
check-symbols: check-openal check-opengles check-security check-coretext \
  check-graphics-symbols

check-messenger:
	@test -n "$(MESSENGER)" || { \
		echo 'usage: make check-messenger MESSENGER=/path/to/Messenger [ROOTFS=/path/to/RootFS]' >&2; \
		exit 2; \
	}
	./messenger_eager_symbols.sh "$(MESSENGER)" "$(ROOTFS)"

# Remove only the explicitly enumerated compatibility copies. Theos' normal
# clean target remains responsible for test/.theos.
clean-outputs:
	rm -f $(foreach tool,$(TOOL_NAME),"$(TEST_OUTPUT_DIR)/$(tool)")
endif

endif

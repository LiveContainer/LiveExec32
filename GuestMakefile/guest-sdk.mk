# Shared iOS 10.3 SDK configuration for guest frameworks and guest tests.
# Resolve paths from this fragment rather than the caller's working directory,
# so the SDK cache stays inside the repository's ignored tmp directory.
LC32_GUEST_SDK_FRAGMENT := $(lastword $(MAKEFILE_LIST))
LC32_GUEST_SDK_REPO_ROOT := $(abspath $(dir $(LC32_GUEST_SDK_FRAGMENT))/..)

LC32_GUEST_SDK ?= $(LC32_GUEST_SDK_REPO_ROOT)/tmp/iPhoneOS10.3.sdk
LC32_GUEST_SDK_ARCHIVE ?= $(LC32_GUEST_SDK_REPO_ROOT)/tmp/iPhoneOS10.3.sdk.tar.gz
LC32_GUEST_SDK_URL ?= https://github.com/okanon/iPhoneOS.sdk/releases/download/v0.0.1/iPhoneOS10.3.sdk.tar.gz
LC32_GUEST_SDK_SHA256 ?= fcbbd539d18597b0a07883d97385d5ccac08ab5c02f4493421113a1f8e1ceb80
LC32_GUEST_SDK_SETUP := $(LC32_GUEST_SDK_REPO_ROOT)/GuestMakefile/setup-sdk.sh
LC32_GUEST_SDK_STAMP := $(LC32_GUEST_SDK)/.lc32-sdk-ready

ISYSROOT ?= $(LC32_GUEST_SDK)

# The modern Xcode linker can drop ARM32 Thumb bits from function pointers.
# Resolve the classic linker explicitly; -Wl,-ld_classic is ignored by Xcode 27.
ifeq ($(origin LC32_GUEST_LINKER),undefined)
LC32_GUEST_LINKER := $(shell xcrun --find ld-classic 2>/dev/null)
endif
export LC32_GUEST_LINKER
# Validate in the build-config prerequisite, not while parsing SDK/clean goals.
LC32_GUEST_LINKER_FLAGS = -fuse-ld="$(LC32_GUEST_LINKER)"

# A caller-provided ISYSROOT is intentionally left alone. This lets developers
# use an SDK obtained through Xcode without invoking the third-party download.
ifeq ($(abspath $(ISYSROOT)),$(abspath $(LC32_GUEST_SDK)))
LC32_GUEST_SDK_DEPENDENCY := $(LC32_GUEST_SDK_STAMP)
endif

.PHONY: sdk
sdk: $(LC32_GUEST_SDK_STAMP)

$(LC32_GUEST_SDK_STAMP): $(LC32_GUEST_SDK_SETUP) $(LC32_GUEST_SDK_FRAGMENT)
	@LC32_GUEST_SDK="$(LC32_GUEST_SDK)" \
	LC32_GUEST_SDK_ARCHIVE="$(LC32_GUEST_SDK_ARCHIVE)" \
	LC32_GUEST_SDK_URL="$(LC32_GUEST_SDK_URL)" \
	LC32_GUEST_SDK_SHA256="$(LC32_GUEST_SDK_SHA256)" \
	LC32_GUEST_SDK_STAMP="$(LC32_GUEST_SDK_STAMP)" \
	"$(LC32_GUEST_SDK_SETUP)"

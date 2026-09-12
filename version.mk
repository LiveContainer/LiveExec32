# The package's numeric release version is the source of truth for host
# bundles too. Debian build/prerelease suffixes stay package-only metadata.
LC32_VERSION_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
LC32_VERSION := $(shell awk '/^Version:/ { print $$2; exit }' "$(LC32_VERSION_ROOT)/control")
ifeq ($(strip $(LC32_VERSION)),)
$(error Missing Version in $(LC32_VERSION_ROOT)/control)
endif

# Stamp only built resources, never tracked plists. Convert before signing so
# Theos' final-package plist conversion does not change the signed bytes.
define lc32_stamp_version
plutil -replace CFBundleShortVersionString -string "$(LC32_VERSION)" "$(1)"
plutil -convert binary1 "$(1)"
endef

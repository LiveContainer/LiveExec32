# Include after Theos's framework.mk/tool.mk has defined OBJ_FILES_TO_LINK.
# Theos caches flag-specific objects; an older cached object will not trigger
# relinking when reverting a flag or changing only the linker. Refresh this
# target's objects whenever the guest trace mode or selected linker changes.
ifneq ($(strip $(THEOS_CURRENT_ARCH)),)
LC32_GUEST_BUILD_CONFIG := $(THEOS_OBJ_DIR)/.$(THEOS_CURRENT_INSTANCE)-guest-build-config
.PHONY: lc32-guest-build-config-force
$(LC32_GUEST_BUILD_CONFIG): lc32-guest-build-config-force
	@set -e; \
	if [ ! -f "$(LC32_GUEST_LINKER)" ] || [ ! -x "$(LC32_GUEST_LINKER)" ]; then \
		echo 'ld-classic is unavailable; install compatible Command Line Tools or set LC32_GUEST_LINKER to its absolute path' >&2; \
		exit 1; \
	fi; \
	mkdir -p "$(@D)"; \
	tmp="$@.$$$$"; \
	{ \
		printf '%s\n' "LC32_OBJC_TRACE=$(or $(LC32_OBJC_TRACE),0)"; \
		printf '%s\n' "LC32_GUEST_LINKER=$(LC32_GUEST_LINKER)"; \
	} > "$$tmp"; \
	if [ -f "$@" ] && cmp -s "$$tmp" "$@"; then \
		rm -f "$$tmp"; \
	else \
		mv -f "$$tmp" "$@"; \
	fi
$(OBJ_FILES_TO_LINK): $(LC32_GUEST_BUILD_CONFIG)
endif

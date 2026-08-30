# Keep Clang's reusable PCMs inside the repository. Clang's context hash
# separates incompatible SDKs, targets, language modes, and compiler flags,
# while its cache locking permits concurrent framework builds.
LC32_REPO_ROOT := $(patsubst %/,%,$(dir \
	$(abspath $(lastword $(MAKEFILE_LIST)))))
CLANG_MODULE_CACHE_PATH ?= $(LC32_REPO_ROOT)/.theos/module-cache
export CLANG_MODULE_CACHE_PATH

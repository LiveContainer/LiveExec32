#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
IMAGE=${1:-"$REPO_ROOT/GuestMakefile/.theos/obj/armv7s/Security.framework/Security"}

if [ ! -f "$IMAGE" ]; then
    echo "Security linked image does not exist: $IMAGE" >&2
    exit 1
fi

SYMBOLS=$(mktemp "${TMPDIR:-/private/tmp}/lc32-security-symbols.XXXXXX")
trap 'rm -f "$SYMBOLS"' EXIT HUP INT TERM
xcrun nm -gjU "$IMAGE" > "$SYMBOLS"

while IFS= read -r symbol; do
    if ! grep -qx "_$symbol" "$SYMBOLS"; then
        echo "Security bridge is missing export: $symbol" >&2
        exit 1
    fi
done < "$SCRIPT_DIR/security_symbols.txt"

echo "Security symbol audit: PASS"

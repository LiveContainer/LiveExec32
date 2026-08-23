#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
MESSENGER=${1:-}
ROOTFS=${2:-"$REPO_ROOT/Resources/RootFS"}

if [ -z "$MESSENGER" ]; then
    echo "usage: $0 /path/to/com.facebook.Messenger.app/Messenger [RootFS]" >&2
    exit 2
fi
if [ ! -f "$MESSENGER" ]; then
    echo "Messenger executable does not exist: $MESSENGER" >&2
    exit 1
fi
if [ ! -d "$ROOTFS" ]; then
    echo "Guest RootFS does not exist: $ROOTFS" >&2
    exit 1
fi

work=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-messenger-symbols.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

# Messenger uses old-style dyld fixups.  Bind entries outside its lazy-symbol
# pointer section must all be resolvable before main() can run.
xcrun dyld_info -arch armv7 -fixups "$MESSENGER" |
    awk '$4 == "bind" && $2 !~ /lazy/ { print $5 }' |
    sed 's/ +.*//' |
    LC_ALL=C sort -u > "$work/eager-targets"

# Weak imports may legally remain unresolved.  Strip them from the required
# symbol set before comparing it with the guest images.
xcrun dyld_info -arch armv7 -imports "$MESSENGER" |
    sed -n 's/^[[:space:]]*\([^[:space:]]*\) \[weak-import\].*/\1/p' |
    LC_ALL=C sort -u > "$work/weak-symbols"
sed 's#^[^/]*/##' "$work/eager-targets" |
    LC_ALL=C sort -u |
    comm -23 - "$work/weak-symbols" > "$work/required-symbols"

# Resolve against the full RootFS export namespace.  Several compatibility
# images intentionally supply symbols that moved between Apple frameworks, so
# comparing only with the import ordinal's nominal framework gives false
# failures for otherwise valid reexports.
find "$ROOTFS" -type f -print |
    while IFS= read -r image; do
        xcrun nm -gjU "$image" 2>/dev/null || :
    done |
    LC_ALL=C sort -u > "$work/rootfs-exports"

comm -23 "$work/required-symbols" "$work/rootfs-exports" \
    > "$work/missing-symbols"
if [ -s "$work/missing-symbols" ]; then
    echo "Messenger has unresolved eager guest symbols:" >&2
    awk -F/ '
        NR == FNR { missing[$0] = 1; next }
        {
            symbol = $0
            sub(/^[^/]*\//, "", symbol)
            if (missing[symbol]) print $0
        }
    ' "$work/missing-symbols" "$work/eager-targets" |
        LC_ALL=C sort -u |
        sed 's/^/  /' >&2
    exit 1
fi

count=$(wc -l < "$work/required-symbols" | tr -d ' ')
echo "Messenger eager-symbol audit: PASS ($count required imports resolved)"

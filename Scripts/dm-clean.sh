#!/bin/bash

set -euo pipefail

if (( $# < 3 )); then
    echo "dm-clean.sh: expected dm.pl options, staging path, and output path" >&2
    exit 2
fi
if [[ -z "${THEOS:-}" || ! -x "$THEOS/bin/dm.pl" ]]; then
    echo "dm-clean.sh: THEOS does not identify a usable dm.pl" >&2
    exit 2
fi

arguments=("$@")
staging_index=$(( ${#arguments[@]} - 2 ))
if [[ "${arguments[$((staging_index - 1))]}" != "-b" ]]; then
    echo "dm-clean.sh: expected the final dm.pl option to be -b" >&2
    exit 2
fi
staging_path=${arguments[$staging_index]}
if [[ ! -d "$staging_path" ]]; then
    echo "dm-clean.sh: staging directory does not exist: $staging_path" >&2
    exit 2
fi

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/liveexec32-deb.XXXXXX")
cleanup() {
    chmod -RN "$temporary_root" 2>/dev/null || true
    rm -rf -- "$temporary_root"
}
trap cleanup EXIT HUP INT TERM

clean_staging="$temporary_root/staging"
mkdir -m 0755 "$clean_staging"
rsync -a --exclude='.DS_Store' "$staging_path/" "$clean_staging/"

if [[ -n "$(find "$clean_staging" -type f -name .DS_Store -print -quit)" ]]; then
    echo "dm-clean.sh: clean staging copy still contains .DS_Store" >&2
    exit 1
fi

arguments[$staging_index]=$clean_staging
"$THEOS/bin/dm.pl" "${arguments[@]}"

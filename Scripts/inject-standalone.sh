#!/bin/bash
# Bundle LiveExec32 into a decrypted ARM32 iOS app or IPA. Run on macOS.
set -euo pipefail
export LC_ALL=C

usage() {
    echo "Usage: $0 [--output OUTPUT.app|OUTPUT.ipa] GAME.app|GAME.ipa LiveExec32.app|LiveExec32.ipa"
    echo "Output uses the input game format; signing, JIT enablement and installation are separate."
    echo "Without --output, replaces the input and keeps INPUT.lc32-backup (must not exist)."
}
fail() { echo "inject-standalone: $*" >&2; exit 1; }

output=
in_place=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            [[ $# -ge 2 && -n "$2" && -z "$output" ]] || { usage >&2; exit 2; }
            output=$2; shift 2 ;;
        --in-place) in_place=1; shift ;;
        --help|-h) usage; exit 0 ;;
        --) shift; break ;;
        -*) usage >&2; exit 2 ;;
        *) break ;;
    esac
done
[[ $# -eq 2 ]] || { usage >&2; exit 2; }
if [[ $in_place -eq 1 ]]; then
    [[ -z "$output" ]] || fail "choose either --output or --in-place"
else
    [[ -n "$output" ]] || in_place=1
fi
[[ $(uname -s) == Darwin ]] || fail "macOS with Xcode Command Line Tools is required"
for tool in xcrun rsync; do
    command -v "$tool" >/dev/null || fail "missing required tool: $tool"
done
repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
[[ ! -L "${1%/}" ]] || fail "the input must not be a symlink"
input=$(cd -- "$(dirname -- "${1%/}")" && printf '%s/%s\n' "$(pwd -P)" "$(basename -- "${1%/}")")
runtime_input=$(cd -- "$(dirname -- "${2%/}")" && printf '%s/%s\n' "$(pwd -P)" "$(basename -- "${2%/}")")
case "$input" in
    *.app) [[ -d "$input" ]] || fail "game .app directory is missing"; format=app ;;
    *.ipa) [[ -f "$input" ]] || fail "game .ipa file is missing"; format=ipa ;;
    *) fail "input must be an .app directory or .ipa file" ;;
esac
case "$runtime_input" in
    *.app) [[ -d "$runtime_input" ]] || fail "runtime .app directory is missing" ;;
    *.ipa) [[ -f "$runtime_input" ]] || fail "runtime .ipa file is missing" ;;
    *) fail "runtime must be an .app directory or .ipa file" ;;
esac
if [[ $format == ipa || "$runtime_input" == *.ipa ]]; then
    for tool in unzip zip; do
        command -v "$tool" >/dev/null || fail "missing required tool: $tool"
    done
    # Do not inherit options that follow links, change filenames or allow traversal.
    unset ZIPOPT UNZIP UNZIPOPT ZIPINFO ZIPINFOOPT
fi

backup=
if [[ $in_place -eq 1 ]]; then
    output=$input
    backup="$input.lc32-backup"
    [[ ! -e "$backup" && ! -L "$backup" ]] || fail "backup already exists: $backup"
else
    [[ "$output" == *."$format" ]] || fail "output must end in .$format to match the input"
    parent=$(cd -- "$(dirname -- "$output")" && pwd -P) || fail "output parent must exist"
    output="$parent/$(basename -- "$output")"
    [[ ! -e "$output" && ! -L "$output" ]] || fail "output already exists: $output"
fi
case "$output" in "$input"/*|"$runtime_input"|"$runtime_input"/*) fail "output must be outside both inputs" ;; esac
parent=$(dirname -- "$output")
work=$(mktemp -d "$parent/.lc32-standalone.XXXXXX")
cleanup() {
    result=$?
    trap - EXIT
    if [[ -n "$backup" && -e "$backup" && ! -e "$input" && ! -L "$input" ]]; then
        mv -- "$backup" "$input" || echo "Original input remains at: $backup" >&2
    fi
    rm -rf -- "$work"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

shopt -s nullglob dotglob
extract_ipa() {
    local entry
    unzip -Z1 "$1" > "$work/archive-entries"
    while IFS= read -r entry; do
        case "/$entry/" in
            //*|*/../*) fail "unsafe IPA entry: $entry" ;;
        esac
    done < "$work/archive-entries"
    # A fresh directory and -n prevent overwrites; unzip defers symlinks until
    # after files, so archived links cannot redirect extraction outside it.
    mkdir "$2"
    unzip -q -n -P '' "$1" -d "$2" < /dev/null
}
ipa_app() {
    [[ -d "$1/Payload" && ! -L "$1/Payload" ]] || fail "IPA is missing a real Payload directory"
    local apps=("$1/Payload/"*.app)
    [[ ${#apps[@]} -eq 1 && -d "${apps[0]}" && ! -L "${apps[0]}" ]] ||
        fail "IPA must contain exactly one app directory directly under Payload"
    printf '%s\n' "${apps[0]}"
}
game=$input
runtime=$runtime_input
if [[ $format == ipa ]]; then
    extract_ipa "$input" "$work/game-archive"
    game=$(ipa_app "$work/game-archive")
fi
if [[ "$runtime_input" == *.ipa ]]; then
    extract_ipa "$runtime_input" "$work/runtime-archive"
    runtime=$(ipa_app "$work/runtime-archive")
fi
[[ -f "$game/Info.plist" && ! -L "$game/Info.plist" ]] || fail "missing or symlinked game Info.plist"
[[ -f "$runtime/Info.plist" && ! -L "$runtime/Info.plist" ]] || fail "missing or symlinked runtime Info.plist"
[[ ! -L "$runtime/RootFS" && ! -L "$runtime/Frameworks" &&
   -f "$runtime/RootFS/usr/lib/dyld" &&
   -f "$runtime/RootFS/System/Library/Frameworks/LC32.framework/LC32" &&
   -f "$runtime/Frameworks/LiveExec32Shared.framework/LiveExec32Shared" ]] ||
    fail "runtime is incomplete; pack the guest RootFS and build LiveExec32 first"
[[ ! -e "$game/RootFS" && ! -L "$game/RootFS" ]] || fail "input already contains RootFS"
[[ ! -L "$game/Frameworks" ]] || fail "game Frameworks must not be a symlink"
[[ ! -e "$game/Frameworks" || -d "$game/Frameworks" ]] || fail "game Frameworks is not a directory"
for entry in "$runtime/Frameworks/"*; do
    name=${entry##*/}
    [[ ! -e "$game/Frameworks/$name" && ! -L "$game/Frameworks/$name" ]] ||
        fail "framework collision: $name"
done

# Reuse the jailbreak injector's validated Mach-O parser, SDK preservation,
# entitlement merge and atomic executable replacement instead of a second lipo implementation.
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -DLC32_PRESERVE_GUEST_SDK=1 -I"$repo/Tweak" \
    "$repo/Scripts/inject-standalone.m" "$repo/Tweak/FatMachO.c" \
    "$repo/Tweak/MachOImage.c" "$repo/Tweak/AdHocSigner.c" \
    -framework Foundation -framework Security -o "$work/inject"
staged=$game
if [[ $format == app ]]; then
    staged="$work/Standalone.app"
    mkdir "$staged"
    rsync -aH "$game/" "$staged/"
fi
"$work/inject" "$staged" "$runtime"
mkdir -p "$staged/Frameworks"
rsync -aH "$runtime/Frameworks/" "$staged/Frameworks/"
rsync -aH "$runtime/RootFS/" "$staged/RootFS/"
# Existing resource seals no longer describe this bundle. Do not alter the
# preserved ARM32 slice or pretend the injector's arm64 ad-hoc signature signs the app.
rm -rf -- "$staged/_CodeSignature"
if [[ $format == ipa ]]; then
    # -y stores symlinks as links instead of following RootFS links on the Mac.
    (cd "$work/game-archive" && zip -qry "$work/Standalone.ipa" .)
    staged="$work/Standalone.ipa"
fi
if [[ $in_place -eq 1 ]]; then
    [[ ! -e "$backup" && ! -L "$backup" ]] || fail "backup appeared while preparing the app"
    mv -n -- "$input" "$backup"
    [[ ! -e "$input" && ! -L "$input" ]] || fail "could not move the original to its backup"
fi
[[ ! -e "$output" && ! -L "$output" ]] || fail "output appeared while preparing the app"
mv -n -- "$staged" "$output"
[[ ! -e "$staged" ]] || fail "output was not published"
echo "Prepared: $output"
[[ -z "$backup" ]] || echo "Original backup: $backup"
echo "Re-sign the complete bundle and provide JIT before launching on a compatible iOS version."

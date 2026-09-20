#!/bin/sh
# No Simulator/device launch: compile real hook units and exercise the native
# versus compatibility behavior of the Foundation-only and fake-host adapters.
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temp_base=$(CDPATH= cd -- "${TMPDIR:-/tmp}" && pwd -P)
workdir=$(mktemp -d "$temp_base/lc32-uikit-switch.XXXXXX")
trap 'case "$workdir" in "$temp_base"/lc32-uikit-switch.*) rm -rf -- "$workdir" ;; esac' EXIT

for mode in 0 1; do
    xcrun --sdk macosx clang -Wall -Wextra -Werror -fobjc-arc -fblocks \
        -DLC32_UIKIT_COMPATIBILITY="$mode" \
        -I"$repo_root/test/background-task-stubs" -framework Foundation \
        "$repo_root/test/uikit_background_tasks_host.m" \
        "$repo_root/GuestFrameworks/UIKit/UIApplication+LC32BlockCompatibility.m" \
        -o "$workdir/background-$mode"
    "$workdir/background-$mode"
    xcrun --sdk macosx clang++ -Wall -Wextra -Werror -fobjc-arc \
        -DLC32_UIKIT_COMPATIBILITY="$mode" -framework Foundation \
        "$repo_root/test/legacy_nib_loading_host.mm" \
        "$repo_root/HostFrameworks/UIKit/LegacyNibLoading.mm" \
        -o "$workdir/nib-$mode"
    "$workdir/nib-$mode"

    for unit in LegacyAutoLayout LegacyFonts LegacyAlerts LegacyRotation; do
        xcrun --sdk iphoneos clang++ -arch arm64 -miphoneos-version-min=15.0 \
            -std=c++17 -fobjc-arc -Wno-deprecated-declarations \
            -DLC32_UIKIT_COMPATIBILITY="$mode" -I"$repo_root/include" \
            -c "$repo_root/HostFrameworks/UIKit/$unit.mm" -o "$workdir/$unit.o"
        case "$unit" in
            LegacyAutoLayout|LegacyFonts|LegacyAlerts) expected=1 ;;
            *) expected=$mode ;;
        esac
        if xcrun nm -U "$workdir/$unit.o" | grep -q 'OBJC_.*LC32'; then
            test "$expected" = 1
        else
            test "$expected" = 0
        fi
        echo "PASS $unit hook metadata mode=$mode present=$expected"
        if [ "$unit" = LegacyAutoLayout ]; then
            xcrun strings "$workdir/$unit.o" | grep -Fq '_forceLayoutEngineSolutionInRationalEdges'
            xcrun strings "$workdir/$unit.o" | grep -Fq '_hostsLayoutEngineAllowsTAMIC_NO'
            xcrun strings "$workdir/$unit.o" | grep -Fq 'UITrackingWindowView'
            xcrun strings "$workdir/$unit.o" | grep -Fq 'UIInputSetContainerView'
            echo "PASS rational-edge and scoped overlay hosting fixes retained mode=$mode"
        fi
    done
done
echo 'UIKit compatibility compile switch: PASS'

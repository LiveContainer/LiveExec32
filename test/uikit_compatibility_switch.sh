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

    for unit in LegacyAutoLayout LegacyFonts LegacyAlerts LegacyRotation GuestSelectorHooks GuestScreenMetrics; do
        xcrun --sdk iphoneos clang++ -arch arm64 -miphoneos-version-min=15.0 \
            -std=c++17 -fobjc-arc -Wno-deprecated-declarations \
            -DLC32_UIKIT_COMPATIBILITY="$mode" -I"$repo_root/include" \
            -DDYNARMIC_MASTER -I"$repo_root/External/dynarmic/src" \
            -I"$repo_root/External/mini-gdbstub/include" \
            -c "$repo_root/HostFrameworks/UIKit/$unit.mm" -o "$workdir/$unit.o"
        case "$unit" in
            LegacyAutoLayout|LegacyFonts|LegacyAlerts) expected=1 ;;
            *) expected=$mode ;;
        esac
        pattern='OBJC_.*LC32'
        if [ "$unit" = GuestSelectorHooks ]; then pattern='OBJC_CLASS_.*LC32GuestViewMutationHooks'; fi
        if xcrun nm -U "$workdir/$unit.o" | grep -q "$pattern"; then
            test "$expected" = 1
        else
            test "$expected" = 0
        fi
        echo "PASS $unit hook metadata mode=$mode present=$expected"
        if [ "$unit" = GuestSelectorHooks ]; then
            xcrun nm -U "$workdir/$unit.o" | grep -Fq 'lc32_guestView]'
            xcrun nm -U "$workdir/$unit.o" | grep -Fq 'lc32_guestLoadNibNamed:owner:options:]'
            xcrun nm -U "$workdir/$unit.o" | grep -Fq 'lc32_guestShow]'
            echo "PASS essential guest view/nib/alert adapters retained mode=$mode"
        fi
        if [ "$unit" = LegacyAutoLayout ]; then
            xcrun strings "$workdir/$unit.o" | grep -Fq '_forceLayoutEngineSolutionInRationalEdges'
            xcrun strings "$workdir/$unit.o" | grep -Fq '_hostsLayoutEngineAllowsTAMIC_NO'
            xcrun strings "$workdir/$unit.o" | grep -Fq 'UITrackingWindowView'
            xcrun strings "$workdir/$unit.o" | grep -Fq 'UIInputSetContainerView'
            xcrun strings "$workdir/$unit.o" | grep -Fq '_UIAlertControllerPhoneTVMacView'
            echo "PASS rational-edge and scoped overlay hosting fixes retained mode=$mode"
        fi
    done
done
echo 'UIKit compatibility compile switch: PASS'

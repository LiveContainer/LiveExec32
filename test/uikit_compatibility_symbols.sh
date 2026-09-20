#!/bin/sh
# Audit actual linked products, not just compiler flags/config stamps.
set -eu
mode=${1:?usage: uikit_compatibility_symbols.sh 0-or-1}
case "$mode" in 0|1) ;; *) exit 2 ;; esac
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
host="$repo_root/HostFrameworks/LC32/.theos/obj/LiveExec32Shared.framework/LiveExec32Shared"
guest="$repo_root/GuestMakefile/.theos/obj/armv7s/UIKit.framework/UIKit"
check_symbol() {
    binary=$1
    symbol=$2
    expected=$3
    if xcrun nm -U "$binary" | grep -Fq -- "$symbol"; then
        test "$expected" = 1
    else
        test "$expected" = 0
    fi
    echo "PASS $symbol present=$expected"
}
for symbol in 'LC32NativeLegacyRotation)' 'LC32LegacyRootViewController)'; do
    check_symbol "$host" "$symbol" "$mode"
done
for symbol in 'lc32_interfaceOrientation]' 'lc32_statusBarOrientation]'; do
    check_symbol "$guest" "$symbol" "$mode"
done
# Essential entry points, retained shims, and native forwarders survive either mode.
check_symbol "$host" 'LC32LegacyAutoLayout' 1
for selector in '_forceLayoutEngineSolutionInRationalEdges' '_hostsLayoutEngineAllowsTAMIC_NO'; do
    xcrun strings "$host" | grep -Fq -- "$selector"
    echo "PASS retained layout selector $selector"
done
check_symbol "$host" '+[LC32LegacyAlerts load]' 1
check_symbol "$host" '+[UIFont(LC32LegacyFonts) load]' 1
check_symbol "$host" '+[UIFontDescriptor(LC32LegacyFonts) load]' 1
check_symbol "$host" '_LC32_UIKit_UIApplicationMain' 1
check_symbol "$host" '_LC32UIKitGetViewDuringGuestLoad' 1
check_symbol "$guest" '_UIApplicationMain' 1
check_symbol "$guest" '_LC32DisableLegacyAdMobNetworking' 1
check_symbol "$guest" '-[UIDevice(LC32LegacyUniqueIdentifier) uniqueIdentifier]' 1
check_symbol "$guest" '_LC32ResolveLegacyUniqueIdentifierFallback' 1
for selector in 'setStatusBarOrientation:' 'setStatusBarOrientation:animated:' \
    'setStatusBarOrientation:animation:duration:' \
    'setStatusBarOrientation:animationParameters:' \
    'setStatusBarOrientation:animationParameters:notifySpringBoardAndFence:' \
    'setStatusBarOrientation:animationParameters:notifySpringBoardAndFence:updateBlock:'; do
    check_symbol "$guest" "-[UIApplication(LC32LegacyOrientation) $selector]" 1
    check_symbol "$guest" "-[UIApplication $selector]" 0
done
check_symbol "$guest" '-[UIScreen(LC32LegacyCanvas) bounds]' 1
check_symbol "$guest" '-[UIWebView(LC32LegacyUserAgent) loadRequest:]' 1
echo "UIKit linked-product compatibility audit mode=$mode: PASS"

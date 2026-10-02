#!/bin/sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/lc32-coremedia-generator.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
"$script_dir/build.sh"
"$script_dir/GenerateShimObjC" "$script_dir/Tests/coremedia-time.plist" "$test_dir"

fixture="$test_dir/AVFoundation/LC32MediaTimeFixture.m"
require() {
    if ! grep -Fq -- "$1" "$fixture"; then
        echo "Missing generated CoreMedia bridge: $1" >&2
        exit 1
    fi
}
require '- (CMTime)frameDuration {'
require '- (void)setFrameDuration:(CMTime)guest_arg0 {'
require 'CMTime host_arg0 = guest_arg0;'
require 'CMTime host_ret = {0}; LC32InvokeHostSelector'
require '- (CMTimeRange)timeRange {'
require 'CMTimeRange host_arg0 = guest_arg0;'
require 'CMTimeRange host_ret = {0}; LC32InvokeHostSelector'
require '- (CMTime)namedTime {'
require '- (CMTimeRange)namedRange {'
require 'return host_ret;'
require 'LC32HostAggregateArgument(&host_arg0), LC32HostAggregateArgument(&host_arg1)'
require 'host_arg0, host_arg1, LC32HostAggregateArgument(&host_arg2)'
require 'host_arg0, LC32HostAggregateArgument(&host_arg1)'
require 'uint64_t host_arg0 = [(__bridge id)guest_arg0 host_self];'
require 'return (__bridge void *)LC32HostToGuestOwnedObject(host_ret);'
require 'id guest_ret = LC32InvokeHostObjectSelector'
require 'return (__bridge void *)guest_ret;'
if grep -Fq 'FIXME: has unhandled types' "$fixture"; then
    echo 'Known CoreMedia types remain disabled' >&2
    exit 1
fi
unknown="$test_dir/AVFoundation/LC32UnknownMediaFixture.m"
if [ "$(grep -Fc 'FIXME: has unhandled types' "$unknown")" -ne 2 ]; then
    echo 'Unrelated anonymous/opaque types must remain unsupported' >&2
    exit 1
fi
thumbnail="$test_dir/AVFoundation/AVAssetImageGenerator.m"
if grep -Fq 'copyCGImageAtTime:' "$thumbnail"; then
    echo 'Thumbnail method must be provided only by its typed manual adapter' >&2
    exit 1
fi
echo 'GenerateShimAPI CoreMedia time fixture: PASS'

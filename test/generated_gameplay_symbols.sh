#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
FRAMEWORK_DIR=${GUEST_FRAMEWORK_DIR:-"$REPO_ROOT/GuestMakefile/.theos/obj/armv7s"}
SDKROOT=${SDKROOT:-"$REPO_ROOT/tmp/iPhoneOS10.3.sdk"}
FRAMEWORKS="GameplayKit MetalPerformanceShaders ModelIO MultipeerConnectivity SpriteKit"

work=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-generated-gameplay-symbols.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

expected_symbols() {
    case $1 in
        MetalPerformanceShaders)
            cat <<'EOF'
MPSRectNoClip
MPSSupportsMTLDevice
EOF
            ;;
        ModelIO)
            cat <<'EOF'
MDLVertexAttributeAnisotropy
MDLVertexAttributeBinormal
MDLVertexAttributeBitangent
MDLVertexAttributeColor
MDLVertexAttributeEdgeCrease
MDLVertexAttributeJointIndices
MDLVertexAttributeJointWeights
MDLVertexAttributeNormal
MDLVertexAttributeOcclusionValue
MDLVertexAttributePosition
MDLVertexAttributeShadingBasisU
MDLVertexAttributeShadingBasisV
MDLVertexAttributeSubdivisionStencil
MDLVertexAttributeTangent
MDLVertexAttributeTextureCoordinate
kUTType3dObject
kUTTypeAlembic
kUTTypePolygon
kUTTypeStereolithography
kUTTypeUniversalSceneDescription
EOF
            ;;
        MultipeerConnectivity)
            cat <<'EOF'
MCErrorDomain
kMCSessionMaximumNumberOfPeers
kMCSessionMinimumNumberOfPeers
EOF
            ;;
        GameplayKit|SpriteKit)
            :
            ;;
    esac
}

total=0
for framework in $FRAMEWORKS; do
    image="$FRAMEWORK_DIR/$framework.framework/$framework"
    tbd="$SDKROOT/System/Library/Frameworks/$framework.framework/$framework.tbd"
    if [ ! -f "$image" ] || [ ! -f "$tbd" ]; then
        echo "$framework image or SDK stub is missing" >&2
        exit 1
    fi

    expected_symbols "$framework" | LC_ALL=C sort -u \
        > "$work/$framework.expected"
    xcrun nm -gjU "$tbd" 2>/dev/null | sed 's/^_//' | LC_ALL=C sort -u \
        > "$work/$framework.sdk"
    xcrun nm -gjU "$image" | sed 's/^_//' | LC_ALL=C sort -u \
        > "$work/$framework.actual"

    comm -23 "$work/$framework.expected" "$work/$framework.sdk" \
        > "$work/$framework.not-in-sdk"
    if [ -s "$work/$framework.not-in-sdk" ]; then
        echo "$framework expected symbols are not in the iOS 10.3 SDK:" >&2
        sed 's/^/  /' "$work/$framework.not-in-sdk" >&2
        exit 1
    fi

    comm -23 "$work/$framework.expected" "$work/$framework.actual" \
        > "$work/$framework.missing"
    if [ -s "$work/$framework.missing" ]; then
        echo "$framework is missing public guest symbols:" >&2
        sed 's/^/  /' "$work/$framework.missing" >&2
        exit 1
    fi

    count=$(wc -l < "$work/$framework.expected" | tr -d ' ')
    total=$((total + count))
    echo "$framework gameplay symbol audit: PASS ($count exports)"
done

echo "Generated gameplay framework symbol audit: PASS ($total exports)"

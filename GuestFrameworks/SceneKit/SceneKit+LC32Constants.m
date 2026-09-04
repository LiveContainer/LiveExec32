#import <SceneKit/SceneKit.h>
#import <Foundation/Foundation+LC32.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

const SCNVector3 SCNVector3Zero = { 0.0f, 0.0f, 0.0f };
const SCNVector4 SCNVector4Zero = { 0.0f, 0.0f, 0.0f, 0.0f };
const SCNMatrix4 SCNMatrix4Identity = {
    1.0f, 0.0f, 0.0f, 0.0f,
    0.0f, 1.0f, 0.0f, 0.0f,
    0.0f, 0.0f, 1.0f, 0.0f,
    0.0f, 0.0f, 0.0f, 1.0f,
};

/* Bind guest proxies to the native framework's canonical object constants. */
#define LC32_SCENEKIT_OBJECT_CONSTANTS(X) \
    X(SCNConsistencyElementIDErrorKey) \
    X(SCNConsistencyElementTypeErrorKey) \
    X(SCNConsistencyLineNumberErrorKey) \
    X(SCNDetailedErrorsKey) \
    X(SCNErrorDomain) \
    X(SCNGeometrySourceSemanticBoneIndices) \
    X(SCNGeometrySourceSemanticBoneWeights) \
    X(SCNGeometrySourceSemanticColor) \
    X(SCNGeometrySourceSemanticEdgeCrease) \
    X(SCNGeometrySourceSemanticNormal) \
    X(SCNGeometrySourceSemanticTangent) \
    X(SCNGeometrySourceSemanticTexcoord) \
    X(SCNGeometrySourceSemanticVertex) \
    X(SCNGeometrySourceSemanticVertexCrease) \
    X(SCNHitTestBackFaceCullingKey) \
    X(SCNHitTestBoundingBoxOnlyKey) \
    X(SCNHitTestClipToZRangeKey) \
    X(SCNHitTestFirstFoundOnlyKey) \
    X(SCNHitTestIgnoreChildNodesKey) \
    X(SCNHitTestIgnoreHiddenNodesKey) \
    X(SCNHitTestOptionCategoryBitMask) \
    X(SCNHitTestRootNodeKey) \
    X(SCNHitTestSortResultsKey) \
    X(SCNLightTypeAmbient) \
    X(SCNLightTypeDirectional) \
    X(SCNLightTypeIES) \
    X(SCNLightTypeOmni) \
    X(SCNLightTypeProbe) \
    X(SCNLightTypeSpot) \
    X(SCNLightingModelBlinn) \
    X(SCNLightingModelConstant) \
    X(SCNLightingModelLambert) \
    X(SCNLightingModelPhong) \
    X(SCNLightingModelPhysicallyBased) \
    X(SCNModelTransform) \
    X(SCNModelViewProjectionTransform) \
    X(SCNModelViewTransform) \
    X(SCNNormalTransform) \
    X(SCNParticlePropertyAngle) \
    X(SCNParticlePropertyAngularVelocity) \
    X(SCNParticlePropertyBounce) \
    X(SCNParticlePropertyCharge) \
    X(SCNParticlePropertyColor) \
    X(SCNParticlePropertyContactNormal) \
    X(SCNParticlePropertyContactPoint) \
    X(SCNParticlePropertyFrame) \
    X(SCNParticlePropertyFrameRate) \
    X(SCNParticlePropertyFriction) \
    X(SCNParticlePropertyLife) \
    X(SCNParticlePropertyOpacity) \
    X(SCNParticlePropertyPosition) \
    X(SCNParticlePropertyRotationAxis) \
    X(SCNParticlePropertySize) \
    X(SCNParticlePropertyVelocity) \
    X(SCNPhysicsShapeKeepAsCompoundKey) \
    X(SCNPhysicsShapeOptionCollisionMargin) \
    X(SCNPhysicsShapeScaleKey) \
    X(SCNPhysicsShapeTypeBoundingBox) \
    X(SCNPhysicsShapeTypeConcavePolyhedron) \
    X(SCNPhysicsShapeTypeConvexHull) \
    X(SCNPhysicsShapeTypeKey) \
    X(SCNPhysicsTestBackfaceCullingKey) \
    X(SCNPhysicsTestCollisionBitMaskKey) \
    X(SCNPhysicsTestSearchModeAll) \
    X(SCNPhysicsTestSearchModeAny) \
    X(SCNPhysicsTestSearchModeClosest) \
    X(SCNPhysicsTestSearchModeKey) \
    X(SCNPreferLowPowerDeviceKey) \
    X(SCNPreferredDeviceKey) \
    X(SCNPreferredRenderingAPIKey) \
    X(SCNProgramMappingChannelKey) \
    X(SCNProjectionTransform) \
    X(SCNSceneEndTimeAttributeKey) \
    X(SCNSceneExportDestinationURL) \
    X(SCNSceneFrameRateAttributeKey) \
    X(SCNSceneSourceAnimationImportPolicyDoNotPlay) \
    X(SCNSceneSourceAnimationImportPolicyKey) \
    X(SCNSceneSourceAnimationImportPolicyPlay) \
    X(SCNSceneSourceAnimationImportPolicyPlayRepeatedly) \
    X(SCNSceneSourceAnimationImportPolicyPlayUsingSceneTimeBase) \
    X(SCNSceneSourceAssetAuthorKey) \
    X(SCNSceneSourceAssetAuthoringToolKey) \
    X(SCNSceneSourceAssetContributorsKey) \
    X(SCNSceneSourceAssetCreatedDateKey) \
    X(SCNSceneSourceAssetDirectoryURLsKey) \
    X(SCNSceneSourceAssetModifiedDateKey) \
    X(SCNSceneSourceAssetUnitKey) \
    X(SCNSceneSourceAssetUnitMeterKey) \
    X(SCNSceneSourceAssetUnitNameKey) \
    X(SCNSceneSourceAssetUpAxisKey) \
    X(SCNSceneSourceCheckConsistencyKey) \
    X(SCNSceneSourceCreateNormalsIfAbsentKey) \
    X(SCNSceneSourceFlattenSceneKey) \
    X(SCNSceneSourceLoadingOptionPreserveOriginalTopology) \
    X(SCNSceneSourceOverrideAssetURLsKey) \
    X(SCNSceneSourceStrictConformanceKey) \
    X(SCNSceneSourceUseSafeModeKey) \
    X(SCNSceneStartTimeAttributeKey) \
    X(SCNSceneUpAxisAttributeKey) \
    X(SCNShaderModifierEntryPointFragment) \
    X(SCNShaderModifierEntryPointGeometry) \
    X(SCNShaderModifierEntryPointLightingModel) \
    X(SCNShaderModifierEntryPointSurface) \
    X(SCNViewTransform)

#define LC32_DECLARE_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_DECL(__typeof__(name) name)
LC32_SCENEKIT_OBJECT_CONSTANTS(LC32_DECLARE_OBJECT_CONSTANT)
#undef LC32_DECLARE_OBJECT_CONSTANT

__attribute__((constructor))
static void LC32InitializeSceneKitObjectConstants(void) {
    LC32LoadHostFramework("SceneKit");
#define LC32_INITIALIZE_OBJECT_CONSTANT(name) LC32_CONST_STR_INIT(name);
    LC32_SCENEKIT_OBJECT_CONSTANTS(LC32_INITIALIZE_OBJECT_CONSTANT)
#undef LC32_INITIALIZE_OBJECT_CONSTANT
}

#undef LC32_SCENEKIT_OBJECT_CONSTANTS

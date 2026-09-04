#import <ModelIO/ModelIO.h>
#import <Foundation/Foundation+LC32.h>

/* Bind guest proxies to the native framework's canonical object constants. */
#define LC32_MODELIO_OBJECT_CONSTANTS(X) \
    X(MDLVertexAttributeAnisotropy) \
    X(MDLVertexAttributeBinormal) \
    X(MDLVertexAttributeBitangent) \
    X(MDLVertexAttributeColor) \
    X(MDLVertexAttributeEdgeCrease) \
    X(MDLVertexAttributeJointIndices) \
    X(MDLVertexAttributeJointWeights) \
    X(MDLVertexAttributeNormal) \
    X(MDLVertexAttributeOcclusionValue) \
    X(MDLVertexAttributePosition) \
    X(MDLVertexAttributeShadingBasisU) \
    X(MDLVertexAttributeShadingBasisV) \
    X(MDLVertexAttributeSubdivisionStencil) \
    X(MDLVertexAttributeTangent) \
    X(MDLVertexAttributeTextureCoordinate) \
    X(kUTType3dObject) \
    X(kUTTypeAlembic) \
    X(kUTTypePolygon) \
    X(kUTTypeStereolithography) \
    X(kUTTypeUniversalSceneDescription)

#define LC32_DECLARE_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_DECL(__typeof__(name) name)
LC32_MODELIO_OBJECT_CONSTANTS(LC32_DECLARE_OBJECT_CONSTANT)
#undef LC32_DECLARE_OBJECT_CONSTANT

__attribute__((constructor))
static void LC32InitializeModelIOObjectConstants(void) {
    LC32LoadHostFramework("ModelIO");
#define LC32_INITIALIZE_OBJECT_CONSTANT(name) LC32_CONST_STR_INIT(name);
    LC32_MODELIO_OBJECT_CONSTANTS(LC32_INITIALIZE_OBJECT_CONSTANT)
#undef LC32_INITIALIZE_OBJECT_CONSTANT
}

#undef LC32_MODELIO_OBJECT_CONSTANTS

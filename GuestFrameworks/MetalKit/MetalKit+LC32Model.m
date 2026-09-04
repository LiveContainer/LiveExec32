#import <MetalKit/MetalKit.h>

static const NSUInteger LC32MetalVertexTableCount = 31;

static const MDLVertexFormat LC32ModelFormatForMetalFormat[] = {
    [MTLVertexFormatInvalid] = MDLVertexFormatInvalid,
    [MTLVertexFormatUChar2] = MDLVertexFormatUChar2,
    [MTLVertexFormatUChar3] = MDLVertexFormatUChar3,
    [MTLVertexFormatUChar4] = MDLVertexFormatUChar4,
    [MTLVertexFormatChar2] = MDLVertexFormatChar2,
    [MTLVertexFormatChar3] = MDLVertexFormatChar3,
    [MTLVertexFormatChar4] = MDLVertexFormatChar4,
    [MTLVertexFormatUChar2Normalized] = MDLVertexFormatUChar2Normalized,
    [MTLVertexFormatUChar3Normalized] = MDLVertexFormatUChar3Normalized,
    [MTLVertexFormatUChar4Normalized] = MDLVertexFormatUChar4Normalized,
    [MTLVertexFormatChar2Normalized] = MDLVertexFormatChar2Normalized,
    [MTLVertexFormatChar3Normalized] = MDLVertexFormatChar3Normalized,
    [MTLVertexFormatChar4Normalized] = MDLVertexFormatChar4Normalized,
    [MTLVertexFormatUShort2] = MDLVertexFormatUShort2,
    [MTLVertexFormatUShort3] = MDLVertexFormatUShort3,
    [MTLVertexFormatUShort4] = MDLVertexFormatUShort4,
    [MTLVertexFormatShort2] = MDLVertexFormatShort2,
    [MTLVertexFormatShort3] = MDLVertexFormatShort3,
    [MTLVertexFormatShort4] = MDLVertexFormatShort4,
    [MTLVertexFormatUShort2Normalized] = MDLVertexFormatUShort2Normalized,
    [MTLVertexFormatUShort3Normalized] = MDLVertexFormatUShort3Normalized,
    [MTLVertexFormatUShort4Normalized] = MDLVertexFormatUShort4Normalized,
    [MTLVertexFormatShort2Normalized] = MDLVertexFormatShort2Normalized,
    [MTLVertexFormatShort3Normalized] = MDLVertexFormatShort3Normalized,
    [MTLVertexFormatShort4Normalized] = MDLVertexFormatShort4Normalized,
    [MTLVertexFormatHalf2] = MDLVertexFormatHalf2,
    [MTLVertexFormatHalf3] = MDLVertexFormatHalf3,
    [MTLVertexFormatHalf4] = MDLVertexFormatHalf4,
    [MTLVertexFormatFloat] = MDLVertexFormatFloat,
    [MTLVertexFormatFloat2] = MDLVertexFormatFloat2,
    [MTLVertexFormatFloat3] = MDLVertexFormatFloat3,
    [MTLVertexFormatFloat4] = MDLVertexFormatFloat4,
    [MTLVertexFormatInt] = MDLVertexFormatInt,
    [MTLVertexFormatInt2] = MDLVertexFormatInt2,
    [MTLVertexFormatInt3] = MDLVertexFormatInt3,
    [MTLVertexFormatInt4] = MDLVertexFormatInt4,
    [MTLVertexFormatUInt] = MDLVertexFormatUInt,
    [MTLVertexFormatUInt2] = MDLVertexFormatUInt2,
    [MTLVertexFormatUInt3] = MDLVertexFormatUInt3,
    [MTLVertexFormatUInt4] = MDLVertexFormatUInt4,
    [MTLVertexFormatInt1010102Normalized] =
        MDLVertexFormatInt1010102Normalized,
    [MTLVertexFormatUInt1010102Normalized] =
        MDLVertexFormatUInt1010102Normalized,
};

MDLVertexFormat MTKModelIOVertexFormatFromMetal(
        MTLVertexFormat metalFormat) {
    const NSUInteger index = (NSUInteger)metalFormat;
    if(index >= sizeof(LC32ModelFormatForMetalFormat) /
            sizeof(LC32ModelFormatForMetalFormat[0])) {
        return MDLVertexFormatInvalid;
    }
    return LC32ModelFormatForMetalFormat[index];
}

MTLVertexFormat MTKMetalVertexFormatFromModelIO(
        MDLVertexFormat modelFormat) {
    if(modelFormat == MDLVertexFormatInvalid) {
        return MTLVertexFormatInvalid;
    }
    for(NSUInteger index = 1;
            index < sizeof(LC32ModelFormatForMetalFormat) /
                sizeof(LC32ModelFormatForMetalFormat[0]);
            ++index) {
        if(LC32ModelFormatForMetalFormat[index] == modelFormat) {
            return (MTLVertexFormat)index;
        }
    }
    return MTLVertexFormatInvalid;
}

static void LC32SetMetalKitModelError(
        NSError **error, NSString *description) {
    if(!error) return;
    *error = [NSError errorWithDomain:MTKModelErrorDomain
        code:0 userInfo:@{MTKModelErrorKey: description}];
}

#pragma clang diagnostic push
/* The SDK annotates these conversion results nonnull, but MetalKit itself
 * returns nil when a source descriptor contains an unsupported format. */
#pragma clang diagnostic ignored "-Wnonnull"

MDLVertexDescriptor *MTKModelIOVertexDescriptorFromMetalWithError(
        MTLVertexDescriptor *metalDescriptor, NSError **error) {
    if(!metalDescriptor) return nil;

    MDLVertexDescriptor *modelDescriptor = [MDLVertexDescriptor new];
    for(NSUInteger index = 0;
            index < LC32MetalVertexTableCount; ++index) {
        MTLVertexAttributeDescriptor *source =
            metalDescriptor.attributes[index];
        const MDLVertexFormat format =
            MTKModelIOVertexFormatFromMetal(source.format);
        if(source.format != MTLVertexFormatInvalid &&
                format == MDLVertexFormatInvalid) {
            LC32SetMetalKitModelError(error,
                @"No compatible MDLVertexFormat format for "
                 "MTLVertexAttribute format");
            [modelDescriptor release];
            return nil;
        }

        MDLVertexAttribute *destination =
            modelDescriptor.attributes[index];
        destination.format = format;
        destination.offset = source.offset;
        destination.bufferIndex = source.bufferIndex;
        ((MDLVertexBufferLayout *)modelDescriptor.layouts[index]).stride =
            metalDescriptor.layouts[index].stride;
    }
    return [modelDescriptor autorelease];
}

MDLVertexDescriptor *MTKModelIOVertexDescriptorFromMetal(
        MTLVertexDescriptor *metalDescriptor) {
    return MTKModelIOVertexDescriptorFromMetalWithError(
        metalDescriptor, NULL);
}

MTLVertexDescriptor *MTKMetalVertexDescriptorFromModelIOWithError(
        MDLVertexDescriptor *modelDescriptor, NSError **error) {
    if(!modelDescriptor) return nil;

    MTLVertexDescriptor *metalDescriptor =
        [MTLVertexDescriptor vertexDescriptor];
    const NSUInteger attributeCount = MIN(
        modelDescriptor.attributes.count, LC32MetalVertexTableCount);
    for(NSUInteger index = 0; index < attributeCount; ++index) {
        MDLVertexAttribute *source = modelDescriptor.attributes[index];
        const MTLVertexFormat format =
            MTKMetalVertexFormatFromModelIO(source.format);
        if(source.format != MDLVertexFormatInvalid &&
                format == MTLVertexFormatInvalid) {
            LC32SetMetalKitModelError(error,
                @"No compatible MTLVertexFormat format for "
                 "MDLVertexAttribute format");
            return nil;
        }

        MTLVertexAttributeDescriptor *destination =
            metalDescriptor.attributes[index];
        destination.format = format;
        destination.offset = source.offset;
        destination.bufferIndex = source.bufferIndex;
    }

    const NSUInteger layoutCount = MIN(
        modelDescriptor.layouts.count, LC32MetalVertexTableCount);
    for(NSUInteger index = 0; index < layoutCount; ++index) {
        MDLVertexBufferLayout *source = modelDescriptor.layouts[index];
        metalDescriptor.layouts[index].stride = source.stride;
    }
    return metalDescriptor;
}

MTLVertexDescriptor *MTKMetalVertexDescriptorFromModelIO(
        MDLVertexDescriptor *modelDescriptor) {
    return MTKMetalVertexDescriptorFromModelIOWithError(
        modelDescriptor, NULL);
}

#pragma clang diagnostic pop

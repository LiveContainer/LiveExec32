#import <CoreImage/CoreImage.h>
#import <Foundation/Foundation+LC32.h>

/*
 * Keep guest exports at stable ARM32 addresses while binding each object to
 * the native framework constant. This preserves native key/identifier
 * identity when a guest collection crosses the bridge.
 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

LC32_CONST_STR_DECL(NSString *const CIDetectorAccuracy)
LC32_CONST_STR_DECL(NSString *const CIDetectorAccuracyHigh)
LC32_CONST_STR_DECL(NSString *const CIDetectorAccuracyLow)
LC32_CONST_STR_DECL(NSString *const CIDetectorAspectRatio)
LC32_CONST_STR_DECL(NSString *const CIDetectorEyeBlink)
LC32_CONST_STR_DECL(NSString *const CIDetectorFocalLength)
LC32_CONST_STR_DECL(NSString *const CIDetectorImageOrientation)
LC32_CONST_STR_DECL(NSString *const CIDetectorMaxFeatureCount)
LC32_CONST_STR_DECL(NSString *const CIDetectorMinFeatureSize)
LC32_CONST_STR_DECL(NSString *const CIDetectorNumberOfAngles)
LC32_CONST_STR_DECL(NSString *const CIDetectorReturnSubFeatures)
LC32_CONST_STR_DECL(NSString *const CIDetectorSmile)
LC32_CONST_STR_DECL(NSString *const CIDetectorTracking)
LC32_CONST_STR_DECL(NSString *const CIDetectorTypeFace)
LC32_CONST_STR_DECL(NSString *const CIDetectorTypeQRCode)
LC32_CONST_STR_DECL(NSString *const CIDetectorTypeRectangle)
LC32_CONST_STR_DECL(NSString *const CIDetectorTypeText)
LC32_CONST_STR_DECL(NSString *const CIFeatureTypeFace)
LC32_CONST_STR_DECL(NSString *const CIFeatureTypeQRCode)
LC32_CONST_STR_DECL(NSString *const CIFeatureTypeRectangle)
LC32_CONST_STR_DECL(NSString *const CIFeatureTypeText)
LC32_CONST_STR_DECL(NSString *const kCIActiveKeys)
LC32_CONST_STR_DECL(NSString *const kCIAttributeClass)
LC32_CONST_STR_DECL(NSString *const kCIAttributeDefault)
LC32_CONST_STR_DECL(NSString *const kCIAttributeDescription)
LC32_CONST_STR_DECL(NSString *const kCIAttributeDisplayName)
LC32_CONST_STR_DECL(NSString *const kCIAttributeFilterAvailable_Mac)
LC32_CONST_STR_DECL(NSString *const kCIAttributeFilterAvailable_iOS)
LC32_CONST_STR_DECL(NSString *const kCIAttributeFilterCategories)
LC32_CONST_STR_DECL(NSString *const kCIAttributeFilterDisplayName)
LC32_CONST_STR_DECL(NSString *const kCIAttributeFilterName)
LC32_CONST_STR_DECL(NSString *const kCIAttributeIdentity)
LC32_CONST_STR_DECL(NSString *const kCIAttributeMax)
LC32_CONST_STR_DECL(NSString *const kCIAttributeMin)
LC32_CONST_STR_DECL(NSString *const kCIAttributeName)
LC32_CONST_STR_DECL(NSString *const kCIAttributeReferenceDocumentation)
LC32_CONST_STR_DECL(NSString *const kCIAttributeSliderMax)
LC32_CONST_STR_DECL(NSString *const kCIAttributeSliderMin)
LC32_CONST_STR_DECL(NSString *const kCIAttributeType)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypeAngle)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypeBoolean)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypeColor)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypeCount)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypeDistance)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypeGradient)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypeImage)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypeInteger)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypeOffset)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypeOpaqueColor)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypePosition)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypePosition3)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypeRectangle)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypeScalar)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypeTime)
LC32_CONST_STR_DECL(NSString *const kCIAttributeTypeTransform)
LC32_CONST_STR_DECL(NSString *const kCICategoryBlur)
LC32_CONST_STR_DECL(NSString *const kCICategoryBuiltIn)
LC32_CONST_STR_DECL(NSString *const kCICategoryColorAdjustment)
LC32_CONST_STR_DECL(NSString *const kCICategoryColorEffect)
LC32_CONST_STR_DECL(NSString *const kCICategoryCompositeOperation)
LC32_CONST_STR_DECL(NSString *const kCICategoryDistortionEffect)
LC32_CONST_STR_DECL(NSString *const kCICategoryFilterGenerator)
LC32_CONST_STR_DECL(NSString *const kCICategoryGenerator)
LC32_CONST_STR_DECL(NSString *const kCICategoryGeometryAdjustment)
LC32_CONST_STR_DECL(NSString *const kCICategoryGradient)
LC32_CONST_STR_DECL(NSString *const kCICategoryHalftoneEffect)
LC32_CONST_STR_DECL(NSString *const kCICategoryHighDynamicRange)
LC32_CONST_STR_DECL(NSString *const kCICategoryInterlaced)
LC32_CONST_STR_DECL(NSString *const kCICategoryNonSquarePixels)
LC32_CONST_STR_DECL(NSString *const kCICategoryReduction)
LC32_CONST_STR_DECL(NSString *const kCICategorySharpen)
LC32_CONST_STR_DECL(NSString *const kCICategoryStillImage)
LC32_CONST_STR_DECL(NSString *const kCICategoryStylize)
LC32_CONST_STR_DECL(NSString *const kCICategoryTileEffect)
LC32_CONST_STR_DECL(NSString *const kCICategoryTransition)
LC32_CONST_STR_DECL(NSString *const kCICategoryVideo)
LC32_CONST_STR_DECL(NSString *const kCIContextCacheIntermediates)
LC32_CONST_STR_DECL(NSString *const kCIContextHighQualityDownsample)
LC32_CONST_STR_DECL(NSString *const kCIContextOutputColorSpace)
LC32_CONST_STR_DECL(NSString *const kCIContextOutputPremultiplied)
LC32_CONST_STR_DECL(NSString *const kCIContextPriorityRequestLow)
LC32_CONST_STR_DECL(NSString *const kCIContextUseSoftwareRenderer)
LC32_CONST_STR_DECL(NSString *const kCIContextWorkingColorSpace)
LC32_CONST_STR_DECL(NSString *const kCIContextWorkingFormat)
LC32_CONST_STR_DECL(NSString *const kCIImageAutoAdjustCrop)
LC32_CONST_STR_DECL(NSString *const kCIImageAutoAdjustEnhance)
LC32_CONST_STR_DECL(NSString *const kCIImageAutoAdjustFeatures)
LC32_CONST_STR_DECL(NSString *const kCIImageAutoAdjustLevel)
LC32_CONST_STR_DECL(NSString *const kCIImageAutoAdjustRedEye)
LC32_CONST_STR_DECL(NSString *const kCIImageColorSpace)
LC32_CONST_STR_DECL(NSString *const kCIImageProperties)
LC32_CONST_STR_DECL(NSString *const kCIImageProviderTileSize)
LC32_CONST_STR_DECL(NSString *const kCIImageProviderUserInfo)
LC32_CONST_STR_DECL(NSString *const kCIInputAllowDraftModeKey)
LC32_CONST_STR_DECL(NSString *const kCIInputAngleKey)
LC32_CONST_STR_DECL(NSString *const kCIInputAspectRatioKey)
LC32_CONST_STR_DECL(NSString *const kCIInputBackgroundImageKey)
LC32_CONST_STR_DECL(NSString *const kCIInputBaselineExposureKey)
LC32_CONST_STR_DECL(NSString *const kCIInputBiasKey)
LC32_CONST_STR_DECL(NSString *const kCIInputBoostKey)
LC32_CONST_STR_DECL(NSString *const kCIInputBoostShadowAmountKey)
LC32_CONST_STR_DECL(NSString *const kCIInputBrightnessKey)
LC32_CONST_STR_DECL(NSString *const kCIInputCenterKey)
LC32_CONST_STR_DECL(NSString *const kCIInputColorKey)
LC32_CONST_STR_DECL(NSString *const kCIInputColorNoiseReductionAmountKey)
LC32_CONST_STR_DECL(NSString *const kCIInputContrastKey)
LC32_CONST_STR_DECL(NSString *const kCIInputDecoderVersionKey)
LC32_CONST_STR_DECL(NSString *const kCIInputDisableGamutMapKey)
LC32_CONST_STR_DECL(NSString *const kCIInputEVKey)
LC32_CONST_STR_DECL(NSString *const kCIInputEnableChromaticNoiseTrackingKey)
LC32_CONST_STR_DECL(NSString *const kCIInputEnableSharpeningKey)
LC32_CONST_STR_DECL(NSString *const kCIInputEnableVendorLensCorrectionKey)
LC32_CONST_STR_DECL(NSString *const kCIInputExtentKey)
LC32_CONST_STR_DECL(NSString *const kCIInputGradientImageKey)
LC32_CONST_STR_DECL(NSString *const kCIInputIgnoreImageOrientationKey)
LC32_CONST_STR_DECL(NSString *const kCIInputImageKey)
LC32_CONST_STR_DECL(NSString *const kCIInputImageOrientationKey)
LC32_CONST_STR_DECL(NSString *const kCIInputIntensityKey)
LC32_CONST_STR_DECL(NSString *const kCIInputLinearSpaceFilter)
LC32_CONST_STR_DECL(NSString *const kCIInputLuminanceNoiseReductionAmountKey)
LC32_CONST_STR_DECL(NSString *const kCIInputMaskImageKey)
LC32_CONST_STR_DECL(NSString *const kCIInputNeutralChromaticityXKey)
LC32_CONST_STR_DECL(NSString *const kCIInputNeutralChromaticityYKey)
LC32_CONST_STR_DECL(NSString *const kCIInputNeutralLocationKey)
LC32_CONST_STR_DECL(NSString *const kCIInputNeutralTemperatureKey)
LC32_CONST_STR_DECL(NSString *const kCIInputNeutralTintKey)
LC32_CONST_STR_DECL(NSString *const kCIInputNoiseReductionAmountKey)
LC32_CONST_STR_DECL(NSString *const kCIInputNoiseReductionContrastAmountKey)
LC32_CONST_STR_DECL(NSString *const kCIInputNoiseReductionDetailAmountKey)
LC32_CONST_STR_DECL(NSString *const kCIInputNoiseReductionSharpnessAmountKey)
LC32_CONST_STR_DECL(NSString *const kCIInputRadiusKey)
LC32_CONST_STR_DECL(NSString *const kCIInputRefractionKey)
LC32_CONST_STR_DECL(NSString *const kCIInputSaturationKey)
LC32_CONST_STR_DECL(NSString *const kCIInputScaleFactorKey)
LC32_CONST_STR_DECL(NSString *const kCIInputScaleKey)
LC32_CONST_STR_DECL(NSString *const kCIInputShadingImageKey)
LC32_CONST_STR_DECL(NSString *const kCIInputSharpnessKey)
LC32_CONST_STR_DECL(NSString *const kCIInputTargetImageKey)
LC32_CONST_STR_DECL(NSString *const kCIInputTimeKey)
LC32_CONST_STR_DECL(NSString *const kCIInputTransformKey)
LC32_CONST_STR_DECL(NSString *const kCIInputVersionKey)
LC32_CONST_STR_DECL(NSString *const kCIInputWeightsKey)
LC32_CONST_STR_DECL(NSString *const kCIInputWidthKey)
LC32_CONST_STR_DECL(NSString *const kCIOutputImageKey)
LC32_CONST_STR_DECL(NSString *const kCIOutputNativeSizeKey)
LC32_CONST_STR_DECL(NSString *const kCISamplerAffineMatrix)
LC32_CONST_STR_DECL(NSString *const kCISamplerColorSpace)
LC32_CONST_STR_DECL(NSString *const kCISamplerFilterLinear)
LC32_CONST_STR_DECL(NSString *const kCISamplerFilterMode)
LC32_CONST_STR_DECL(NSString *const kCISamplerFilterNearest)
LC32_CONST_STR_DECL(NSString *const kCISamplerWrapBlack)
LC32_CONST_STR_DECL(NSString *const kCISamplerWrapClamp)
LC32_CONST_STR_DECL(NSString *const kCISamplerWrapMode)
LC32_CONST_STR_DECL(NSString *const kCISupportedDecoderVersionsKey)
LC32_CONST_STR_DECL(NSString *const kCIUIParameterSet)
LC32_CONST_STR_DECL(NSString *const kCIUISetAdvanced)
LC32_CONST_STR_DECL(NSString *const kCIUISetBasic)
LC32_CONST_STR_DECL(NSString *const kCIUISetDevelopment)
LC32_CONST_STR_DECL(NSString *const kCIUISetIntermediate)

__attribute__((constructor)) static void LC32InitializeCoreImageConstants(void) {
    LC32LoadHostFramework("CoreImage");
    LC32_CONST_STR_INIT(CIDetectorAccuracy);
    LC32_CONST_STR_INIT(CIDetectorAccuracyHigh);
    LC32_CONST_STR_INIT(CIDetectorAccuracyLow);
    LC32_CONST_STR_INIT(CIDetectorAspectRatio);
    LC32_CONST_STR_INIT(CIDetectorEyeBlink);
    LC32_CONST_STR_INIT(CIDetectorFocalLength);
    LC32_CONST_STR_INIT(CIDetectorImageOrientation);
    LC32_CONST_STR_INIT(CIDetectorMaxFeatureCount);
    LC32_CONST_STR_INIT(CIDetectorMinFeatureSize);
    LC32_CONST_STR_INIT(CIDetectorNumberOfAngles);
    LC32_CONST_STR_INIT(CIDetectorReturnSubFeatures);
    LC32_CONST_STR_INIT(CIDetectorSmile);
    LC32_CONST_STR_INIT(CIDetectorTracking);
    LC32_CONST_STR_INIT(CIDetectorTypeFace);
    LC32_CONST_STR_INIT(CIDetectorTypeQRCode);
    LC32_CONST_STR_INIT(CIDetectorTypeRectangle);
    LC32_CONST_STR_INIT(CIDetectorTypeText);
    LC32_CONST_STR_INIT(CIFeatureTypeFace);
    LC32_CONST_STR_INIT(CIFeatureTypeQRCode);
    LC32_CONST_STR_INIT(CIFeatureTypeRectangle);
    LC32_CONST_STR_INIT(CIFeatureTypeText);
    LC32_CONST_STR_INIT(kCIActiveKeys);
    LC32_CONST_STR_INIT(kCIAttributeClass);
    LC32_CONST_STR_INIT(kCIAttributeDefault);
    LC32_CONST_STR_INIT(kCIAttributeDescription);
    LC32_CONST_STR_INIT(kCIAttributeDisplayName);
    LC32_CONST_STR_INIT(kCIAttributeFilterAvailable_Mac);
    LC32_CONST_STR_INIT(kCIAttributeFilterAvailable_iOS);
    LC32_CONST_STR_INIT(kCIAttributeFilterCategories);
    LC32_CONST_STR_INIT(kCIAttributeFilterDisplayName);
    LC32_CONST_STR_INIT(kCIAttributeFilterName);
    LC32_CONST_STR_INIT(kCIAttributeIdentity);
    LC32_CONST_STR_INIT(kCIAttributeMax);
    LC32_CONST_STR_INIT(kCIAttributeMin);
    LC32_CONST_STR_INIT(kCIAttributeName);
    LC32_CONST_STR_INIT(kCIAttributeReferenceDocumentation);
    LC32_CONST_STR_INIT(kCIAttributeSliderMax);
    LC32_CONST_STR_INIT(kCIAttributeSliderMin);
    LC32_CONST_STR_INIT(kCIAttributeType);
    LC32_CONST_STR_INIT(kCIAttributeTypeAngle);
    LC32_CONST_STR_INIT(kCIAttributeTypeBoolean);
    LC32_CONST_STR_INIT(kCIAttributeTypeColor);
    LC32_CONST_STR_INIT(kCIAttributeTypeCount);
    LC32_CONST_STR_INIT(kCIAttributeTypeDistance);
    LC32_CONST_STR_INIT(kCIAttributeTypeGradient);
    LC32_CONST_STR_INIT(kCIAttributeTypeImage);
    LC32_CONST_STR_INIT(kCIAttributeTypeInteger);
    LC32_CONST_STR_INIT(kCIAttributeTypeOffset);
    LC32_CONST_STR_INIT(kCIAttributeTypeOpaqueColor);
    LC32_CONST_STR_INIT(kCIAttributeTypePosition);
    LC32_CONST_STR_INIT(kCIAttributeTypePosition3);
    LC32_CONST_STR_INIT(kCIAttributeTypeRectangle);
    LC32_CONST_STR_INIT(kCIAttributeTypeScalar);
    LC32_CONST_STR_INIT(kCIAttributeTypeTime);
    LC32_CONST_STR_INIT(kCIAttributeTypeTransform);
    LC32_CONST_STR_INIT(kCICategoryBlur);
    LC32_CONST_STR_INIT(kCICategoryBuiltIn);
    LC32_CONST_STR_INIT(kCICategoryColorAdjustment);
    LC32_CONST_STR_INIT(kCICategoryColorEffect);
    LC32_CONST_STR_INIT(kCICategoryCompositeOperation);
    LC32_CONST_STR_INIT(kCICategoryDistortionEffect);
    LC32_CONST_STR_INIT(kCICategoryFilterGenerator);
    LC32_CONST_STR_INIT(kCICategoryGenerator);
    LC32_CONST_STR_INIT(kCICategoryGeometryAdjustment);
    LC32_CONST_STR_INIT(kCICategoryGradient);
    LC32_CONST_STR_INIT(kCICategoryHalftoneEffect);
    LC32_CONST_STR_INIT(kCICategoryHighDynamicRange);
    LC32_CONST_STR_INIT(kCICategoryInterlaced);
    LC32_CONST_STR_INIT(kCICategoryNonSquarePixels);
    LC32_CONST_STR_INIT(kCICategoryReduction);
    LC32_CONST_STR_INIT(kCICategorySharpen);
    LC32_CONST_STR_INIT(kCICategoryStillImage);
    LC32_CONST_STR_INIT(kCICategoryStylize);
    LC32_CONST_STR_INIT(kCICategoryTileEffect);
    LC32_CONST_STR_INIT(kCICategoryTransition);
    LC32_CONST_STR_INIT(kCICategoryVideo);
    LC32_CONST_STR_INIT(kCIContextCacheIntermediates);
    LC32_CONST_STR_INIT(kCIContextHighQualityDownsample);
    LC32_CONST_STR_INIT(kCIContextOutputColorSpace);
    LC32_CONST_STR_INIT(kCIContextOutputPremultiplied);
    LC32_CONST_STR_INIT(kCIContextPriorityRequestLow);
    LC32_CONST_STR_INIT(kCIContextUseSoftwareRenderer);
    LC32_CONST_STR_INIT(kCIContextWorkingColorSpace);
    LC32_CONST_STR_INIT(kCIContextWorkingFormat);
    LC32_CONST_STR_INIT(kCIImageAutoAdjustCrop);
    LC32_CONST_STR_INIT(kCIImageAutoAdjustEnhance);
    LC32_CONST_STR_INIT(kCIImageAutoAdjustFeatures);
    LC32_CONST_STR_INIT(kCIImageAutoAdjustLevel);
    LC32_CONST_STR_INIT(kCIImageAutoAdjustRedEye);
    LC32_CONST_STR_INIT(kCIImageColorSpace);
    LC32_CONST_STR_INIT(kCIImageProperties);
    LC32_CONST_STR_INIT(kCIImageProviderTileSize);
    LC32_CONST_STR_INIT(kCIImageProviderUserInfo);
    LC32_CONST_STR_INIT(kCIInputAllowDraftModeKey);
    LC32_CONST_STR_INIT(kCIInputAngleKey);
    LC32_CONST_STR_INIT(kCIInputAspectRatioKey);
    LC32_CONST_STR_INIT(kCIInputBackgroundImageKey);
    LC32_CONST_STR_INIT(kCIInputBaselineExposureKey);
    LC32_CONST_STR_INIT(kCIInputBiasKey);
    LC32_CONST_STR_INIT(kCIInputBoostKey);
    LC32_CONST_STR_INIT(kCIInputBoostShadowAmountKey);
    LC32_CONST_STR_INIT(kCIInputBrightnessKey);
    LC32_CONST_STR_INIT(kCIInputCenterKey);
    LC32_CONST_STR_INIT(kCIInputColorKey);
    LC32_CONST_STR_INIT(kCIInputColorNoiseReductionAmountKey);
    LC32_CONST_STR_INIT(kCIInputContrastKey);
    LC32_CONST_STR_INIT(kCIInputDecoderVersionKey);
    LC32_CONST_STR_INIT(kCIInputDisableGamutMapKey);
    LC32_CONST_STR_INIT(kCIInputEVKey);
    LC32_CONST_STR_INIT(kCIInputEnableChromaticNoiseTrackingKey);
    LC32_CONST_STR_INIT(kCIInputEnableSharpeningKey);
    LC32_CONST_STR_INIT(kCIInputEnableVendorLensCorrectionKey);
    LC32_CONST_STR_INIT(kCIInputExtentKey);
    LC32_CONST_STR_INIT(kCIInputGradientImageKey);
    LC32_CONST_STR_INIT(kCIInputIgnoreImageOrientationKey);
    LC32_CONST_STR_INIT(kCIInputImageKey);
    LC32_CONST_STR_INIT(kCIInputImageOrientationKey);
    LC32_CONST_STR_INIT(kCIInputIntensityKey);
    LC32_CONST_STR_INIT(kCIInputLinearSpaceFilter);
    LC32_CONST_STR_INIT(kCIInputLuminanceNoiseReductionAmountKey);
    LC32_CONST_STR_INIT(kCIInputMaskImageKey);
    LC32_CONST_STR_INIT(kCIInputNeutralChromaticityXKey);
    LC32_CONST_STR_INIT(kCIInputNeutralChromaticityYKey);
    LC32_CONST_STR_INIT(kCIInputNeutralLocationKey);
    LC32_CONST_STR_INIT(kCIInputNeutralTemperatureKey);
    LC32_CONST_STR_INIT(kCIInputNeutralTintKey);
    LC32_CONST_STR_INIT(kCIInputNoiseReductionAmountKey);
    LC32_CONST_STR_INIT(kCIInputNoiseReductionContrastAmountKey);
    LC32_CONST_STR_INIT(kCIInputNoiseReductionDetailAmountKey);
    LC32_CONST_STR_INIT(kCIInputNoiseReductionSharpnessAmountKey);
    LC32_CONST_STR_INIT(kCIInputRadiusKey);
    LC32_CONST_STR_INIT(kCIInputRefractionKey);
    LC32_CONST_STR_INIT(kCIInputSaturationKey);
    LC32_CONST_STR_INIT(kCIInputScaleFactorKey);
    LC32_CONST_STR_INIT(kCIInputScaleKey);
    LC32_CONST_STR_INIT(kCIInputShadingImageKey);
    LC32_CONST_STR_INIT(kCIInputSharpnessKey);
    LC32_CONST_STR_INIT(kCIInputTargetImageKey);
    LC32_CONST_STR_INIT(kCIInputTimeKey);
    LC32_CONST_STR_INIT(kCIInputTransformKey);
    LC32_CONST_STR_INIT(kCIInputVersionKey);
    LC32_CONST_STR_INIT(kCIInputWeightsKey);
    LC32_CONST_STR_INIT(kCIInputWidthKey);
    LC32_CONST_STR_INIT(kCIOutputImageKey);
    LC32_CONST_STR_INIT(kCIOutputNativeSizeKey);
    LC32_CONST_STR_INIT(kCISamplerAffineMatrix);
    LC32_CONST_STR_INIT(kCISamplerColorSpace);
    LC32_CONST_STR_INIT(kCISamplerFilterLinear);
    LC32_CONST_STR_INIT(kCISamplerFilterMode);
    LC32_CONST_STR_INIT(kCISamplerFilterNearest);
    LC32_CONST_STR_INIT(kCISamplerWrapBlack);
    LC32_CONST_STR_INIT(kCISamplerWrapClamp);
    LC32_CONST_STR_INIT(kCISamplerWrapMode);
    LC32_CONST_STR_INIT(kCISupportedDecoderVersionsKey);
    LC32_CONST_STR_INIT(kCIUIParameterSet);
    LC32_CONST_STR_INIT(kCIUISetAdvanced);
    LC32_CONST_STR_INIT(kCIUISetBasic);
    LC32_CONST_STR_INIT(kCIUISetDevelopment);
    LC32_CONST_STR_INIT(kCIUISetIntermediate);
}

#pragma clang diagnostic pop

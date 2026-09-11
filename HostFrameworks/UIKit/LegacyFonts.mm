#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <cmath>
#include <cstring>
#include <mach-o/loader.h>
#include <stdint.h>

struct LC32FontDyldBuildVersion {
    uint32_t platform;
    uint32_t version;
};
extern "C" bool dyld_program_sdk_at_least(LC32FontDyldBuildVersion version);

static thread_local bool LC32RepairingLegacyFont;
using LC32FontRetry = id (^)(UITraitCollection *);

static bool LC32FiniteFont(UIFont *font) {
    return font && std::isfinite(font.pointSize) && std::isfinite(font.ascender) &&
        std::isfinite(font.descender) && std::isfinite(font.lineHeight);
}

/* Only used on an already-invalid preferred font. Keep valid authored traits,
 * features, variations and transforms, not NaN values nested inside them. */
static id LC32FiniteFontAttribute(id value) {
    if([value isKindOfClass:NSNumber.class])
        return std::isfinite([value doubleValue]) ? value : nil;
    if([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for(id key in value) {
            id child = LC32FiniteFontAttribute(value[key]);
            if(child) result[key] = child;
        }
        return result;
    }
    if([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray array];
        for(id child in value) {
            id finite = LC32FiniteFontAttribute(child);
            if(finite) [result addObject:finite];
        }
        return result;
    }
    if([value isKindOfClass:NSValue.class] &&
       !strcmp([value objCType], @encode(CGAffineTransform))) {
        CGAffineTransform matrix = [value CGAffineTransformValue];
        if(!std::isfinite(matrix.a) || !std::isfinite(matrix.b) ||
           !std::isfinite(matrix.c) || !std::isfinite(matrix.d) ||
           !std::isfinite(matrix.tx) || !std::isfinite(matrix.ty)) return nil;
    }
    return value;
}

static UITraitCollection *LC32LargestFiniteFontTraits(UITraitCollection *traits) {
    /* The pre-iOS-11 CoreText override has missing accessibility-size records.
     * Do not invent modern AX sizes or scale from an unrelated Body font: only
     * when the original size is nonfinite, clamp to the last normal category.
     * This deliberately sacrifices further AX enlargement for a usable font.
     * Retain the caller's other traits, including legibility and interface idiom. */
    return [UITraitCollection traitCollectionWithTraitsFromCollections:@[
        traits ?: UITraitCollection.currentTraitCollection,
        [UITraitCollection traitCollectionWithPreferredContentSizeCategory:
            UIContentSizeCategoryExtraExtraExtraLarge]]];
}

static id LC32RepairPreferredFont(id original, bool descriptorResult,
                                 UITraitCollection *traits, LC32FontRetry retry) {
    if(!original || LC32RepairingLegacyFont) return original;
    struct RepairScope {
        RepairScope() { LC32RepairingLegacyFont = true; }
        ~RepairScope() { LC32RepairingLegacyFont = false; }
    } scope;

    UIFontDescriptor *descriptor = descriptorResult ? original : [original fontDescriptor];
    UIFont *font = descriptorResult ? [UIFont fontWithDescriptor:descriptor size:0] : original;
    CGFloat size = descriptorResult ? descriptor.pointSize : font.pointSize;
    if(std::isfinite(size) && LC32FiniteFont(font)) return original;

    UIFont *resolvedFont = font;
    if(!std::isfinite(size)) {
        id fallback = retry(LC32LargestFiniteFontTraits(traits));
        UIFontDescriptor *fallbackDescriptor = descriptorResult ? fallback : [fallback fontDescriptor];
        resolvedFont = descriptorResult ? [UIFont fontWithDescriptor:fallbackDescriptor size:0] : fallback;
        size = descriptorResult ? fallbackDescriptor.pointSize : resolvedFont.pointSize;
    }
    if(!resolvedFont || !std::isfinite(size) || size <= 0 || !resolvedFont.fontName.length)
        return original;

    NSMutableDictionary *attributes = [LC32FiniteFontAttribute(
        resolvedFont.fontDescriptor.fontAttributes) mutableCopy];
    [attributes addEntriesFromDictionary:LC32FiniteFontAttribute(descriptor.fontAttributes)];

    /* Merely fixing a CTFont's language-aware ratio is insufficient: UIFont's
     * fontDescriptor can drop that override while retaining text-style usage,
     * causing a subsequent fontWithDescriptor: to recompute the same NaNs.
     * Resolve to the actual native face and size instead. These private key
     * spellings are descriptor metadata, not OS-specific offsets or symbols.
     * UIFontDescriptorTextStyleAttribute also names NSCTFontUIUsageAttribute
     * on current UIKit; removing both is harmless on other SDKs. */
    [attributes removeObjectsForKeys:@[
        UIFontDescriptorTextStyleAttribute, @"NSCTFontUIUsageAttribute",
        @"NSCTFontSizeCategoryAttribute", @"CTFontLanguageAwareLineHeightRatioAttribute",
        @"CTFontLineSpacingOverrideAttribute"]];
    attributes[UIFontDescriptorNameAttribute] = resolvedFont.fontName;
    attributes[UIFontDescriptorSizeAttribute] = @(size);
    UIFontDescriptor *concrete = [UIFontDescriptor fontDescriptorWithFontAttributes:attributes];
    UIFont *repaired = [UIFont fontWithDescriptor:concrete size:size];
    if(!LC32FiniteFont(repaired)) return original;
    return descriptorResult ? concrete : repaired;
}

static void swizzle(Class cls, SEL originalAction, SEL swizzledAction) {
    Method originalMethod = class_getInstanceMethod(cls, originalAction);
    if(!originalMethod) {
        NSLog(@"%s not found", sel_getName(originalAction));
        return;
    }
    method_exchangeImplementations(originalMethod,
        class_getInstanceMethod(cls, swizzledAction));
}

@implementation UIFont (LC32LegacyFonts)
+ (void)load {
    if(dyld_program_sdk_at_least({PLATFORM_IOS, 0x000b0000})) return;

    /* Modern CoreText's pre-iOS-11 text-style table can produce nonfinite line
     * metrics (language dependent) and nonfinite accessibility point sizes.
     * Native UIKit uses these fonts too, so repairing only guest UIFont calls
     * misses alerts and other system controls. Hook creation, not metric getters:
     * the returned UIFont and its descriptor must both be usable by CoreText.
     * Valid fonts remain untouched, and no process SDK or font table is changed.
     * This safety fix is independent of the optional LC32 geometry adapters. */
    Class cls = object_getClass(self);
    swizzle(cls, @selector(preferredFontForTextStyle:),
        @selector(lc32_preferredFontForTextStyle:));
    swizzle(cls, @selector(preferredFontForTextStyle:compatibleWithTraitCollection:),
        @selector(lc32_preferredFontForTextStyle:compatibleWithTraitCollection:));
    swizzle(cls, @selector(_preferredFontForTextStyle:maximumContentSizeCategory:compatibleWithTraitCollection:),
        @selector(lc32_preferredFontForTextStyle:maximumContentSizeCategory:compatibleWithTraitCollection:));
    swizzle(cls, @selector(_preferredFontForTextStyle:design:weight:symbolicTraits:maximumContentSizeCategory:compatibleWithTraitCollection:pointSize:pointSizeForScaling:),
        @selector(lc32_preferredFontForTextStyle:design:weight:symbolicTraits:maximumContentSizeCategory:compatibleWithTraitCollection:pointSize:pointSizeForScaling:));
}

+ (UIFont *)lc32_preferredFontForTextStyle:(UIFontTextStyle)style {
    UIFont *result = [self lc32_preferredFontForTextStyle:style];
    return LC32RepairPreferredFont(result, false, nil, ^id(UITraitCollection *fallback) {
        // The one-argument spelling has no place to pass the category.
        return [self lc32_preferredFontForTextStyle:style compatibleWithTraitCollection:fallback];
    });
}

+ (UIFont *)lc32_preferredFontForTextStyle:(UIFontTextStyle)style
            compatibleWithTraitCollection:(UITraitCollection *)traits {
    UIFont *result = [self lc32_preferredFontForTextStyle:style compatibleWithTraitCollection:traits];
    return LC32RepairPreferredFont(result, false, traits, ^id(UITraitCollection *fallback) {
        return [self lc32_preferredFontForTextStyle:style compatibleWithTraitCollection:fallback];
    });
}

+ (UIFont *)lc32_preferredFontForTextStyle:(UIFontTextStyle)style
               maximumContentSizeCategory:(UIContentSizeCategory)maximum
            compatibleWithTraitCollection:(UITraitCollection *)traits {
    UIFont *result = [self lc32_preferredFontForTextStyle:style
        maximumContentSizeCategory:maximum compatibleWithTraitCollection:traits];
    return LC32RepairPreferredFont(result, false, traits, ^id(UITraitCollection *fallback) {
        return [self lc32_preferredFontForTextStyle:style
            maximumContentSizeCategory:maximum compatibleWithTraitCollection:fallback];
    });
}

+ (UIFont *)lc32_preferredFontForTextStyle:(UIFontTextStyle)style
                                   design:(NSString *)design
                                   weight:(NSNumber *)weight
                           symbolicTraits:(UIFontDescriptorSymbolicTraits)symbolic
               maximumContentSizeCategory:(UIContentSizeCategory)maximum
            compatibleWithTraitCollection:(UITraitCollection *)traits
                                pointSize:(CGFloat)size
                      pointSizeForScaling:(CGFloat)scalingSize {
    UIFont *result = [self lc32_preferredFontForTextStyle:style design:design
        weight:weight symbolicTraits:symbolic maximumContentSizeCategory:maximum
        compatibleWithTraitCollection:traits pointSize:size pointSizeForScaling:scalingSize];
    return LC32RepairPreferredFont(result, false, traits, ^id(UITraitCollection *fallback) {
        return [self lc32_preferredFontForTextStyle:style design:design weight:weight
            symbolicTraits:symbolic maximumContentSizeCategory:maximum
            compatibleWithTraitCollection:fallback pointSize:size pointSizeForScaling:scalingSize];
    });
}
@end

@implementation UIFontDescriptor (LC32LegacyFonts)
+ (void)load {
    if(dyld_program_sdk_at_least({PLATFORM_IOS, 0x000b0000})) return;
    Class cls = object_getClass(self);
    swizzle(cls, @selector(preferredFontDescriptorWithTextStyle:),
        @selector(lc32_preferredFontDescriptorWithTextStyle:));
    swizzle(cls, @selector(preferredFontDescriptorWithTextStyle:compatibleWithTraitCollection:),
        @selector(lc32_preferredFontDescriptorWithTextStyle:compatibleWithTraitCollection:));
    swizzle(cls, @selector(_preferredFontDescriptorWithTextStyle:addingSymbolicTraits:compatibleWithTraitCollection:),
        @selector(lc32_preferredFontDescriptorWithTextStyle:addingSymbolicTraits:compatibleWithTraitCollection:));
    swizzle(cls, @selector(preferredFontDescriptorWithTextStyle:addingSymbolicTraits:options:),
        @selector(lc32_preferredFontDescriptorWithTextStyle:addingSymbolicTraits:options:));
    swizzle(cls, @selector(_preferredFontDescriptorWithTextStyle:design:weight:compatibleWithTraitCollection:),
        @selector(lc32_preferredFontDescriptorWithTextStyle:design:weight:compatibleWithTraitCollection:));
    swizzle(cls, @selector(_preferredFontDescriptorWithTextStyle:addingSymbolicTraits:design:weight:compatibleWithTraitCollection:),
        @selector(lc32_preferredFontDescriptorWithTextStyle:addingSymbolicTraits:design:weight:compatibleWithTraitCollection:));
}

+ (UIFontDescriptor *)lc32_preferredFontDescriptorWithTextStyle:(UIFontTextStyle)style {
    UIFontDescriptor *result = [self lc32_preferredFontDescriptorWithTextStyle:style];
    return LC32RepairPreferredFont(result, true, nil, ^id(UITraitCollection *fallback) {
        return [self lc32_preferredFontDescriptorWithTextStyle:style compatibleWithTraitCollection:fallback];
    });
}

+ (UIFontDescriptor *)lc32_preferredFontDescriptorWithTextStyle:(UIFontTextStyle)style
                                compatibleWithTraitCollection:(UITraitCollection *)traits {
    UIFontDescriptor *result = [self lc32_preferredFontDescriptorWithTextStyle:style
        compatibleWithTraitCollection:traits];
    return LC32RepairPreferredFont(result, true, traits, ^id(UITraitCollection *fallback) {
        return [self lc32_preferredFontDescriptorWithTextStyle:style compatibleWithTraitCollection:fallback];
    });
}

+ (UIFontDescriptor *)lc32_preferredFontDescriptorWithTextStyle:(UIFontTextStyle)style
                                         addingSymbolicTraits:(UIFontDescriptorSymbolicTraits)symbolic
                                compatibleWithTraitCollection:(UITraitCollection *)traits {
    UIFontDescriptor *result = [self lc32_preferredFontDescriptorWithTextStyle:style
        addingSymbolicTraits:symbolic compatibleWithTraitCollection:traits];
    return LC32RepairPreferredFont(result, true, traits, ^id(UITraitCollection *fallback) {
        return [self lc32_preferredFontDescriptorWithTextStyle:style
            addingSymbolicTraits:symbolic compatibleWithTraitCollection:fallback];
    });
}

+ (UIFontDescriptor *)lc32_preferredFontDescriptorWithTextStyle:(UIFontTextStyle)style
                                         addingSymbolicTraits:(UIFontDescriptorSymbolicTraits)symbolic
                                                      options:(NSUInteger)options {
    /* Native alert text fields and action-sheet titles use this factory,
     * which calls CoreText directly rather than the trait-taking methods.
     * For a missing AX point size, option bit 0 caps the legacy category at
     * XXXL; preserve all other option bits and symbolic traits. */
    UIFontDescriptor *result = [self lc32_preferredFontDescriptorWithTextStyle:style
        addingSymbolicTraits:symbolic options:options];
    return LC32RepairPreferredFont(result, true, nil, ^id(UITraitCollection *) {
        return [self lc32_preferredFontDescriptorWithTextStyle:style
            addingSymbolicTraits:symbolic options:options | 1u];
    });
}

+ (UIFontDescriptor *)lc32_preferredFontDescriptorWithTextStyle:(UIFontTextStyle)style
                                                       design:(NSString *)design
                                                       weight:(CGFloat)weight
                                compatibleWithTraitCollection:(UITraitCollection *)traits {
    UIFontDescriptor *result = [self lc32_preferredFontDescriptorWithTextStyle:style
        design:design weight:weight compatibleWithTraitCollection:traits];
    return LC32RepairPreferredFont(result, true, traits, ^id(UITraitCollection *fallback) {
        return [self lc32_preferredFontDescriptorWithTextStyle:style
            design:design weight:weight compatibleWithTraitCollection:fallback];
    });
}

+ (UIFontDescriptor *)lc32_preferredFontDescriptorWithTextStyle:(UIFontTextStyle)style
                                         addingSymbolicTraits:(UIFontDescriptorSymbolicTraits)symbolic
                                                       design:(NSString *)design
                                                       weight:(CGFloat)weight
                                compatibleWithTraitCollection:(UITraitCollection *)traits {
    UIFontDescriptor *result = [self lc32_preferredFontDescriptorWithTextStyle:style
        addingSymbolicTraits:symbolic design:design weight:weight compatibleWithTraitCollection:traits];
    return LC32RepairPreferredFont(result, true, traits, ^id(UITraitCollection *fallback) {
        return [self lc32_preferredFontDescriptorWithTextStyle:style addingSymbolicTraits:symbolic
            design:design weight:weight compatibleWithTraitCollection:fallback];
    });
}
@end

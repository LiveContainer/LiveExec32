@import CoreGraphics;
@import CoreText;

#include "bridge.h"
#include "../CoreGraphics/LC32CoreGraphicsHost.h"
#include "../../GuestFrameworks/CoreText/LC32CoreTextBridge.h"

#include <algorithm>
#include <limits>
#include <vector>

namespace {

bool ReadCoreTextCall(u32 guestAddress, LC32CoreTextCall &call) {
    struct {
        uint32_t version;
        uint32_t slotCount;
    } header = {};
    if(!guestAddress ||
       Dynarmic_mem_1read(guestAddress, sizeof(header),
           reinterpret_cast<char *>(&header)) != 0 ||
       header.version != LC32CoreTextABIVersion ||
       header.slotCount > LC32CoreTextMaxSlots) {
        return false;
    }

    call = {};
    call.version = header.version;
    call.slotCount = header.slotCount;
    const size_t byteCount = header.slotCount * sizeof(call.slots[0]);
    const uint64_t slotsAddress = static_cast<uint64_t>(guestAddress) +
        offsetof(LC32CoreTextCall, slots);
    if(slotsAddress > UINT32_MAX ||
       slotsAddress + byteCount > static_cast<uint64_t>(UINT32_MAX) + 1) {
        return false;
    }
    return !byteCount || Dynarmic_mem_1read(static_cast<u32>(slotsAddress),
        byteCount, reinterpret_cast<char *>(call.slots)) == 0;
}

bool RequireCoreTextSlots(const LC32CoreTextCall &call, uint32_t count) {
    return call.slotCount == count;
}

u32 SlotU32(const LC32CoreTextCall &call, size_t index) {
    return static_cast<u32>(call.slots[index]);
}

CFIndex SlotIndex(const LC32CoreTextCall &call, size_t index) {
    return static_cast<CFIndex>(static_cast<int32_t>(SlotU32(call, index)));
}

template<typename T>
T SlotHostObject(const LC32CoreTextCall &call, size_t index) {
    return reinterpret_cast<T>(static_cast<uintptr_t>(call.slots[index]));
}

CGFloat SlotCGFloat(const LC32CoreTextCall &call, size_t index) {
    const uint32_t bits = SlotU32(call, index);
    float value;
    memcpy(&value, &bits, sizeof(value));
    return static_cast<CGFloat>(value);
}

double SlotDouble(const LC32CoreTextCall &call, size_t index) {
    const uint64_t bits = call.slots[index];
    double value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

u32 ReturnCGFloat(CGFloat value) {
    const float narrowed = static_cast<float>(value);
    u32 bits;
    memcpy(&bits, &narrowed, sizeof(bits));
    return bits;
}

bool GuestRangeIsValid(u32 address, size_t byteCount) {
    return address && static_cast<uint64_t>(address) + byteCount <=
        static_cast<uint64_t>(UINT32_MAX) + 1;
}

template<typename T>
bool WriteGuestValue(u32 address, const T &value) {
    return GuestRangeIsValid(address, sizeof(value)) &&
        Dynarmic_mem_1write(address, sizeof(value),
            const_cast<char *>(reinterpret_cast<const char *>(&value))) == 0;
}

bool NarrowCFIndex(CFIndex value, uint32_t &result) {
    if(value < std::numeric_limits<int32_t>::min() ||
       value > std::numeric_limits<int32_t>::max()) return false;
    result = static_cast<uint32_t>(static_cast<int32_t>(value));
    return true;
}

bool WriteRange(u32 guestAddress, CFRange range) {
    LC32CoreTextPair32 response = {};
    if(!NarrowCFIndex(range.location, response.first) ||
       !NarrowCFIndex(range.length, response.second)) return false;
    return WriteGuestValue(guestAddress, response);
}

bool WriteSize(u32 guestAddress, CGSize size) {
    const LC32CoreTextPair32 response = {
        ReturnCGFloat(size.width), ReturnCGFloat(size.height),
    };
    return WriteGuestValue(guestAddress, response);
}

LC32CoreTextRect32 NarrowRect(CGRect rect) {
    return {ReturnCGFloat(rect.origin.x), ReturnCGFloat(rect.origin.y),
        ReturnCGFloat(rect.size.width), ReturnCGFloat(rect.size.height)};
}

template<typename T>
bool ReadGlyphArray(u32 address, CFIndex count, std::vector<T> &values) {
    if(count < 0 || count > LC32CoreTextMaximumGlyphs ||
       !GuestRangeIsValid(address, static_cast<size_t>(count) * sizeof(T)))
        return false;
    values.resize(static_cast<size_t>(count));
    return !count || Dynarmic_mem_1read(address, values.size() * sizeof(T),
        reinterpret_cast<char *>(values.data())) == 0;
}

template<typename T>
bool WriteGlyphArray(u32 address, const std::vector<T> &values) {
    const size_t bytes = values.size() * sizeof(T);
    return GuestRangeIsValid(address, bytes) && (!bytes ||
        Dynarmic_mem_1write(address, bytes,
            const_cast<char *>(reinterpret_cast<const char *>(values.data()))) == 0);
}

bool WriteTypographicBounds(u32 guestAddress, double value, CGFloat ascent,
                            CGFloat descent, CGFloat leading) {
    uint64_t valueBits;
    memcpy(&valueBits, &value, sizeof(valueBits));
    const LC32CoreTextTypographicBounds32 response = {
        static_cast<uint32_t>(valueBits),
        static_cast<uint32_t>(valueBits >> 32),
        ReturnCGFloat(ascent), ReturnCGFloat(descent), ReturnCGFloat(leading),
    };
    return WriteGuestValue(guestAddress, response);
}

u32 GuestBorrowedObject(CFTypeRef object) {
    return object ? [(id)object guest_self] : 0;
}

struct NativeParagraphValue {
    uint8_t byteValue = 0;
    CGFloat floatValue = 0;
    CFArrayRef objectValue = nullptr;
    CTLineBoundsOptions optionsValue = 0;
};

bool BuildParagraphSetting(const LC32CoreTextParagraphSetting &source,
                           NativeParagraphValue &storage,
                           CTParagraphStyleSetting &destination) {
    destination.spec =
        static_cast<CTParagraphStyleSpecifier>(source.specifier);
    switch(destination.spec) {
        case kCTParagraphStyleSpecifierAlignment:
        case kCTParagraphStyleSpecifierLineBreakMode:
        case kCTParagraphStyleSpecifierBaseWritingDirection:
            if(source.kind != LC32CoreTextParagraphValueByte) return false;
            storage.byteValue = static_cast<uint8_t>(source.value);
            destination.valueSize = sizeof(storage.byteValue);
            destination.value = &storage.byteValue;
            return true;

        case kCTParagraphStyleSpecifierFirstLineHeadIndent:
        case kCTParagraphStyleSpecifierHeadIndent:
        case kCTParagraphStyleSpecifierTailIndent:
        case kCTParagraphStyleSpecifierDefaultTabInterval:
        case kCTParagraphStyleSpecifierLineHeightMultiple:
        case kCTParagraphStyleSpecifierMaximumLineHeight:
        case kCTParagraphStyleSpecifierMinimumLineHeight:
        case kCTParagraphStyleSpecifierLineSpacing:
        case kCTParagraphStyleSpecifierParagraphSpacing:
        case kCTParagraphStyleSpecifierParagraphSpacingBefore:
        case kCTParagraphStyleSpecifierMaximumLineSpacing:
        case kCTParagraphStyleSpecifierMinimumLineSpacing:
        case kCTParagraphStyleSpecifierLineSpacingAdjustment: {
            if(source.kind != LC32CoreTextParagraphValueFloat) return false;
            const uint32_t bits = static_cast<uint32_t>(source.value);
            float value;
            memcpy(&value, &bits, sizeof(value));
            storage.floatValue = value;
            destination.valueSize = sizeof(storage.floatValue);
            destination.value = &storage.floatValue;
            return true;
        }

        case kCTParagraphStyleSpecifierTabStops:
            if(source.kind != LC32CoreTextParagraphValueObject) return false;
            storage.objectValue = reinterpret_cast<CFArrayRef>(
                static_cast<uintptr_t>(source.value));
            destination.valueSize = sizeof(storage.objectValue);
            destination.value = &storage.objectValue;
            return true;

        case kCTParagraphStyleSpecifierLineBoundsOptions:
            if(source.kind != LC32CoreTextParagraphValueUInt32) return false;
            storage.optionsValue = static_cast<CTLineBoundsOptions>(
                static_cast<uint32_t>(source.value));
            destination.valueSize = sizeof(storage.optionsValue);
            destination.value = &storage.optionsValue;
            return true;

        default:
            return false;
    }
}

} // namespace

__BEGIN_DECLS

u32 LC32_CoreText_Dispatch(u32 opcode, u32 guestCall, u32) {
    LC32CoreTextCall call;
    if(!ReadCoreTextCall(guestCall, call)) return 0;

    switch(static_cast<LC32CoreTextOpcode>(opcode)) {
        case LC32CoreTextOpFontCreateWithName: {
            if(!RequireCoreTextSlots(call, 9)) return 0;
            CFStringRef name = SlotHostObject<CFStringRef>(call, 0);
            if(!name) return 0;
            CGAffineTransform transform;
            const CGAffineTransform *transformPointer = nullptr;
            if(SlotU32(call, 2)) {
                transform = CGAffineTransformMake(
                    SlotCGFloat(call, 3), SlotCGFloat(call, 4),
                    SlotCGFloat(call, 5), SlotCGFloat(call, 6),
                    SlotCGFloat(call, 7), SlotCGFloat(call, 8));
                transformPointer = &transform;
            }
            CTFontRef font = CTFontCreateWithName(
                name, SlotCGFloat(call, 1), transformPointer);
            return font ? LC32GuestObjectForOwnedHostObject(font) : 0;
        }

        case LC32CoreTextOpFontDescriptorCreateWithAttributes: {
            if(!RequireCoreTextSlots(call, 1)) return 0;
            CFDictionaryRef attributes =
                SlotHostObject<CFDictionaryRef>(call, 0);
            if(!attributes) return 0;
            CTFontDescriptorRef descriptor =
                CTFontDescriptorCreateWithAttributes(attributes);
            return descriptor
                ? LC32GuestObjectForOwnedHostObject(descriptor) : 0;
        }

        case LC32CoreTextOpFontCreateWithFontDescriptor: {
            if(!RequireCoreTextSlots(call, 9)) return 0;
            CTFontDescriptorRef descriptor =
                SlotHostObject<CTFontDescriptorRef>(call, 0);
            if(!descriptor) return 0;
            CGAffineTransform transform;
            const CGAffineTransform *transformPointer = nullptr;
            if(SlotU32(call, 2)) {
                transform = CGAffineTransformMake(
                    SlotCGFloat(call, 3), SlotCGFloat(call, 4),
                    SlotCGFloat(call, 5), SlotCGFloat(call, 6),
                    SlotCGFloat(call, 7), SlotCGFloat(call, 8));
                transformPointer = &transform;
            }
            CTFontRef font = CTFontCreateWithFontDescriptor(
                descriptor, SlotCGFloat(call, 1), transformPointer);
            return font ? LC32GuestObjectForOwnedHostObject(font) : 0;
        }

        case LC32CoreTextOpFontCreateUIFontForLanguage: {
            if(!RequireCoreTextSlots(call, 3)) return 0;
            CFStringRef language = SlotHostObject<CFStringRef>(call, 2);
            CTFontRef font = CTFontCreateUIFontForLanguage(
                static_cast<CTFontUIFontType>(SlotU32(call, 0)),
                SlotCGFloat(call, 1), language);
            return font ? LC32GuestObjectForOwnedHostObject(font) : 0;
        }

        case LC32CoreTextOpFontCreateWithGraphicsFont:
        case LC32CoreTextOpFontCreateCopyWithAttributes: {
            if(!RequireCoreTextSlots(call, 10)) return 0;
            CGFontRef graphicsFont = SlotHostObject<CGFontRef>(call, 0);
            if(!graphicsFont) return 0;
            CGAffineTransform transform;
            const CGAffineTransform *transformPointer = nullptr;
            if(SlotU32(call, 2)) {
                transform = CGAffineTransformMake(
                    SlotCGFloat(call, 3), SlotCGFloat(call, 4),
                    SlotCGFloat(call, 5), SlotCGFloat(call, 6),
                    SlotCGFloat(call, 7), SlotCGFloat(call, 8));
                transformPointer = &transform;
            }
            CTFontDescriptorRef attributes = SlotHostObject<CTFontDescriptorRef>(call, 9);
            CTFontRef font = opcode == LC32CoreTextOpFontCreateWithGraphicsFont
                ? CTFontCreateWithGraphicsFont(graphicsFont,
                    SlotCGFloat(call, 1), transformPointer, attributes)
                : CTFontCreateCopyWithAttributes((CTFontRef)graphicsFont,
                    SlotCGFloat(call, 1), transformPointer, attributes);
            return font ? LC32GuestObjectForOwnedHostObject(font) : 0;
        }

        case LC32CoreTextOpFontCopyGraphicsFont: {
            if(!RequireCoreTextSlots(call, 2)) return 0;
            CTFontRef font = SlotHostObject<CTFontRef>(call, 0);
            if(!font) return 0;
            const u32 guestAttributes = SlotU32(call, 1);
            CTFontDescriptorRef attributes = nullptr;
            CGFontRef graphicsFont = CTFontCopyGraphicsFont(font,
                guestAttributes ? &attributes : nullptr);
            // Transfer the optional +1 separately; the guest narrows the pointer
            // only after converting the native descriptor to a guest proxy.
            const uint64_t hostAttributes = reinterpret_cast<uintptr_t>(attributes);
            if(guestAttributes && !WriteGuestValue(guestAttributes, hostAttributes)) {
                if(attributes) CFRelease(attributes);
                if(graphicsFont) CGFontRelease(graphicsFont);
                return 0;
            }
            return graphicsFont ? LC32GuestObjectForOwnedHostObject(graphicsFont) : 0;
        }

        case LC32CoreTextOpFontGetAscent:
        case LC32CoreTextOpFontGetDescent:
        case LC32CoreTextOpFontGetLeading:
        case LC32CoreTextOpFontGetSize:
        case LC32CoreTextOpFontGetSlantAngle:
        case LC32CoreTextOpFontGetUnderlineThickness:
        case LC32CoreTextOpFontGetSymbolicTraits:
        case LC32CoreTextOpFontGetGlyphCount: {
            if(!RequireCoreTextSlots(call, 1)) return 0;
            CTFontRef font = SlotHostObject<CTFontRef>(call, 0);
            if(!font) return 0;
            switch(opcode) {
                case LC32CoreTextOpFontGetAscent: return ReturnCGFloat(CTFontGetAscent(font));
                case LC32CoreTextOpFontGetDescent: return ReturnCGFloat(CTFontGetDescent(font));
                case LC32CoreTextOpFontGetLeading: return ReturnCGFloat(CTFontGetLeading(font));
                case LC32CoreTextOpFontGetSize: return ReturnCGFloat(CTFontGetSize(font));
                case LC32CoreTextOpFontGetSlantAngle: return ReturnCGFloat(CTFontGetSlantAngle(font));
                case LC32CoreTextOpFontGetUnderlineThickness: return ReturnCGFloat(CTFontGetUnderlineThickness(font));
                case LC32CoreTextOpFontGetSymbolicTraits: return CTFontGetSymbolicTraits(font);
                default: return static_cast<u32>(CTFontGetGlyphCount(font));
            }
        }

        case LC32CoreTextOpFontGetGlyphsForCharacters: {
            if(!RequireCoreTextSlots(call, 4)) return 0;
            CTFontRef font = SlotHostObject<CTFontRef>(call, 0);
            const CFIndex count = SlotIndex(call, 3);
            std::vector<UniChar> characters;
            if(!font || !ReadGlyphArray(SlotU32(call, 1), count, characters)) return 0;
            std::vector<CGGlyph> glyphs(characters.size());
            const bool result = CTFontGetGlyphsForCharacters(font,
                characters.data(), glyphs.data(), count);
            // Even a missing character has an observable zero glyph output.
            return WriteGlyphArray(SlotU32(call, 2), glyphs) && result;
        }

        case LC32CoreTextOpFontGetAdvancesForGlyphs:
        case LC32CoreTextOpFontGetBoundingRectsForGlyphs: {
            if(!RequireCoreTextSlots(call, 6)) return 0;
            CTFontRef font = SlotHostObject<CTFontRef>(call, 0);
            const CFIndex count = SlotIndex(call, 4);
            const auto orientation = static_cast<CTFontOrientation>(SlotU32(call, 1));
            const u32 guestValues = SlotU32(call, 3);
            std::vector<CGGlyph> glyphs;
            if(!font || !ReadGlyphArray(SlotU32(call, 2), count, glyphs)) return 0;
            if(opcode == LC32CoreTextOpFontGetAdvancesForGlyphs) {
                std::vector<CGSize> advances(guestValues ? glyphs.size() : 0);
                const double total = CTFontGetAdvancesForGlyphs(font, orientation,
                    glyphs.data(), guestValues ? advances.data() : nullptr, count);
                if(guestValues) {
                    std::vector<LC32CoreTextPair32> narrowed(advances.size());
                    for(size_t i = 0; i < advances.size(); ++i)
                        narrowed[i] = {ReturnCGFloat(advances[i].width),
                            ReturnCGFloat(advances[i].height)};
                    if(!WriteGlyphArray(guestValues, narrowed)) return 0;
                }
                return WriteGuestValue(SlotU32(call, 5), total);
            }
            std::vector<CGRect> bounds(guestValues ? glyphs.size() : 0);
            const CGRect total = CTFontGetBoundingRectsForGlyphs(font, orientation,
                glyphs.data(), guestValues ? bounds.data() : nullptr, count);
            if(guestValues) {
                std::vector<LC32CoreTextRect32> narrowed(bounds.size());
                for(size_t i = 0; i < bounds.size(); ++i) narrowed[i] = NarrowRect(bounds[i]);
                if(!WriteGlyphArray(guestValues, narrowed)) return 0;
            }
            return WriteGuestValue(SlotU32(call, 5), NarrowRect(total));
        }

        case LC32CoreTextOpFontCopyFamilyName:
        case LC32CoreTextOpFontCopyFontDescriptor: {
            if(!RequireCoreTextSlots(call, 1)) return 0;
            CTFontRef font = SlotHostObject<CTFontRef>(call, 0);
            if(!font) return 0;
            CFTypeRef result = opcode == LC32CoreTextOpFontCopyFamilyName
                ? (CFTypeRef)CTFontCopyFamilyName(font)
                : (CFTypeRef)CTFontCopyFontDescriptor(font);
            return result ? LC32GuestObjectForOwnedHostObject(result) : 0;
        }
        case LC32CoreTextOpFontDrawGlyphs: {
            if(!RequireCoreTextSlots(call, 5)) return 0;
            CTFontRef font = SlotHostObject<CTFontRef>(call, 0);
            CGContextRef context = SlotHostObject<CGContextRef>(call, 4);
            std::vector<CGGlyph> glyphs;
            std::vector<LC32CoreTextPair32> pairs;
            const CFIndex count = SlotIndex(call, 3);
            if(!font || !context || !ReadGlyphArray(SlotU32(call, 1), count, glyphs) ||
               !ReadGlyphArray(SlotU32(call, 2), count, pairs)) return 0;
            std::vector<CGPoint> positions(pairs.size());
            for(size_t i = 0; i < pairs.size(); ++i) {
                float x, y;
                memcpy(&x, &pairs[i].first, sizeof(x));
                memcpy(&y, &pairs[i].second, sizeof(y));
                positions[i] = CGPointMake(x, y);
            }
            CTFontDrawGlyphs(font, glyphs.data(), positions.data(), glyphs.size(), context);
            LC32CoreGraphicsSyncBitmapBacking(context);
            return 1;
        }
        case LC32CoreTextOpTypesetterSuggestLineBreak: {
            if(!RequireCoreTextSlots(call, 3)) return 0;
            CTTypesetterRef typesetter = SlotHostObject<CTTypesetterRef>(call, 0);
            return typesetter ? static_cast<u32>(CTTypesetterSuggestLineBreak(
                typesetter, SlotIndex(call, 1), SlotDouble(call, 2))) : 0;
        }
        case LC32CoreTextOpLineGetPenOffsetForFlush: {
            if(!RequireCoreTextSlots(call, 4)) return 0;
            CTLineRef line = SlotHostObject<CTLineRef>(call, 0);
            return line && WriteGuestValue(SlotU32(call, 3),
                CTLineGetPenOffsetForFlush(line, SlotCGFloat(call, 1), SlotDouble(call, 2)));
        }
        case LC32CoreTextOpRunGetGlyphs:
        case LC32CoreTextOpRunGetPositions:
        case LC32CoreTextOpRunGetAdvances:
        case LC32CoreTextOpRunGetStringIndices: {
            if(!RequireCoreTextSlots(call, 4)) return 0;
            CTRunRef run = SlotHostObject<CTRunRef>(call, 0);
            CFRange range = CFRangeMake(SlotIndex(call, 1), SlotIndex(call, 2));
            if(!run || range.location < 0 || range.length < 0) return 0;
            const CFIndex total = CTRunGetGlyphCount(run);
            if(range.location > total) return 0;
            if(!range.length) range.length = total - range.location;
            if(range.length > total - range.location ||
               range.length > LC32CoreTextMaximumGlyphs) return 0;
            const size_t count = static_cast<size_t>(range.length);
            if(!count) return 1;
            const u32 output = SlotU32(call, 3);
            if(opcode == LC32CoreTextOpRunGetGlyphs) {
                std::vector<CGGlyph> values(count);
                CTRunGetGlyphs(run, range, values.data());
                return WriteGlyphArray(output, values);
            }
            if(opcode == LC32CoreTextOpRunGetStringIndices) {
                std::vector<CFIndex> values(count);
                CTRunGetStringIndices(run, range, values.data());
                std::vector<int32_t> narrowed(values.begin(), values.end());
                return WriteGlyphArray(output, narrowed);
            }
            std::vector<LC32CoreTextPair32> narrowed(count);
            if(opcode == LC32CoreTextOpRunGetPositions) {
                std::vector<CGPoint> values(count);
                CTRunGetPositions(run, range, values.data());
                for(size_t i = 0; i < count; ++i)
                    narrowed[i] = {ReturnCGFloat(values[i].x), ReturnCGFloat(values[i].y)};
            } else {
                std::vector<CGSize> values(count);
                CTRunGetAdvances(run, range, values.data());
                for(size_t i = 0; i < count; ++i)
                    narrowed[i] = {ReturnCGFloat(values[i].width), ReturnCGFloat(values[i].height)};
            }
            return WriteGlyphArray(output, narrowed);
        }

        case LC32CoreTextOpTypesetterCreateWithAttributedString: {
            if(!RequireCoreTextSlots(call, 1)) return 0;
            CFAttributedStringRef string = SlotHostObject<CFAttributedStringRef>(call, 0);
            CTTypesetterRef typesetter = string ? CTTypesetterCreateWithAttributedString(string) : nullptr;
            return typesetter ? LC32GuestObjectForOwnedHostObject(typesetter) : 0;
        }

        case LC32CoreTextOpTypesetterCreateLine: {
            if(!RequireCoreTextSlots(call, 3)) return 0;
            CTTypesetterRef typesetter = SlotHostObject<CTTypesetterRef>(call, 0);
            CTLineRef line = typesetter ? CTTypesetterCreateLine(typesetter,
                CFRangeMake(SlotIndex(call, 1), SlotIndex(call, 2))) : nullptr;
            return line ? LC32GuestObjectForOwnedHostObject(line) : 0;
        }

        case LC32CoreTextOpLineGetGlyphCount: {
            if(!RequireCoreTextSlots(call, 1)) return 0;
            CTLineRef line = SlotHostObject<CTLineRef>(call, 0);
            return line ? static_cast<u32>(CTLineGetGlyphCount(line)) : 0;
        }

        case LC32CoreTextOpLineGetImageBounds: {
            if(!RequireCoreTextSlots(call, 3)) return 0;
            CTLineRef line = SlotHostObject<CTLineRef>(call, 0);
            return line && WriteGuestValue(SlotU32(call, 2), NarrowRect(
                CTLineGetImageBounds(line, SlotHostObject<CGContextRef>(call, 1))));
        }

        case LC32CoreTextOpRunGetGlyphCount: {
            if(!RequireCoreTextSlots(call, 1)) return 0;
            CTRunRef run = SlotHostObject<CTRunRef>(call, 0);
            return run ? static_cast<u32>(CTRunGetGlyphCount(run)) : 0;
        }

        case LC32CoreTextOpRunCopyGlyphs: {
            if(!RequireCoreTextSlots(call, 3)) return 0;
            CTRunRef run = SlotHostObject<CTRunRef>(call, 0);
            const CFIndex count = SlotIndex(call, 2);
            if(!run || count <= 0 || count > LC32CoreTextMaximumGlyphs ||
               count != CTRunGetGlyphCount(run)) return 0;
            std::vector<CGGlyph> glyphs(static_cast<size_t>(count));
            CTRunGetGlyphs(run, CFRangeMake(0, count), glyphs.data());
            return WriteGlyphArray(SlotU32(call, 1), glyphs);
        }

        case LC32CoreTextOpFrameDraw: {
            if(!RequireCoreTextSlots(call, 2)) return 0;
            CTFrameRef frame = SlotHostObject<CTFrameRef>(call, 0);
            CGContextRef context = SlotHostObject<CGContextRef>(call, 1);
            if(!frame || !context) return 0;
            CTFrameDraw(frame, context);
            LC32CoreGraphicsSyncBitmapBacking(context);
            return 1;
        }

        case LC32CoreTextOpFrameGetLineOrigins: {
            if(!RequireCoreTextSlots(call, 4)) return 0;
            CTFrameRef frame = SlotHostObject<CTFrameRef>(call, 0);
            const CFRange range = CFRangeMake(
                SlotIndex(call, 1), SlotIndex(call, 2));
            const u32 guestOrigins = SlotU32(call, 3);
            if(!frame || range.location < 0 || range.length < 0 ||
               !guestOrigins) return 0;

            CFArrayRef lines = CTFrameGetLines(frame);
            const CFIndex lineCount = lines ? CFArrayGetCount(lines) : 0;
            if(range.location > lineCount) return 0;
            const CFIndex available = lineCount - range.location;
            const CFIndex originCount = range.length == 0
                ? available : std::min(range.length, available);
            if(originCount < 0 || static_cast<uint64_t>(originCount) >
                    SIZE_MAX / sizeof(LC32CoreTextPair32)) return 0;
            const size_t guestByteCount = static_cast<size_t>(originCount) *
                sizeof(LC32CoreTextPair32);
            if(originCount && !GuestRangeIsValid(
                    guestOrigins, guestByteCount)) return 0;

            std::vector<CGPoint> nativeOrigins(
                static_cast<size_t>(originCount));
            if(originCount) CTFrameGetLineOrigins(
                frame, CFRangeMake(range.location, originCount),
                nativeOrigins.data());
            std::vector<LC32CoreTextPair32> guestValues(
                static_cast<size_t>(originCount));
            for(CFIndex index = 0; index < originCount; index++) {
                guestValues[static_cast<size_t>(index)] = {
                    ReturnCGFloat(nativeOrigins[static_cast<size_t>(index)].x),
                    ReturnCGFloat(nativeOrigins[static_cast<size_t>(index)].y),
                };
            }
            return !guestByteCount || Dynarmic_mem_1write(
                guestOrigins, guestByteCount,
                reinterpret_cast<char *>(guestValues.data())) == 0;
        }

        case LC32CoreTextOpFrameGetLines: {
            if(!RequireCoreTextSlots(call, 1)) return 0;
            CTFrameRef frame = SlotHostObject<CTFrameRef>(call, 0);
            return frame ? GuestBorrowedObject(CTFrameGetLines(frame)) : 0;
        }

        case LC32CoreTextOpFrameGetPath: {
            if(!RequireCoreTextSlots(call, 1)) return 0;
            CTFrameRef frame = SlotHostObject<CTFrameRef>(call, 0);
            return frame ? GuestBorrowedObject(CTFrameGetPath(frame)) : 0;
        }

        case LC32CoreTextOpFramesetterCreateFrame: {
            if(!RequireCoreTextSlots(call, 5)) return 0;
            CTFramesetterRef framesetter =
                SlotHostObject<CTFramesetterRef>(call, 0);
            CGPathRef path = SlotHostObject<CGPathRef>(call, 3);
            if(!framesetter || !path) return 0;
            CTFrameRef frame = CTFramesetterCreateFrame(framesetter,
                CFRangeMake(SlotIndex(call, 1), SlotIndex(call, 2)), path,
                SlotHostObject<CFDictionaryRef>(call, 4));
            return frame ? LC32GuestObjectForOwnedHostObject(frame) : 0;
        }

        case LC32CoreTextOpFramesetterCreateWithAttributedString: {
            if(!RequireCoreTextSlots(call, 1)) return 0;
            CFAttributedStringRef string =
                SlotHostObject<CFAttributedStringRef>(call, 0);
            if(!string) return 0;
            CTFramesetterRef framesetter =
                CTFramesetterCreateWithAttributedString(string);
            return framesetter
                ? LC32GuestObjectForOwnedHostObject(framesetter) : 0;
        }

        case LC32CoreTextOpFramesetterSuggestFrameSizeWithConstraints: {
            if(!RequireCoreTextSlots(call, 9)) return 0;
            CTFramesetterRef framesetter =
                SlotHostObject<CTFramesetterRef>(call, 0);
            if(!framesetter) return 0;
            CFRange fitRange = CFRangeMake(0, 0);
            const bool wantsFitRange = SlotU32(call, 7) != 0;
            const CGSize result = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRangeMake(SlotIndex(call, 1), SlotIndex(call, 2)),
                SlotHostObject<CFDictionaryRef>(call, 3),
                CGSizeMake(SlotCGFloat(call, 4), SlotCGFloat(call, 5)),
                wantsFitRange ? &fitRange : nullptr);
            if(!WriteSize(SlotU32(call, 6), result)) return 0;
            if(wantsFitRange && !WriteRange(SlotU32(call, 8), fitRange))
                return 0;
            return 1;
        }

        case LC32CoreTextOpLineCreateTruncatedLine: {
            if(!RequireCoreTextSlots(call, 4)) return 0;
            CTLineRef line = SlotHostObject<CTLineRef>(call, 0);
            if(!line) return 0;
            CTLineRef result = CTLineCreateTruncatedLine(line,
                SlotDouble(call, 1),
                static_cast<CTLineTruncationType>(SlotU32(call, 2)),
                SlotHostObject<CTLineRef>(call, 3));
            return result ? LC32GuestObjectForOwnedHostObject(result) : 0;
        }

        case LC32CoreTextOpLineCreateWithAttributedString: {
            if(!RequireCoreTextSlots(call, 1)) return 0;
            CFAttributedStringRef string =
                SlotHostObject<CFAttributedStringRef>(call, 0);
            if(!string) return 0;
            CTLineRef line = CTLineCreateWithAttributedString(string);
            return line ? LC32GuestObjectForOwnedHostObject(line) : 0;
        }

        case LC32CoreTextOpLineDraw: {
            if(!RequireCoreTextSlots(call, 2)) return 0;
            CTLineRef line = SlotHostObject<CTLineRef>(call, 0);
            CGContextRef context = SlotHostObject<CGContextRef>(call, 1);
            if(!line || !context) return 0;
            CTLineDraw(line, context);
            LC32CoreGraphicsSyncBitmapBacking(context);
            return 1;
        }

        case LC32CoreTextOpLineGetGlyphRuns: {
            if(!RequireCoreTextSlots(call, 1)) return 0;
            CTLineRef line = SlotHostObject<CTLineRef>(call, 0);
            return line ? GuestBorrowedObject(CTLineGetGlyphRuns(line)) : 0;
        }

        case LC32CoreTextOpLineGetOffsetForStringIndex: {
            if(!RequireCoreTextSlots(call, 4)) return 0;
            CTLineRef line = SlotHostObject<CTLineRef>(call, 0);
            if(!line) return 0;
            CGFloat secondaryOffset = 0;
            const bool wantsSecondaryOffset = SlotU32(call, 2) != 0;
            const CGFloat result = CTLineGetOffsetForStringIndex(line,
                SlotIndex(call, 1),
                wantsSecondaryOffset ? &secondaryOffset : nullptr);
            if(wantsSecondaryOffset) {
                const uint32_t bits = ReturnCGFloat(secondaryOffset);
                if(!WriteGuestValue(SlotU32(call, 3), bits)) return 0;
            }
            return ReturnCGFloat(result);
        }

        case LC32CoreTextOpLineGetStringIndexForPosition: {
            if(!RequireCoreTextSlots(call, 3)) return 0;
            CTLineRef line = SlotHostObject<CTLineRef>(call, 0);
            if(!line) return static_cast<u32>(-1);
            const CFIndex index = CTLineGetStringIndexForPosition(line,
                CGPointMake(SlotCGFloat(call, 1), SlotCGFloat(call, 2)));
            uint32_t narrowed;
            return NarrowCFIndex(index, narrowed)
                ? narrowed : static_cast<u32>(-1);
        }

        case LC32CoreTextOpLineGetStringRange: {
            if(!RequireCoreTextSlots(call, 2)) return 0;
            CTLineRef line = SlotHostObject<CTLineRef>(call, 0);
            return line && WriteRange(
                SlotU32(call, 1), CTLineGetStringRange(line));
        }

        case LC32CoreTextOpLineGetTypographicBounds: {
            if(!RequireCoreTextSlots(call, 2)) return 0;
            CTLineRef line = SlotHostObject<CTLineRef>(call, 0);
            if(!line) return 0;
            CGFloat ascent = 0, descent = 0, leading = 0;
            const double width = CTLineGetTypographicBounds(
                line, &ascent, &descent, &leading);
            return WriteTypographicBounds(
                SlotU32(call, 1), width, ascent, descent, leading);
        }

        case LC32CoreTextOpParagraphStyleCreate: {
            if(!RequireCoreTextSlots(call, 2)) return 0;
            const u32 guestSettings = SlotU32(call, 0);
            const size_t count = SlotU32(call, 1);
            if(count > LC32CoreTextMaximumParagraphSettings ||
               (count && !guestSettings)) return 0;
            if(count > SIZE_MAX / sizeof(LC32CoreTextParagraphSetting))
                return 0;

            std::vector<LC32CoreTextParagraphSetting> source(count);
            const size_t byteCount = count * sizeof(source[0]);
            if(byteCount && (!GuestRangeIsValid(guestSettings, byteCount) ||
                    Dynarmic_mem_1read(guestSettings, byteCount,
                        reinterpret_cast<char *>(source.data())) != 0)) {
                return 0;
            }
            std::vector<NativeParagraphValue> values(count);
            std::vector<CTParagraphStyleSetting> settings(count);
            for(size_t index = 0; index < count; index++) {
                if(!BuildParagraphSetting(
                        source[index], values[index], settings[index])) {
                    return 0;
                }
            }
            CTParagraphStyleRef style = CTParagraphStyleCreate(
                settings.empty() ? nullptr : settings.data(), count);
            return style ? LC32GuestObjectForOwnedHostObject(style) : 0;
        }

        case LC32CoreTextOpRunGetAttributes: {
            if(!RequireCoreTextSlots(call, 1)) return 0;
            CTRunRef run = SlotHostObject<CTRunRef>(call, 0);
            return run ? GuestBorrowedObject(CTRunGetAttributes(run)) : 0;
        }

        case LC32CoreTextOpRunCopyPositions: {
            if(!RequireCoreTextSlots(call, 3)) return 0;
            CTRunRef run = SlotHostObject<CTRunRef>(call, 0);
            if(!run) return 0;
            const CFIndex count = CTRunGetGlyphCount(run);
            if(count <= 0 || static_cast<uint64_t>(count) >
                    UINT32_MAX / sizeof(LC32CoreTextPair32)) return 0;

            const u32 guestPositions = SlotU32(call, 1);
            const u32 requestedCount = SlotU32(call, 2);
            if(!guestPositions && !requestedCount)
                return static_cast<u32>(count);
            if(!guestPositions || requestedCount != static_cast<u32>(count))
                return 0;

            const size_t positionCount = static_cast<size_t>(count);
            std::vector<CGPoint> nativePositions(positionCount);
            CTRunGetPositions(run, CFRangeMake(0, count),
                              nativePositions.data());
            std::vector<LC32CoreTextPair32> guestValues(positionCount);
            for(size_t index = 0; index < positionCount; index++) {
                guestValues[index] = {
                    ReturnCGFloat(nativePositions[index].x),
                    ReturnCGFloat(nativePositions[index].y),
                };
            }
            const size_t byteCount = positionCount * sizeof(guestValues[0]);
            if(!GuestRangeIsValid(guestPositions, byteCount)) return 0;
            return Dynarmic_mem_1write(guestPositions, byteCount,
                reinterpret_cast<char *>(guestValues.data())) == 0;
        }

        case LC32CoreTextOpRunGetStatus: {
            if(!RequireCoreTextSlots(call, 1)) return 0;
            CTRunRef run = SlotHostObject<CTRunRef>(call, 0);
            return run ? static_cast<u32>(CTRunGetStatus(run)) : 0;
        }

        case LC32CoreTextOpRunGetStringRange: {
            if(!RequireCoreTextSlots(call, 2)) return 0;
            CTRunRef run = SlotHostObject<CTRunRef>(call, 0);
            return run && WriteRange(
                SlotU32(call, 1), CTRunGetStringRange(run));
        }

        case LC32CoreTextOpRunGetTypographicBounds: {
            if(!RequireCoreTextSlots(call, 4)) return 0;
            CTRunRef run = SlotHostObject<CTRunRef>(call, 0);
            if(!run) return 0;
            CGFloat ascent = 0, descent = 0, leading = 0;
            const double width = CTRunGetTypographicBounds(run,
                CFRangeMake(SlotIndex(call, 1), SlotIndex(call, 2)),
                &ascent, &descent, &leading);
            return WriteTypographicBounds(
                SlotU32(call, 3), width, ascent, descent, leading);
        }
    }
    return 0;
}

__END_DECLS

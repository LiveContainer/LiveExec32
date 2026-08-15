@import Foundation;

#import "../../bridge.h"
#import "../../GuestFrameworks/Foundation/LC32FoundationBridge.h"

#include <atomic>
#include <ctype.h>
#include <limits>
#include <memory>
#include <optional>
#include <string.h>
#include <vector>

namespace {

constexpr size_t kMaximumFormatArguments = 64;
constexpr size_t kMaximumGuestStringUnits = 1024 * 1024;
constexpr size_t kMaximumGuestStringBytes = 64 * 1024 * 1024;

static_assert(sizeof(LC32FoundationStringGetBytesRequest) == 48);

bool guestStringByteRangeIsValid(u32 address, size_t byteCount) {
    return !byteCount || (address &&
        static_cast<uint64_t>(address) + byteCount <=
            static_cast<uint64_t>(UINT32_MAX) + 1);
}

bool writeGuestStringBytes(u32 address, const void *bytes,
                           size_t byteCount) {
    return guestStringByteRangeIsValid(address, byteCount) &&
        (!byteCount || Dynarmic_mem_1write(
            address, byteCount,
            const_cast<char *>(reinterpret_cast<const char *>(bytes))) == 0);
}

enum : u32 {
    LC32FormatHasLocale = 1 << 0,
    LC32FormatTakesArgumentsList = 1 << 1,
    LC32FormatReturnGuestObject = 1 << 2,
};

enum class FormatArgumentKind {
    Unknown,
    Word,
    SignedGuestWordAsHostLong,
    UnsignedGuestWordAsHostLong,
    DoubleWord,
    Floating,
    Object,
    CString,
    UTF16String,
    PascalString,
    Pointer,
};

enum class FormatLength {
    None,
    Char,
    Short,
    Long,
    LongLong,
    IntMax,
    Size,
    PtrDiff,
    LongDouble,
};

class GuestVaListReader {
public:
    explicit GuestVaListReader(u32 address) : address(address) {}

    bool readWord(u32 &value) {
        if(address > std::numeric_limits<u32>::max() - sizeof(value) ||
           Dynarmic_mem_1read(address, sizeof(value),
                              reinterpret_cast<char *>(&value))) {
            return false;
        }
        address += sizeof(value);
        return true;
    }

    bool readDoubleWord(u64 &value) {
        // Darwin ARMv7 deliberately does not realign va_list for 64-bit
        // values. A value may start in the saved r3 word and continue at the
        // caller's stack pointer.
        if(address > std::numeric_limits<u32>::max() - sizeof(value) ||
           Dynarmic_mem_1read(address, sizeof(value),
                              reinterpret_cast<char *>(&value))) {
            return false;
        }
        address += sizeof(value);
        return true;
    }

private:
    u32 address;
};

struct ParsedFormat {
    std::vector<FormatArgumentKind> arguments;
    bool sawPositional = false;
    bool sawSequential = false;
    size_t nextSequential = 0;
};

bool parseUnsigned(const char *&cursor, const char *end, size_t &value) {
    const char *start = cursor;
    value = 0;
    while(cursor < end && isdigit(static_cast<unsigned char>(*cursor))) {
        unsigned digit = static_cast<unsigned>(*cursor - '0');
        if(value > (std::numeric_limits<size_t>::max() - digit) / 10) {
            return false;
        }
        value = value * 10 + digit;
        cursor++;
    }
    return cursor != start;
}

bool parsePosition(const char *&cursor,
                   const char *end,
                   std::optional<size_t> &position) {
    const char *start = cursor;
    size_t oneBased = 0;
    if(!parseUnsigned(cursor, end, oneBased) ||
       cursor == end || *cursor != '$') {
        cursor = start;
        position.reset();
        return true;
    }
    if(oneBased == 0 || oneBased > kMaximumFormatArguments) return false;
    cursor++;
    position = oneBased - 1;
    return true;
}

bool isFormatFlag(char character) {
    switch(character) {
        case '-':
        case '+':
        case ' ':
        case '#':
        case '0':
        case '\'':
            return true;
        default:
            return false;
    }
}

bool recordArgument(ParsedFormat &parsed,
                    std::optional<size_t> position,
                    FormatArgumentKind kind) {
    size_t index;
    if(position) {
        if(parsed.sawSequential) return false;
        parsed.sawPositional = true;
        index = *position;
    } else {
        if(parsed.sawPositional) return false;
        parsed.sawSequential = true;
        index = parsed.nextSequential++;
    }

    if(index >= kMaximumFormatArguments) return false;
    if(parsed.arguments.size() <= index) {
        parsed.arguments.resize(index + 1, FormatArgumentKind::Unknown);
    }

    FormatArgumentKind &existing = parsed.arguments[index];
    if(existing != FormatArgumentKind::Unknown && existing != kind) {
        return false;
    }
    existing = kind;
    return true;
}

FormatArgumentKind integerKind(char conversion, FormatLength length) {
    bool isSigned = conversion == 'd' || conversion == 'i' || conversion == 'D';
    if(length == FormatLength::LongLong ||
       length == FormatLength::IntMax) {
        return FormatArgumentKind::DoubleWord;
    }

    // D/U/O imply long even without an explicit length modifier.
    bool hostLong = conversion == 'D' || conversion == 'U' ||
                    conversion == 'O' || length == FormatLength::Long ||
                    length == FormatLength::Size ||
                    length == FormatLength::PtrDiff;
    if(hostLong) {
        return isSigned ? FormatArgumentKind::SignedGuestWordAsHostLong
                        : FormatArgumentKind::UnsignedGuestWordAsHostLong;
    }
    return FormatArgumentKind::Word;
}

std::optional<FormatArgumentKind>
kindForConversion(char conversion, FormatLength length) {
    switch(conversion) {
        case 'd':
        case 'i':
        case 'D':
        case 'u':
        case 'o':
        case 'x':
        case 'X':
        case 'U':
        case 'O':
            return integerKind(conversion, length);
        case 'c':
        case 'C':
            return FormatArgumentKind::Word;
        case 'a':
        case 'A':
        case 'e':
        case 'E':
        case 'f':
        case 'F':
        case 'g':
        case 'G':
            return FormatArgumentKind::Floating;
        case '@':
            return FormatArgumentKind::Object;
        case 'p':
            return FormatArgumentKind::Pointer;
        case 's':
            // CoreFoundation's formatter treats %ls as a byte C string too.
            return FormatArgumentKind::CString;
        case 'S':
            return FormatArgumentKind::UTF16String;
        case 'P':
            return FormatArgumentKind::PascalString;
        case 'n':
            // Modern CoreFoundation does not expose %n's writeback. Do not
            // hand it a translated guest pointer until that behavior is
            // explicitly implemented and tested.
            return std::nullopt;
        default:
            return std::nullopt;
    }
}

bool parseFormat(NSString *format, ParsedFormat &parsed) {
    NSData *encoded = [format dataUsingEncoding:NSUTF8StringEncoding
                           allowLossyConversion:NO];
    if(!encoded) return false;

    // UTF8String is NUL terminated and would silently hide format directives
    // after an embedded NUL. Keep the NSString's encoded length instead.
    const char *bytes = encoded.length
        ? static_cast<const char *>(encoded.bytes)
        : "";
    const char *end = bytes + encoded.length;

    for(const char *cursor = bytes; cursor < end;) {
        if(*cursor++ != '%') continue;
        if(cursor < end && *cursor == '%') {
            cursor++;
            continue;
        }

        std::optional<size_t> valuePosition;
        if(!parsePosition(cursor, end, valuePosition)) return false;

        bool sawAlternateForm = false;
        while(cursor < end && isFormatFlag(*cursor)) {
            sawAlternateForm |= *cursor == '#';
            cursor++;
        }

        // CoreFoundation's localized external and plural forms (%[key]@ and
        // %#@key@) interpret arguments using strings-dictionary metadata that
        // is not represented in the format itself. Guessing Object here can
        // message a scalar guest value, so reject these forms before reading
        // any argument.
        if(cursor < end &&
           (*cursor == '[' || (sawAlternateForm && *cursor == '@'))) {
            return false;
        }

        bool hasDynamicWidth = false;
        std::optional<size_t> widthPosition;
        if(cursor < end && *cursor == '*') {
            cursor++;
            hasDynamicWidth = true;
            if(!parsePosition(cursor, end, widthPosition)) return false;
        } else {
            size_t ignored;
            parseUnsigned(cursor, end, ignored);
        }

        bool hasPrecision = false;
        bool hasDynamicPrecision = false;
        std::optional<size_t> precisionPosition;
        if(cursor < end && *cursor == '.') {
            cursor++;
            hasPrecision = true;
            if(cursor < end && *cursor == '*') {
                cursor++;
                hasDynamicPrecision = true;
                if(!parsePosition(cursor, end, precisionPosition)) return false;
            } else {
                size_t ignored;
                parseUnsigned(cursor, end, ignored);
            }
        }

        FormatLength length = FormatLength::None;
        if(end - cursor >= 2 && cursor[0] == 'h' && cursor[1] == 'h') {
            length = FormatLength::Char;
            cursor += 2;
        } else if(end - cursor >= 2 &&
                  cursor[0] == 'l' && cursor[1] == 'l') {
            length = FormatLength::LongLong;
            cursor += 2;
        } else if(cursor < end) {
            switch(*cursor) {
                case 'h': length = FormatLength::Short; cursor++; break;
                case 'l': length = FormatLength::Long; cursor++; break;
                case 'q': length = FormatLength::LongLong; cursor++; break;
                case 'j': length = FormatLength::IntMax; cursor++; break;
                case 'z': length = FormatLength::Size; cursor++; break;
                case 't': length = FormatLength::PtrDiff; cursor++; break;
                case 'L': length = FormatLength::LongDouble; cursor++; break;
                default: break;
            }
        }

        if(cursor == end) return false;
        char conversion = *cursor++;

        // CFString treats these unsupported conversions as literal text and
        // does not consume even dynamic width/precision arguments.
        if(conversion == 'b' || conversion == 'B') continue;

        // A precision makes %s/%S bounded, while our guest pointer copier
        // currently scans for a terminator. Fail instead of reading beyond a
        // valid non-NUL-terminated guest buffer.
        if(hasPrecision && (conversion == 's' || conversion == 'S')) {
            return false;
        }

        std::optional<FormatArgumentKind> kind =
            kindForConversion(conversion, length);
        if(!kind) return false;

        // Width and precision precede the converted value in a sequential
        // varargs list. Defer recording them until the conversion is known so
        // literal %b/%B consumes nothing.
        if((hasDynamicWidth &&
            !recordArgument(parsed, widthPosition, FormatArgumentKind::Word)) ||
           (hasDynamicPrecision &&
            !recordArgument(parsed, precisionPosition,
                            FormatArgumentKind::Word)) ||
           !recordArgument(parsed, valuePosition, *kind)) {
            return false;
        }
    }

    for(FormatArgumentKind kind : parsed.arguments) {
        if(kind == FormatArgumentKind::Unknown) return false;
    }
    return true;
}

u64 hostObjectForGuestObject(u32 guestObject) {
    if(!guestObject) return 0;
    static std::atomic<u32> cachedGuestHostSelfSelector{0};
    u32 guestHostSelfSelector =
        cachedGuestHostSelfSelector.load(std::memory_order_acquire);
    if(!guestHostSelfSelector) {
        guestHostSelfSelector = guest_sel_registerName("host_self");
        cachedGuestHostSelfSelector.store(guestHostSelfSelector,
                                           std::memory_order_release);
    }
    u32 arguments[] = {guestObject, guestHostSelfSelector};
    return guest_objc_msgSend(sizeof(arguments) / sizeof(*arguments),
                              arguments);
}

template<typename Character>
bool copyGuestTerminatedString(u32 guestAddress,
                               std::vector<Character> &output) {
    if(!guestAddress) return true;
    output.reserve(64);
    for(size_t index = 0; index < kMaximumGuestStringUnits; index++) {
        Character value;
        u64 address = static_cast<u64>(guestAddress) +
                      index * sizeof(Character);
        if(address > std::numeric_limits<u32>::max() ||
           Dynarmic_mem_1read(address, sizeof(value),
                              reinterpret_cast<char *>(&value))) {
            return false;
        }
        output.push_back(value);
        if(value == 0) return true;
    }
    return false;
}

struct StableFormatPointers {
    std::vector<std::unique_ptr<std::vector<char>>> cStrings;
    std::vector<std::unique_ptr<std::vector<uint16_t>>> utf16Strings;
    std::vector<std::unique_ptr<std::vector<unsigned char>>> pascalStrings;
};

bool translateArguments(const ParsedFormat &parsed,
                        u32 guestArguments,
                        u64 *hostSlots,
                        StableFormatPointers &pointers) {
    GuestVaListReader reader(guestArguments);
    for(size_t index = 0; index < parsed.arguments.size(); index++) {
        u32 word = 0;
        u64 doubleWord = 0;
        switch(parsed.arguments[index]) {
            case FormatArgumentKind::Word:
                if(!reader.readWord(word)) return false;
                hostSlots[index] = word;
                break;
            case FormatArgumentKind::SignedGuestWordAsHostLong:
                if(!reader.readWord(word)) return false;
                hostSlots[index] = static_cast<u64>(
                    static_cast<int64_t>(static_cast<int32_t>(word)));
                break;
            case FormatArgumentKind::UnsignedGuestWordAsHostLong:
                if(!reader.readWord(word)) return false;
                hostSlots[index] = word;
                break;
            case FormatArgumentKind::DoubleWord:
            case FormatArgumentKind::Floating:
                if(!reader.readDoubleWord(doubleWord)) return false;
                hostSlots[index] = doubleWord;
                break;
            case FormatArgumentKind::Object:
                if(!reader.readWord(word)) return false;
                hostSlots[index] = hostObjectForGuestObject(word);
                break;
            case FormatArgumentKind::Pointer:
                if(!reader.readWord(word)) return false;
                hostSlots[index] = word;
                break;
            case FormatArgumentKind::CString: {
                if(!reader.readWord(word)) return false;
                if(!word) break;
                auto string = std::make_unique<std::vector<char>>();
                if(!copyGuestTerminatedString(word, *string)) return false;
                hostSlots[index] = reinterpret_cast<u64>(string->data());
                pointers.cStrings.push_back(std::move(string));
                break;
            }
            case FormatArgumentKind::UTF16String: {
                if(!reader.readWord(word)) return false;
                if(!word) break;
                auto string = std::make_unique<std::vector<uint16_t>>();
                if(!copyGuestTerminatedString(word, *string)) return false;
                hostSlots[index] = reinterpret_cast<u64>(string->data());
                pointers.utf16Strings.push_back(std::move(string));
                break;
            }
            case FormatArgumentKind::PascalString: {
                if(!reader.readWord(word)) return false;
                if(!word) break;
                unsigned char length = 0;
                if(Dynarmic_mem_1read(word, sizeof(length),
                                     reinterpret_cast<char *>(&length))) {
                    return false;
                }
                auto string =
                    std::make_unique<std::vector<unsigned char>>(length + 1);
                if(Dynarmic_mem_1read(word, string->size(),
                                     reinterpret_cast<char *>(string->data()))) {
                    return false;
                }
                hostSlots[index] = reinterpret_cast<u64>(string->data());
                pointers.pascalStrings.push_back(std::move(string));
                break;
            }
            case FormatArgumentKind::Unknown:
                return false;
        }
    }
    return true;
}

#define LC32_FORMAT_ARGUMENTS \
    hostSlots[0], hostSlots[1], hostSlots[2], hostSlots[3], \
    hostSlots[4], hostSlots[5], hostSlots[6], hostSlots[7], \
    hostSlots[8], hostSlots[9], hostSlots[10], hostSlots[11], \
    hostSlots[12], hostSlots[13], hostSlots[14], hostSlots[15], \
    hostSlots[16], hostSlots[17], hostSlots[18], hostSlots[19], \
    hostSlots[20], hostSlots[21], hostSlots[22], hostSlots[23], \
    hostSlots[24], hostSlots[25], hostSlots[26], hostSlots[27], \
    hostSlots[28], hostSlots[29], hostSlots[30], hostSlots[31], \
    hostSlots[32], hostSlots[33], hostSlots[34], hostSlots[35], \
    hostSlots[36], hostSlots[37], hostSlots[38], hostSlots[39], \
    hostSlots[40], hostSlots[41], hostSlots[42], hostSlots[43], \
    hostSlots[44], hostSlots[45], hostSlots[46], hostSlots[47], \
    hostSlots[48], hostSlots[49], hostSlots[50], hostSlots[51], \
    hostSlots[52], hostSlots[53], hostSlots[54], hostSlots[55], \
    hostSlots[56], hostSlots[57], hostSlots[58], hostSlots[59], \
    hostSlots[60], hostSlots[61], hostSlots[62], hostSlots[63]

u64 invokeHostFormat(u64 receiver,
                     u64 selector,
                     u64 format,
                     u64 locale,
                     u32 options,
                     u64 *hostSlots) {
    void *send = reinterpret_cast<void *>(objc_msgSend);
    u64 sendReceiver = receiver;
    struct objc_super superInfo = {};
    Class receiverClass = object_getClass((id)receiver);
    if([(id)receiverClass isGuestClass]) {
        bool receiverIsClass = class_isMetaClass(receiverClass);
        Class superclass = [(id)receiver superclass];
        while([(id)superclass isGuestClass]) {
            superclass = [superclass superclass];
        }
        // objc_msgSendSuper starts lookup at the supplied class. Class-method
        // implementations live on the superclass's metaclass.
        Class lookupClass = receiverIsClass
            ? object_getClass(superclass)
            : superclass;
        superInfo = {(id)receiver, lookupClass};
        send = reinterpret_cast<void *>(objc_msgSendSuper);
        sendReceiver = reinterpret_cast<u64>(&superInfo);
    }

    va_list hostArguments = reinterpret_cast<char *>(hostSlots);
    if(options & LC32FormatTakesArgumentsList) {
        if(options & LC32FormatHasLocale) {
            using SendArguments2 =
                u64 (*)(u64, u64, u64, u64, va_list);
            return reinterpret_cast<SendArguments2>(send)(
                sendReceiver, selector, format, locale, hostArguments);
        }
        using SendArguments1 = u64 (*)(u64, u64, u64, va_list);
        return reinterpret_cast<SendArguments1>(send)(
            sendReceiver, selector, format, hostArguments);
    }

    if(options & LC32FormatHasLocale) {
        using SendVariadic2 = u64 (*)(u64, u64, u64, u64, ...);
        return reinterpret_cast<SendVariadic2>(send)(
            sendReceiver, selector, format, locale, LC32_FORMAT_ARGUMENTS);
    }
    using SendVariadic1 = u64 (*)(u64, u64, u64, ...);
    return reinterpret_cast<SendVariadic1>(send)(
        sendReceiver, selector, format, LC32_FORMAT_ARGUMENTS);
}

#undef LC32_FORMAT_ARGUMENTS

} // namespace

extern "C" u32 LC32_Foundation_StringGetBytes(
        u32 guestRequestAddress, u32, u32) {
    LC32FoundationStringGetBytesRequest request = {};
    if(!guestStringByteRangeIsValid(
            guestRequestAddress, sizeof(request)) ||
       Dynarmic_mem_1read(guestRequestAddress, sizeof(request),
            reinterpret_cast<char *>(&request)) != 0 ||
       request.version != LC32FoundationStringGetBytesABIVersion ||
       request.byteSize != sizeof(request) ||
       request.maximumLength > kMaximumGuestStringBytes ||
       (request.guestBuffer && !guestStringByteRangeIsValid(
            request.guestBuffer, request.maximumLength)) ||
       (request.guestUsedLength && !guestStringByteRangeIsValid(
            request.guestUsedLength, sizeof(uint32_t))) ||
       (request.guestRemainingRange && !guestStringByteRangeIsValid(
            request.guestRemainingRange, sizeof(uint32_t) * 2)) ||
       static_cast<uint64_t>(request.rangeLocation) + request.rangeLength >
            static_cast<uint64_t>(UINT32_MAX)) {
        return NO;
    }

    const u64 hostStringAddress = request.hostStringLow |
        (static_cast<u64>(request.hostStringHigh) << 32);
    NSString *string = reinterpret_cast<NSString *>(hostStringAddress);
    if(!string || request.rangeLocation > string.length ||
       request.rangeLength > string.length - request.rangeLocation) {
        return NO;
    }

    std::vector<uint8_t> bytes(request.guestBuffer
        ? request.maximumLength : 0);
    NSUInteger usedLength = 0;
    NSRange remainingRange = NSMakeRange(0, 0);
    const BOOL converted = [string
        getBytes:bytes.empty() ? nullptr : bytes.data()
        maxLength:request.maximumLength
        usedLength:&usedLength
        encoding:(NSStringEncoding)request.encoding
        options:(NSStringEncodingConversionOptions)request.options
        range:NSMakeRange(request.rangeLocation, request.rangeLength)
        remainingRange:request.guestRemainingRange
            ? &remainingRange : nullptr];

    if(usedLength > request.maximumLength || usedLength > UINT32_MAX ||
       remainingRange.location > UINT32_MAX ||
       remainingRange.length > UINT32_MAX ||
       (request.guestBuffer && !writeGuestStringBytes(
            request.guestBuffer, bytes.data(), usedLength))) {
        return NO;
    }
    const uint32_t guestUsedLength = static_cast<uint32_t>(usedLength);
    const uint32_t guestRemainingRange[] = {
        static_cast<uint32_t>(remainingRange.location),
        static_cast<uint32_t>(remainingRange.length),
    };
    if((request.guestUsedLength && !writeGuestStringBytes(
            request.guestUsedLength, &guestUsedLength,
            sizeof(guestUsedLength))) ||
       (request.guestRemainingRange && !writeGuestStringBytes(
            request.guestRemainingRange, guestRemainingRange,
            sizeof(guestRemainingRange)))) {
        return NO;
    }
    return converted;
}

u64 LC32InvokeHostNSStringFormat(u64 host_self,
                                 u64 host_selector,
                                 u64 host_format,
                                 u64 host_locale,
                                 u32 guest_arguments,
                                 u32 options) {
    NSString *format = (NSString *)host_format;
    ParsedFormat parsed;
    if(!format || !parseFormat(format, parsed)) {
        fprintf(stderr, "LC32: unsupported or malformed NSString format: %s\n",
                format ? format.UTF8String : "(null)");
        return 0;
    }

    u64 hostSlots[kMaximumFormatArguments] = {};
    StableFormatPointers pointers;
    if(!translateArguments(parsed, guest_arguments, hostSlots, pointers)) {
        fprintf(stderr, "LC32: could not translate NSString format arguments: %s\n",
                format.UTF8String);
        return 0;
    }

    const u64 result = invokeHostFormat(
        host_self, host_selector, host_format, host_locale,
        options, hostSlots);
    if(!(options & LC32FormatReturnGuestObject) || !result) {
        return result;
    }
    return [(id)result guest_self];
}

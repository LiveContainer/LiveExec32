#ifndef LC32_POD_TYPE_H
#define LC32_POD_TYPE_H

#include <stdint.h>
#include <string.h>

// Numeric, by-value aggregates only. Pointers, unions, bitfields and opaque
// structs need explicit adapters, not a guessed layout. Shared by ARM32
// forwarding and native invocation/callback marshalling.
enum { LC32PODMaxFields = 32, LC32PODMaxSize = 256 };
typedef struct { char kind; unsigned offset; } LC32PODField;
typedef struct {
    unsigned size, alignment, count;
    LC32PODField fields[LC32PODMaxFields];
} LC32PODType;

static inline unsigned LC32PODAlign(unsigned size, unsigned alignment) {
    return (size + alignment - 1) & ~(alignment - 1);
}

static inline unsigned LC32PODScalarSize(char kind) {
    switch(kind) {
        case 'B': case 'c': case 'C': return 1;
        case 's': case 'S': return 2;
        case 'i': case 'I': case 'l': case 'L': case 'f': return 4;
        case 'q': case 'Q': case 'd': return 8;
        default: return 0;
    }
}

static inline int LC32PODAppend(LC32PODType *type, const LC32PODType *field) {
    unsigned offset = LC32PODAlign(type->size, field->alignment);
    if(offset + field->size > LC32PODMaxSize ||
            type->count + field->count > LC32PODMaxFields) return 0;
    for(unsigned i = 0; i < field->count; ++i) {
        type->fields[type->count] = field->fields[i];
        type->fields[type->count++].offset += offset;
    }
    type->size = offset + field->size;
    if(type->alignment < field->alignment) type->alignment = field->alignment;
    return 1;
}

static inline int LC32PODParse(const char **cursor, int native,
        unsigned depth, LC32PODType *type) {
    if(depth > 8 || !cursor || !*cursor) return 0;
    memset(type, 0, sizeof(*type));
    type->alignment = 1;
    const char *p = *cursor;
    while(*p && strchr("rnNoORVA", *p)) ++p;
    const char kind = *p;
    unsigned size = LC32PODScalarSize(kind);
    if(size) {
        type->size = size;
        type->alignment = native || size < 4 ? size : 4;
        type->count = 1;
        type->fields[0].kind = kind;
        ++p;
    } else if(kind == '{') {
        ++p;
        while(*p && *p != '=' && *p != '}') ++p;
        if(*p++ != '=') return 0;
        while(*p && *p != '}') {
            // Runtime encodings may include quoted field names.
            if(*p == '"') {
                ++p;
                while(*p && *p != '"') ++p;
                if(*p++ != '"') return 0;
            }
            LC32PODType field;
            if(!LC32PODParse(&p, native, depth + 1, &field) ||
                    !LC32PODAppend(type, &field)) return 0;
        }
        if(*p++ != '}' || !type->count) return 0;
        type->size = LC32PODAlign(type->size, type->alignment);
    } else if(kind == '[') {
        unsigned count = 0;
        ++p;
        while(*p >= '0' && *p <= '9') {
            count = count * 10 + (*p++ - '0');
            if(count > LC32PODMaxFields) return 0;
        }
        LC32PODType element;
        if(!count || !LC32PODParse(&p, native, depth + 1, &element) ||
                *p++ != ']') return 0;
        for(unsigned i = 0; i < count; ++i)
            if(!LC32PODAppend(type, &element)) return 0;
    } else return 0;
    *cursor = p;
    return 1;
}

static inline int LC32PODStructType(const char *encoding, int native,
        LC32PODType *type) {
    if(!encoding) return 0;
    while(*encoding && strchr("rnNoORVA", *encoding)) ++encoding;
    if(*encoding != '{') return 0;
    return LC32PODParse(&encoding, native, 0, type) && *encoding == '\0';
}

static inline char LC32PODHomogeneousFloat(const LC32PODType *type) {
    if(!type->count || type->count > 4) return 0;
    const char kind = type->fields[0].kind;
    if(kind != 'f' && kind != 'd') return 0;
    for(unsigned i = 1; i < type->count; ++i)
        if(type->fields[i].kind != kind) return 0;
    return kind;
}

#endif

#import <LC32/LC32.h>
#import <Foundation/Foundation.h>

/*
 * Each exported pointer must name a distinct guest Objective-C object.  The
 * previous scalar compound literal initialized every constant to the shared
 * __NSCFConstantString Class object itself, so binding a second symbol merely
 * replaced the first symbol's host peer.  A file-scope compound literal has
 * static storage duration; its single isa word is sufficient for these
 * opaque proxies now that LC32 keeps host identity in the native registry.
 */
#define LC32_CONST_STR_DECL(NAME) \
    NAME = (id)&(struct { void *isa; }){ __CFConstantStringClassReference };
#define LC32_CONST_STR_INIT(NAME) [(id)NAME bindHostSelf:LC32Dlsym(#NAME, NO)]

extern int __CFConstantStringClassReference[];

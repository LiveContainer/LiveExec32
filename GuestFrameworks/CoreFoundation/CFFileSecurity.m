#import <CoreFoundation/CoreFoundation+LC32.h>

CFTypeID CFFileSecurityGetTypeID(void) {
    return (CFTypeID)LC32_CF_CALL0(
        LC32CoreFoundationOpFileSecurityGetTypeID);
}

CFFileSecurityRef CFFileSecurityCreate(CFAllocatorRef allocator) {
    (void)allocator;
    return (CFFileSecurityRef)LC32_CF_CALL0(
        LC32CoreFoundationOpFileSecurityCreate);
}

CFFileSecurityRef CFFileSecurityCreateCopy(
        CFAllocatorRef allocator, CFFileSecurityRef fileSecurity) {
    (void)allocator;
    return fileSecurity ? (CFFileSecurityRef)LC32_CF_CALL(
        LC32CoreFoundationOpFileSecurityCreateCopy,
        LC32_CF_HOST(fileSecurity)) : NULL;
}

Boolean CFFileSecurityCopyOwnerUUID(
        CFFileSecurityRef fileSecurity, CFUUIDRef *ownerUUID) {
    if(ownerUUID) *ownerUUID = NULL;
    return fileSecurity && ownerUUID && LC32_CF_CALL(
        LC32CoreFoundationOpFileSecurityCopyOwnerUUID,
        LC32_CF_HOST(fileSecurity),
        LC32_CF_U32((uintptr_t)ownerUUID));
}

Boolean CFFileSecuritySetOwnerUUID(
        CFFileSecurityRef fileSecurity, CFUUIDRef ownerUUID) {
    return fileSecurity && ownerUUID && LC32_CF_CALL(
        LC32CoreFoundationOpFileSecuritySetOwnerUUID,
        LC32_CF_HOST(fileSecurity), LC32_CF_HOST(ownerUUID));
}

Boolean CFFileSecurityCopyGroupUUID(
        CFFileSecurityRef fileSecurity, CFUUIDRef *groupUUID) {
    if(groupUUID) *groupUUID = NULL;
    return fileSecurity && groupUUID && LC32_CF_CALL(
        LC32CoreFoundationOpFileSecurityCopyGroupUUID,
        LC32_CF_HOST(fileSecurity),
        LC32_CF_U32((uintptr_t)groupUUID));
}

Boolean CFFileSecuritySetGroupUUID(
        CFFileSecurityRef fileSecurity, CFUUIDRef groupUUID) {
    return fileSecurity && groupUUID && LC32_CF_CALL(
        LC32CoreFoundationOpFileSecuritySetGroupUUID,
        LC32_CF_HOST(fileSecurity), LC32_CF_HOST(groupUUID));
}

Boolean CFFileSecurityGetOwner(
        CFFileSecurityRef fileSecurity, uid_t *owner) {
    return fileSecurity && owner && LC32_CF_CALL(
        LC32CoreFoundationOpFileSecurityGetOwner,
        LC32_CF_HOST(fileSecurity), LC32_CF_U32((uintptr_t)owner));
}

Boolean CFFileSecuritySetOwner(
        CFFileSecurityRef fileSecurity, uid_t owner) {
    return fileSecurity && LC32_CF_CALL(
        LC32CoreFoundationOpFileSecuritySetOwner,
        LC32_CF_HOST(fileSecurity), LC32_CF_U32(owner));
}

Boolean CFFileSecurityGetGroup(
        CFFileSecurityRef fileSecurity, gid_t *group) {
    return fileSecurity && group && LC32_CF_CALL(
        LC32CoreFoundationOpFileSecurityGetGroup,
        LC32_CF_HOST(fileSecurity), LC32_CF_U32((uintptr_t)group));
}

Boolean CFFileSecuritySetGroup(
        CFFileSecurityRef fileSecurity, gid_t group) {
    return fileSecurity && LC32_CF_CALL(
        LC32CoreFoundationOpFileSecuritySetGroup,
        LC32_CF_HOST(fileSecurity), LC32_CF_U32(group));
}

Boolean CFFileSecurityGetMode(
        CFFileSecurityRef fileSecurity, mode_t *mode) {
    return fileSecurity && mode && LC32_CF_CALL(
        LC32CoreFoundationOpFileSecurityGetMode,
        LC32_CF_HOST(fileSecurity), LC32_CF_U32((uintptr_t)mode));
}

Boolean CFFileSecuritySetMode(
        CFFileSecurityRef fileSecurity, mode_t mode) {
    return fileSecurity && LC32_CF_CALL(
        LC32CoreFoundationOpFileSecuritySetMode,
        LC32_CF_HOST(fileSecurity), LC32_CF_U32(mode));
}

Boolean CFFileSecurityClearProperties(
        CFFileSecurityRef fileSecurity,
        CFFileSecurityClearOptions clearPropertyMask) {
    return fileSecurity && LC32_CF_CALL(
        LC32CoreFoundationOpFileSecurityClearProperties,
        LC32_CF_HOST(fileSecurity), LC32_CF_U32(clearPropertyMask));
}

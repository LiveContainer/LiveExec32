// Guest stub for AddressBook.framework
//
// Some legacy apps link AddressBook only for optional contact-based features.
// Export the small C surface used by those paths and simulate an empty address
// book without granting the host process access to real contacts.

#import <CoreFoundation/CoreFoundation.h>
#import <AddressBook/AddressBook.h>

// AB_EXTERN const — a real runtime symbol the app binds against.
const ABPropertyID kABPersonEmailProperty = 4;

ABAddressBookRef ABAddressBookCreate(void) {
    // A valid, empty placeholder the caller can CFRelease safely.
    return (ABAddressBookRef)CFArrayCreate(NULL, NULL, 0,
        &kCFTypeArrayCallBacks);
}

CFArrayRef ABAddressBookCopyArrayOfAllPeople(ABAddressBookRef addressBook) {
    // No contacts.
    return CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
}

ABRecordType ABRecordGetRecordType(ABRecordRef record) {
    return kABPersonType;
}

CFTypeRef ABRecordCopyValue(ABRecordRef record, ABPropertyID property) {
    return NULL;
}

CFArrayRef ABMultiValueCopyArrayOfAllValues(ABMultiValueRef multiValue) {
    return CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
}

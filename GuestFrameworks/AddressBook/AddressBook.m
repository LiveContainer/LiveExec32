// Guest-side compatibility implementation for the deprecated AddressBook C
// API. The shim intentionally exposes an isolated, process-local address
// book: legacy optional contact flows remain usable without granting access
// to the user's actual contacts.

#import <AddressBook/AddressBook.h>
#import <CoreFoundation/CoreFoundation.h>

// Clients obtain these property identifiers through exported variables. Their
// exact values only need to stay unique and stable inside this isolated store.
const ABPropertyID kABPersonFirstNameProperty = 0;
const ABPropertyID kABPersonLastNameProperty = 1;
const ABPropertyID kABPersonMiddleNameProperty = 2;
const ABPropertyID kABPersonPrefixProperty = 3;
const ABPropertyID kABPersonEmailProperty = 4;
const ABPropertyID kABPersonSuffixProperty = 5;
const ABPropertyID kABPersonNicknameProperty = 6;
const ABPropertyID kABPersonOrganizationProperty = 7;
const ABPropertyID kABPersonDepartmentProperty = 8;
const ABPropertyID kABPersonJobTitleProperty = 9;
const ABPropertyID kABPersonBirthdayProperty = 10;
const ABPropertyID kABPersonNoteProperty = 11;
const ABPropertyID kABPersonAddressProperty = 12;
const ABPropertyID kABPersonPhoneProperty = 13;
const ABPropertyID kABPersonInstantMessageProperty = 14;
const ABPropertyID kABPersonURLProperty = 15;

const CFStringRef kABWorkLabel = CFSTR("_$!<Work>!$_");
const CFStringRef kABHomeLabel = CFSTR("_$!<Home>!$_");
const CFStringRef kABOtherLabel = CFSTR("_$!<Other>!$_");
const CFStringRef kABPersonHomePageLabel = CFSTR("_$!<HomePage>!$_");

const CFStringRef kABPersonAddressStreetKey = CFSTR("Street");
const CFStringRef kABPersonAddressCityKey = CFSTR("City");
const CFStringRef kABPersonAddressStateKey = CFSTR("State");
const CFStringRef kABPersonAddressZIPKey = CFSTR("ZIP");
const CFStringRef kABPersonAddressCountryKey = CFSTR("Country");
const CFStringRef kABPersonAddressCountryCodeKey = CFSTR("CountryCode");
const CFStringRef kABPersonInstantMessageServiceKey = CFSTR("service");
const CFStringRef kABPersonInstantMessageUsernameKey = CFSTR("username");

static const CFStringRef LC32ABMultiValueValueKey = CFSTR("value");
static const CFStringRef LC32ABMultiValueLabelKey = CFSTR("label");
static const CFStringRef LC32ABPersonImageDataKey =
    CFSTR("LC32AddressBookImageData");

static CFNumberRef LC32ABPropertyKey(ABPropertyID property) {
    int32_t value = property;
    return CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &value);
}

ABAddressBookRef ABAddressBookCreate(void) {
    return (ABAddressBookRef)CFArrayCreateMutable(kCFAllocatorDefault, 0,
        &kCFTypeArrayCallBacks);
}

bool ABAddressBookAddRecord(ABAddressBookRef addressBook, ABRecordRef record,
                            CFErrorRef *error) {
    if(error) *error = NULL;
    if(!addressBook || !record) return false;
    CFArrayAppendValue((CFMutableArrayRef)addressBook, record);
    return true;
}

bool ABAddressBookSave(ABAddressBookRef addressBook, CFErrorRef *error) {
    if(error) *error = NULL;
    return addressBook != NULL;
}

CFArrayRef ABAddressBookCopyArrayOfAllPeople(
        ABAddressBookRef addressBook) {
    if(!addressBook)
        return CFArrayCreate(kCFAllocatorDefault, NULL, 0,
            &kCFTypeArrayCallBacks);
    return CFArrayCreateCopy(kCFAllocatorDefault, (CFArrayRef)addressBook);
}

ABRecordRef ABPersonCreate(void) {
    return (ABRecordRef)CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
}

bool ABPersonSetImageData(ABRecordRef person, CFDataRef imageData,
                          CFErrorRef *error) {
    if(error) *error = NULL;
    if(!person || !imageData) return false;
    CFDictionarySetValue((CFMutableDictionaryRef)person,
        LC32ABPersonImageDataKey, imageData);
    return true;
}

ABRecordType ABRecordGetRecordType(ABRecordRef record) {
    (void)record;
    return kABPersonType;
}

bool ABRecordSetValue(ABRecordRef record, ABPropertyID property,
                      CFTypeRef value, CFErrorRef *error) {
    if(error) *error = NULL;
    if(!record || !value) return false;
    CFNumberRef key = LC32ABPropertyKey(property);
    if(!key) return false;
    CFDictionarySetValue((CFMutableDictionaryRef)record, key, value);
    CFRelease(key);
    return true;
}

CFTypeRef ABRecordCopyValue(ABRecordRef record, ABPropertyID property) {
    if(!record) return NULL;
    CFNumberRef key = LC32ABPropertyKey(property);
    if(!key) return NULL;
    CFTypeRef value = CFDictionaryGetValue((CFDictionaryRef)record, key);
    if(value) CFRetain(value);
    CFRelease(key);
    return value;
}

ABMutableMultiValueRef ABMultiValueCreateMutable(ABPropertyType type) {
    (void)type;
    return (ABMutableMultiValueRef)CFArrayCreateMutable(kCFAllocatorDefault,
        0, &kCFTypeArrayCallBacks);
}

bool ABMultiValueAddValueAndLabel(ABMutableMultiValueRef multiValue,
                                  CFTypeRef value, CFStringRef label,
                                  ABMultiValueIdentifier *outIdentifier) {
    if(!multiValue || !value) return false;
    CFMutableDictionaryRef entry = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    if(!entry) return false;
    CFDictionarySetValue(entry, LC32ABMultiValueValueKey, value);
    if(label)
        CFDictionarySetValue(entry, LC32ABMultiValueLabelKey, label);
    CFIndex index = CFArrayGetCount((CFArrayRef)multiValue);
    CFArrayAppendValue((CFMutableArrayRef)multiValue, entry);
    CFRelease(entry);
    if(outIdentifier) *outIdentifier = (ABMultiValueIdentifier)(index + 1);
    return true;
}

CFIndex ABMultiValueGetCount(ABMultiValueRef multiValue) {
    return multiValue ? CFArrayGetCount((CFArrayRef)multiValue) : 0;
}

static CFDictionaryRef LC32ABMultiValueEntry(ABMultiValueRef multiValue,
                                             CFIndex index) {
    if(!multiValue || index < 0 ||
       index >= CFArrayGetCount((CFArrayRef)multiValue)) return NULL;
    return (CFDictionaryRef)CFArrayGetValueAtIndex(
        (CFArrayRef)multiValue, index);
}

CFTypeRef ABMultiValueCopyValueAtIndex(ABMultiValueRef multiValue,
                                       CFIndex index) {
    CFDictionaryRef entry = LC32ABMultiValueEntry(multiValue, index);
    if(!entry) return NULL;
    CFTypeRef value = CFDictionaryGetValue(entry,
        LC32ABMultiValueValueKey);
    return value ? CFRetain(value) : NULL;
}

CFStringRef ABMultiValueCopyLabelAtIndex(ABMultiValueRef multiValue,
                                         CFIndex index) {
    CFDictionaryRef entry = LC32ABMultiValueEntry(multiValue, index);
    if(!entry) return NULL;
    CFStringRef label = (CFStringRef)CFDictionaryGetValue(entry,
        LC32ABMultiValueLabelKey);
    return label ? (CFStringRef)CFRetain(label) : NULL;
}

CFArrayRef ABMultiValueCopyArrayOfAllValues(ABMultiValueRef multiValue) {
    CFIndex count = ABMultiValueGetCount(multiValue);
    CFMutableArrayRef values = CFArrayCreateMutable(kCFAllocatorDefault,
        count, &kCFTypeArrayCallBacks);
    if(!values) return NULL;
    for(CFIndex index = 0; index < count; ++index) {
        CFTypeRef value = ABMultiValueCopyValueAtIndex(multiValue, index);
        if(value) {
            CFArrayAppendValue(values, value);
            CFRelease(value);
        }
    }
    return values;
}

// Guest-side compatibility implementation for the deprecated AddressBook C
// API. The shim intentionally exposes an isolated, process-local address
// book: legacy optional contact flows remain usable without granting access
// to the user's actual contacts.

#import <AddressBook/AddressBook.h>
#import <CoreFoundation/CoreFoundation.h>

// Keep the iOS AddressBook property identifiers so applications can persist
// and compare them while the backing store remains process-local.
const ABPropertyID kABPersonFirstNameProperty = 0;
const ABPropertyID kABPersonLastNameProperty = 1;
const ABPropertyID kABPersonPhoneProperty = 3;
const ABPropertyID kABPersonEmailProperty = 4;
const ABPropertyID kABPersonAddressProperty = 5;
const ABPropertyID kABPersonMiddleNameProperty = 6;
const ABPropertyID kABPersonFirstNamePhoneticProperty = 7;
const ABPropertyID kABPersonMiddleNamePhoneticProperty = 8;
const ABPropertyID kABPersonLastNamePhoneticProperty = 9;
const ABPropertyID kABPersonOrganizationProperty = 10;
const ABPropertyID kABPersonDepartmentProperty = 11;
const ABPropertyID kABPersonInstantMessageProperty = 13;
const ABPropertyID kABPersonNoteProperty = 14;
const ABPropertyID kABPersonBirthdayProperty = 17;
const ABPropertyID kABPersonJobTitleProperty = 18;
const ABPropertyID kABPersonNicknameProperty = 19;
const ABPropertyID kABPersonPrefixProperty = 20;
const ABPropertyID kABPersonSuffixProperty = 21;
const ABPropertyID kABPersonURLProperty = 22;

const CFStringRef kABWorkLabel = CFSTR("_$!<Work>!$_");
const CFStringRef kABHomeLabel = CFSTR("_$!<Home>!$_");
const CFStringRef kABOtherLabel = CFSTR("_$!<Other>!$_");
const CFStringRef kABPersonHomePageLabel = CFSTR("_$!<HomePage>!$_");
const CFStringRef kABPersonPhoneIPhoneLabel = CFSTR("iPhone");
const CFStringRef kABPersonPhoneMobileLabel = CFSTR("_$!<Mobile>!$_");

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
static const CFStringRef LC32ABRecordIDKey =
    CFSTR("LC32AddressBookRecordID");
static ABRecordID LC32ABNextRecordID = 1;

static CFNumberRef LC32ABPropertyKey(ABPropertyID property) {
    int32_t value = property;
    return CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &value);
}

ABAddressBookRef ABAddressBookCreate(void) {
    return (ABAddressBookRef)CFArrayCreateMutable(kCFAllocatorDefault, 0,
        &kCFTypeArrayCallBacks);
}

CFStringRef ABAddressBookCopyLocalizedLabel(CFStringRef label) {
    /* The isolated store has no Contacts localization bundle. Preserve the
     * label text with the API's Create ownership contract. */
    return label ? CFStringCreateCopy(kCFAllocatorDefault, label) : NULL;
}

void ABAddressBookRegisterExternalChangeCallback(
        ABAddressBookRef addressBook, ABExternalChangeCallback callback,
        void *context) {
    (void)addressBook;
    (void)callback;
    (void)context;
    /* No other process can mutate this process-local address book. */
}

void ABAddressBookUnregisterExternalChangeCallback(
        ABAddressBookRef addressBook, ABExternalChangeCallback callback,
        void *context) {
    (void)addressBook;
    (void)callback;
    (void)context;
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
    CFMutableDictionaryRef person = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if(!person) return NULL;

    ABRecordID recordID = __atomic_fetch_add(
        &LC32ABNextRecordID, 1, __ATOMIC_RELAXED);
    CFNumberRef recordIDNumber = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt32Type, &recordID);
    if(recordIDNumber) {
        CFDictionarySetValue(person, LC32ABRecordIDKey, recordIDNumber);
        CFRelease(recordIDNumber);
    }
    return (ABRecordRef)person;
}

ABPersonCompositeNameFormat ABPersonGetCompositeNameFormat(void) {
    return kABPersonCompositeNameFormatFirstNameFirst;
}

ABPersonSortOrdering ABPersonGetSortOrdering(void) {
    return kABPersonSortByFirstName;
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

ABRecordID ABRecordGetRecordID(ABRecordRef record) {
    if(!record) return kABRecordInvalidID;
    CFNumberRef number = (CFNumberRef)CFDictionaryGetValue(
        (CFDictionaryRef)record, LC32ABRecordIDKey);
    ABRecordID recordID = kABRecordInvalidID;
    if(number) CFNumberGetValue(
        number, kCFNumberSInt32Type, &recordID);
    return recordID;
}

static void LC32ABAppendNameProperty(CFMutableStringRef name,
                                     ABRecordRef record,
                                     ABPropertyID property) {
    CFTypeRef value = ABRecordCopyValue(record, property);
    if(!value) return;
    if(CFGetTypeID(value) == CFStringGetTypeID() &&
            CFStringGetLength((CFStringRef)value) != 0) {
        if(CFStringGetLength(name) != 0) CFStringAppend(name, CFSTR(" "));
        CFStringAppend(name, (CFStringRef)value);
    }
    CFRelease(value);
}

CFStringRef ABRecordCopyCompositeName(ABRecordRef record) {
    if(!record) return NULL;
    CFMutableStringRef name = CFStringCreateMutable(
        kCFAllocatorDefault, 0);
    if(!name) return NULL;

    LC32ABAppendNameProperty(name, record, kABPersonPrefixProperty);
    LC32ABAppendNameProperty(name, record, kABPersonFirstNameProperty);
    LC32ABAppendNameProperty(name, record, kABPersonMiddleNameProperty);
    LC32ABAppendNameProperty(name, record, kABPersonLastNameProperty);
    LC32ABAppendNameProperty(name, record, kABPersonSuffixProperty);
    if(CFStringGetLength(name) == 0)
        LC32ABAppendNameProperty(
            name, record, kABPersonOrganizationProperty);
    if(CFStringGetLength(name) == 0)
        LC32ABAppendNameProperty(name, record, kABPersonNicknameProperty);

    if(CFStringGetLength(name) == 0) {
        CFRelease(name);
        return NULL;
    }
    return name;
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

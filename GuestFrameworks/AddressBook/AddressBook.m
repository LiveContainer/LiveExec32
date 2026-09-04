// Guest-side compatibility implementation for the deprecated AddressBook C
// API. The shim intentionally exposes an isolated, process-local address
// book: legacy optional contact flows remain usable without granting access
// to the user's actual contacts.

#import <AddressBook/AddressBook.h>
#import <CoreFoundation/CoreFoundation.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

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
const ABPropertyID kABPersonCreationDateProperty = 23;
const ABPropertyID kABPersonModificationDateProperty = 24;
const ABPropertyID kABPersonSocialProfileProperty = 25;
const ABPropertyID kABPersonAlternateBirthdayProperty = 26;
const ABPropertyID kABPersonDateProperty = 12;
const ABPropertyID kABPersonKindProperty = 15;
const ABPropertyID kABPersonRelatedNamesProperty = 16;

const ABPropertyID kABSourceNameProperty = 0;
const ABPropertyID kABSourceTypeProperty = 1;
const int kABGroupNameProperty = 0;

const CFStringRef ABAddressBookErrorDomain =
    CFSTR("ABAddressBookErrorDomain");

/* CFNumber globals require writable pointer storage so they can be populated
 * with real guest proxy objects after the bridge is initialized. */
CFNumberRef LC32ABPersonKindPerson __asm__("_kABPersonKindPerson");
CFNumberRef LC32ABPersonKindOrganization
    __asm__("_kABPersonKindOrganization");

const CFStringRef kABWorkLabel = CFSTR("_$!<Work>!$_");
const CFStringRef kABHomeLabel = CFSTR("_$!<Home>!$_");
const CFStringRef kABOtherLabel = CFSTR("_$!<Other>!$_");
const CFStringRef kABPersonHomePageLabel = CFSTR("_$!<HomePage>!$_");
const CFStringRef kABPersonPhoneIPhoneLabel = CFSTR("iPhone");
const CFStringRef kABPersonPhoneMobileLabel = CFSTR("_$!<Mobile>!$_");
const CFStringRef kABPersonPhoneMainLabel = CFSTR("_$!<Main>!$_");
const CFStringRef kABPersonPhoneHomeFAXLabel = CFSTR("_$!<HomeFAX>!$_");
const CFStringRef kABPersonPhoneWorkFAXLabel = CFSTR("_$!<WorkFAX>!$_");
const CFStringRef kABPersonPhoneOtherFAXLabel = CFSTR("_$!<OtherFAX>!$_");
const CFStringRef kABPersonPhonePagerLabel = CFSTR("_$!<Pager>!$_");

const CFStringRef kABPersonAnniversaryLabel =
    CFSTR("_$!<Anniversary>!$_");
const CFStringRef kABPersonAssistantLabel = CFSTR("_$!<Assistant>!$_");
const CFStringRef kABPersonBrotherLabel = CFSTR("_$!<Brother>!$_");
const CFStringRef kABPersonChildLabel = CFSTR("_$!<Child>!$_");
const CFStringRef kABPersonFatherLabel = CFSTR("_$!<Father>!$_");
const CFStringRef kABPersonFriendLabel = CFSTR("_$!<Friend>!$_");
const CFStringRef kABPersonManagerLabel = CFSTR("_$!<Manager>!$_");
const CFStringRef kABPersonMotherLabel = CFSTR("_$!<Mother>!$_");
const CFStringRef kABPersonParentLabel = CFSTR("_$!<Parent>!$_");
const CFStringRef kABPersonPartnerLabel = CFSTR("_$!<Partner>!$_");
const CFStringRef kABPersonSisterLabel = CFSTR("_$!<Sister>!$_");
const CFStringRef kABPersonSpouseLabel = CFSTR("_$!<Spouse>!$_");

const CFStringRef kABPersonAddressStreetKey = CFSTR("Street");
const CFStringRef kABPersonAddressCityKey = CFSTR("City");
const CFStringRef kABPersonAddressStateKey = CFSTR("State");
const CFStringRef kABPersonAddressZIPKey = CFSTR("ZIP");
const CFStringRef kABPersonAddressCountryKey = CFSTR("Country");
const CFStringRef kABPersonAddressCountryCodeKey = CFSTR("CountryCode");
const CFStringRef kABPersonInstantMessageServiceKey = CFSTR("service");
const CFStringRef kABPersonInstantMessageUsernameKey = CFSTR("username");
const CFStringRef kABPersonInstantMessageServiceAIM = CFSTR("AIM");
const CFStringRef kABPersonInstantMessageServiceFacebook =
    CFSTR("Facebook");
const CFStringRef kABPersonInstantMessageServiceGaduGadu =
    CFSTR("Gadu-Gadu");
const CFStringRef kABPersonInstantMessageServiceGoogleTalk =
    CFSTR("Google Talk");
const CFStringRef kABPersonInstantMessageServiceICQ = CFSTR("ICQ");
const CFStringRef kABPersonInstantMessageServiceJabber = CFSTR("Jabber");
const CFStringRef kABPersonInstantMessageServiceMSN = CFSTR("MSN");
const CFStringRef kABPersonInstantMessageServiceQQ = CFSTR("QQ");
const CFStringRef kABPersonInstantMessageServiceSkype = CFSTR("Skype");
const CFStringRef kABPersonInstantMessageServiceYahoo = CFSTR("Yahoo");

const CFStringRef kABPersonSocialProfileURLKey = CFSTR("url");
const CFStringRef kABPersonSocialProfileServiceKey = CFSTR("service");
const CFStringRef kABPersonSocialProfileUsernameKey = CFSTR("username");
const CFStringRef kABPersonSocialProfileUserIdentifierKey =
    CFSTR("userIdentifier");
const CFStringRef kABPersonSocialProfileServiceTwitter = CFSTR("twitter");
const CFStringRef kABPersonSocialProfileServiceGameCenter =
    CFSTR("gamecenter");
const CFStringRef kABPersonSocialProfileServiceFacebook =
    CFSTR("facebook");
const CFStringRef kABPersonSocialProfileServiceMyspace = CFSTR("myspace");
const CFStringRef kABPersonSocialProfileServiceLinkedIn =
    CFSTR("linkedin");
const CFStringRef kABPersonSocialProfileServiceFlickr = CFSTR("flickr");
const CFStringRef kABPersonSocialProfileServiceSinaWeibo =
    CFSTR("sinaweibo");

const CFStringRef kABPersonAlternateBirthdayCalendarIdentifierKey =
    CFSTR("calendarIdentifier");
const CFStringRef kABPersonAlternateBirthdayEraKey = CFSTR("era");
const CFStringRef kABPersonAlternateBirthdayYearKey = CFSTR("year");
const CFStringRef kABPersonAlternateBirthdayMonthKey = CFSTR("month");
const CFStringRef kABPersonAlternateBirthdayDayKey = CFSTR("day");
const CFStringRef kABPersonAlternateBirthdayIsLeapMonthKey =
    CFSTR("isLeapMonth");

static const CFStringRef LC32ABMultiValueValueKey = CFSTR("value");
static const CFStringRef LC32ABMultiValueLabelKey = CFSTR("label");
static const CFStringRef LC32ABMultiValueIdentifierKey =
    CFSTR("identifier");
static const CFStringRef LC32ABPersonImageDataKey =
    CFSTR("LC32AddressBookImageData");
static const CFStringRef LC32ABRecordIDKey =
    CFSTR("LC32AddressBookRecordID");
static const CFStringRef LC32ABRecordTypeKey =
    CFSTR("LC32AddressBookRecordType");
static const CFStringRef LC32ABRecordSourceKey =
    CFSTR("LC32AddressBookRecordSource");
static const CFStringRef LC32ABGroupMembersKey =
    CFSTR("LC32AddressBookGroupMembers");
static ABRecordID LC32ABNextRecordID = 1;
static ABMultiValueIdentifier LC32ABNextMultiValueIdentifier = 1;

__attribute__((constructor))
static void LC32ABInitializeNumberConstants(void) {
    int32_t person = 0;
    int32_t organization = 1;
    LC32ABPersonKindPerson = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt32Type, &person);
    LC32ABPersonKindOrganization = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt32Type, &organization);
}

static CFNumberRef LC32ABPropertyKey(ABPropertyID property) {
    int32_t value = property;
    return CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &value);
}

static ABRecordRef LC32ABCreateRecord(ABRecordType type) {
    CFMutableDictionaryRef record = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if(!record) return NULL;

    ABRecordID recordID = __atomic_fetch_add(
        &LC32ABNextRecordID, 1, __ATOMIC_RELAXED);
    CFNumberRef recordIDNumber = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt32Type, &recordID);
    CFNumberRef recordTypeNumber = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt32Type, &type);
    if(recordIDNumber) {
        CFDictionarySetValue(record, LC32ABRecordIDKey, recordIDNumber);
        CFRelease(recordIDNumber);
    }
    if(recordTypeNumber) {
        CFDictionarySetValue(record, LC32ABRecordTypeKey, recordTypeNumber);
        CFRelease(recordTypeNumber);
    }
    return (ABRecordRef)record;
}

static ABRecordRef LC32ABDefaultSource(void) {
    static ABRecordRef source;
    if(!source) {
        source = LC32ABCreateRecord(kABSourceType);
        if(source) {
            CFErrorRef error = NULL;
            ABRecordSetValue(source, kABSourceNameProperty,
                CFSTR("Local"), &error);
            int32_t type = kABSourceTypeLocal;
            CFNumberRef typeNumber = CFNumberCreate(
                kCFAllocatorDefault, kCFNumberSInt32Type, &type);
            if(typeNumber) {
                ABRecordSetValue(source, kABSourceTypeProperty,
                    typeNumber, &error);
                CFRelease(typeNumber);
            }
            if(error) CFRelease(error);
        }
    }
    return source;
}

ABAddressBookRef ABAddressBookCreate(void) {
    return (ABAddressBookRef)CFArrayCreateMutable(kCFAllocatorDefault, 0,
        &kCFTypeArrayCallBacks);
}

ABAddressBookRef ABAddressBookCreateWithOptions(
        CFDictionaryRef options, CFErrorRef *error) {
    (void)options;
    if(error) *error = NULL;
    return ABAddressBookCreate();
}

ABAuthorizationStatus ABAddressBookGetAuthorizationStatus(void) {
    /* The compatibility store is isolated from the user's real contacts and
     * therefore needs no privacy grant. */
    return kABAuthorizationStatusAuthorized;
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

bool ABAddressBookHasUnsavedChanges(ABAddressBookRef addressBook) {
    (void)addressBook;
    return false;
}

bool ABAddressBookRemoveRecord(ABAddressBookRef addressBook,
                               ABRecordRef record, CFErrorRef *error) {
    if(error) *error = NULL;
    if(!addressBook || !record) return false;
    CFMutableArrayRef records = (CFMutableArrayRef)addressBook;
    CFIndex count = CFArrayGetCount(records);
    CFIndex index = CFArrayGetFirstIndexOfValue(
        records, CFRangeMake(0, count), record);
    if(index == kCFNotFound) return false;
    CFArrayRemoveValueAtIndex(records, index);
    return true;
}

void ABAddressBookRevert(ABAddressBookRef addressBook) {
    (void)addressBook;
}

static CFArrayRef LC32ABCopyRecords(
        ABAddressBookRef addressBook, ABRecordType type,
        ABRecordRef source) {
    CFMutableArrayRef result = CFArrayCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    if(!result || !addressBook) return result;

    CFIndex count = CFArrayGetCount((CFArrayRef)addressBook);
    for(CFIndex index = 0; index < count; index++) {
        ABRecordRef record = (ABRecordRef)CFArrayGetValueAtIndex(
            (CFArrayRef)addressBook, index);
        if(ABRecordGetRecordType(record) != type) continue;
        if(source) {
            ABRecordRef recordSource = (ABRecordRef)CFDictionaryGetValue(
                (CFDictionaryRef)record, LC32ABRecordSourceKey);
            if(!recordSource) recordSource = LC32ABDefaultSource();
            if(recordSource != source && !CFEqual(recordSource, source))
                continue;
        }
        CFArrayAppendValue(result, record);
    }
    return result;
}

static ABRecordRef LC32ABGetRecordWithID(
        ABAddressBookRef addressBook, ABRecordType type,
        ABRecordID recordID) {
    if(!addressBook) return NULL;
    CFIndex count = CFArrayGetCount((CFArrayRef)addressBook);
    for(CFIndex index = 0; index < count; index++) {
        ABRecordRef record = (ABRecordRef)CFArrayGetValueAtIndex(
            (CFArrayRef)addressBook, index);
        if(ABRecordGetRecordType(record) == type &&
                ABRecordGetRecordID(record) == recordID)
            return record;
    }
    return NULL;
}

CFArrayRef ABAddressBookCopyArrayOfAllPeople(
        ABAddressBookRef addressBook) {
    return LC32ABCopyRecords(addressBook, kABPersonType, NULL);
}

CFIndex ABAddressBookGetPersonCount(ABAddressBookRef addressBook) {
    CFArrayRef people = ABAddressBookCopyArrayOfAllPeople(addressBook);
    CFIndex count = people ? CFArrayGetCount(people) : 0;
    if(people) CFRelease(people);
    return count;
}

ABRecordRef ABAddressBookGetPersonWithRecordID(
        ABAddressBookRef addressBook, ABRecordID recordID) {
    return LC32ABGetRecordWithID(addressBook, kABPersonType, recordID);
}

CFArrayRef ABAddressBookCopyArrayOfAllPeopleInSource(
        ABAddressBookRef addressBook, ABRecordRef source) {
    return LC32ABCopyRecords(addressBook, kABPersonType, source);
}

CFArrayRef ABAddressBookCopyArrayOfAllPeopleInSourceWithSortOrdering(
        ABAddressBookRef addressBook, ABRecordRef source,
        ABPersonSortOrdering sortOrdering) {
    (void)sortOrdering;
    return ABAddressBookCopyArrayOfAllPeopleInSource(addressBook, source);
}

CFArrayRef ABAddressBookCopyPeopleWithName(
        ABAddressBookRef addressBook, CFStringRef name) {
    CFMutableArrayRef matches = CFArrayCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    if(!matches || !name) return matches;
    CFArrayRef people = ABAddressBookCopyArrayOfAllPeople(addressBook);
    CFIndex count = people ? CFArrayGetCount(people) : 0;
    for(CFIndex index = 0; index < count; index++) {
        ABRecordRef person = (ABRecordRef)CFArrayGetValueAtIndex(
            people, index);
        CFStringRef compositeName = ABRecordCopyCompositeName(person);
        if(compositeName) {
            CFRange match = CFStringFind(compositeName, name,
                kCFCompareCaseInsensitive | kCFCompareDiacriticInsensitive);
            if(match.location != kCFNotFound)
                CFArrayAppendValue(matches, person);
            CFRelease(compositeName);
        }
    }
    if(people) CFRelease(people);
    return matches;
}

ABRecordRef ABPersonCreate(void) {
    return LC32ABCreateRecord(kABPersonType);
}

ABRecordRef ABPersonCreateInSource(ABRecordRef source) {
    ABRecordRef person = ABPersonCreate();
    if(person && source)
        CFDictionarySetValue((CFMutableDictionaryRef)person,
            LC32ABRecordSourceKey, source);
    return person;
}

ABRecordRef ABPersonCopySource(ABRecordRef person) {
    if(!person) return NULL;
    ABRecordRef source = (ABRecordRef)CFDictionaryGetValue(
        (CFDictionaryRef)person, LC32ABRecordSourceKey);
    if(!source) source = LC32ABDefaultSource();
    return source ? (ABRecordRef)CFRetain(source) : NULL;
}

CFArrayRef ABPersonCopyArrayOfAllLinkedPeople(ABRecordRef person) {
    if(!person) return CFArrayCreate(kCFAllocatorDefault, NULL, 0,
        &kCFTypeArrayCallBacks);
    const void *value = person;
    return CFArrayCreate(kCFAllocatorDefault, &value, 1,
        &kCFTypeArrayCallBacks);
}

ABPropertyType ABPersonGetTypeOfProperty(ABPropertyID property) {
    switch(property) {
        case 0: /* first name / source name */
        case kABPersonLastNameProperty:
        case kABPersonMiddleNameProperty:
        case kABPersonFirstNamePhoneticProperty:
        case kABPersonMiddleNamePhoneticProperty:
        case kABPersonLastNamePhoneticProperty:
        case kABPersonOrganizationProperty:
        case kABPersonDepartmentProperty:
        case kABPersonNoteProperty:
        case kABPersonJobTitleProperty:
        case kABPersonNicknameProperty:
        case kABPersonPrefixProperty:
        case kABPersonSuffixProperty:
            return kABStringPropertyType;
        case kABPersonPhoneProperty:
        case kABPersonEmailProperty:
        case kABPersonURLProperty:
        case kABPersonRelatedNamesProperty:
            return kABMultiStringPropertyType;
        case kABPersonAddressProperty:
        case kABPersonInstantMessageProperty:
        case kABPersonSocialProfileProperty:
            return kABMultiDictionaryPropertyType;
        case kABPersonBirthdayProperty:
        case kABPersonCreationDateProperty:
        case kABPersonModificationDateProperty:
            return kABDateTimePropertyType;
        case kABPersonDateProperty:
            return kABMultiDateTimePropertyType;
        case kABPersonAlternateBirthdayProperty:
            return kABDictionaryPropertyType;
        case kABPersonKindProperty:
            return kABIntegerPropertyType;
        default:
            return kABInvalidPropertyType;
    }
}

CFStringRef ABPersonCopyLocalizedPropertyName(ABPropertyID property) {
    CFStringRef name = NULL;
    switch(property) {
        case kABPersonFirstNameProperty: name = CFSTR("First Name"); break;
        case kABPersonLastNameProperty: name = CFSTR("Last Name"); break;
        case kABPersonMiddleNameProperty: name = CFSTR("Middle Name"); break;
        case kABPersonPrefixProperty: name = CFSTR("Prefix"); break;
        case kABPersonSuffixProperty: name = CFSTR("Suffix"); break;
        case kABPersonNicknameProperty: name = CFSTR("Nickname"); break;
        case kABPersonOrganizationProperty: name = CFSTR("Organization"); break;
        case kABPersonDepartmentProperty: name = CFSTR("Department"); break;
        case kABPersonJobTitleProperty: name = CFSTR("Job Title"); break;
        case kABPersonEmailProperty: name = CFSTR("Email"); break;
        case kABPersonBirthdayProperty: name = CFSTR("Birthday"); break;
        case kABPersonNoteProperty: name = CFSTR("Note"); break;
        case kABPersonAddressProperty: name = CFSTR("Address"); break;
        case kABPersonDateProperty: name = CFSTR("Date"); break;
        case kABPersonKindProperty: name = CFSTR("Kind"); break;
        case kABPersonPhoneProperty: name = CFSTR("Phone"); break;
        case kABPersonInstantMessageProperty:
            name = CFSTR("Instant Message"); break;
        case kABPersonURLProperty: name = CFSTR("URL"); break;
        case kABPersonRelatedNamesProperty:
            name = CFSTR("Related Names"); break;
        case kABPersonSocialProfileProperty:
            name = CFSTR("Social Profile"); break;
        default: return NULL;
    }
    return CFStringCreateCopy(kCFAllocatorDefault, name);
}

ABPersonCompositeNameFormat ABPersonGetCompositeNameFormat(void) {
    return kABPersonCompositeNameFormatFirstNameFirst;
}

ABPersonCompositeNameFormat ABPersonGetCompositeNameFormatForRecord(
        ABRecordRef record) {
    (void)record;
    return ABPersonGetCompositeNameFormat();
}

CFStringRef ABPersonCopyCompositeNameDelimiterForRecord(
        ABRecordRef record) {
    (void)record;
    return CFStringCreateCopy(kCFAllocatorDefault, CFSTR(" "));
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

CFDataRef ABPersonCopyImageData(ABRecordRef person) {
    if(!person) return NULL;
    CFDataRef data = (CFDataRef)CFDictionaryGetValue(
        (CFDictionaryRef)person, LC32ABPersonImageDataKey);
    return data ? (CFDataRef)CFRetain(data) : NULL;
}

CFDataRef ABPersonCopyImageDataWithFormat(
        ABRecordRef person, ABPersonImageFormat format) {
    (void)format;
    return ABPersonCopyImageData(person);
}

bool ABPersonHasImageData(ABRecordRef person) {
    return person && CFDictionaryGetValue(
        (CFDictionaryRef)person, LC32ABPersonImageDataKey) != NULL;
}

bool ABPersonRemoveImageData(ABRecordRef person, CFErrorRef *error) {
    if(error) *error = NULL;
    if(!person) return false;
    CFDictionaryRemoveValue(
        (CFMutableDictionaryRef)person, LC32ABPersonImageDataKey);
    return true;
}

CFComparisonResult ABPersonComparePeopleByName(
        ABRecordRef person1, ABRecordRef person2,
        ABPersonSortOrdering ordering) {
    (void)ordering;
    CFStringRef name1 = ABRecordCopyCompositeName(person1);
    CFStringRef name2 = ABRecordCopyCompositeName(person2);
    CFComparisonResult result = kCFCompareEqualTo;
    if(name1 && name2)
        result = CFStringCompare(name1, name2,
            kCFCompareCaseInsensitive | kCFCompareDiacriticInsensitive);
    else if(name1)
        result = kCFCompareGreaterThan;
    else if(name2)
        result = kCFCompareLessThan;
    if(name1) CFRelease(name1);
    if(name2) CFRelease(name2);
    return result;
}

ABRecordType ABRecordGetRecordType(ABRecordRef record) {
    if(!record) return kABPersonType;
    CFNumberRef number = (CFNumberRef)CFDictionaryGetValue(
        (CFDictionaryRef)record, LC32ABRecordTypeKey);
    ABRecordType type = kABPersonType;
    if(number) CFNumberGetValue(number, kCFNumberSInt32Type, &type);
    return type;
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

bool ABRecordRemoveValue(ABRecordRef record, ABPropertyID property,
                         CFErrorRef *error) {
    if(error) *error = NULL;
    if(!record) return false;
    CFNumberRef key = LC32ABPropertyKey(property);
    if(!key) return false;
    CFDictionaryRemoveValue((CFMutableDictionaryRef)record, key);
    CFRelease(key);
    return true;
}

ABRecordRef ABAddressBookCopyDefaultSource(ABAddressBookRef addressBook) {
    (void)addressBook;
    ABRecordRef source = LC32ABDefaultSource();
    return source ? (ABRecordRef)CFRetain(source) : NULL;
}

ABRecordRef ABAddressBookGetSourceWithRecordID(
        ABAddressBookRef addressBook, ABRecordID sourceID) {
    (void)addressBook;
    ABRecordRef source = LC32ABDefaultSource();
    return source && ABRecordGetRecordID(source) == sourceID ? source : NULL;
}

CFArrayRef ABAddressBookCopyArrayOfAllSources(
        ABAddressBookRef addressBook) {
    (void)addressBook;
    ABRecordRef source = LC32ABDefaultSource();
    const void *values[1] = { source };
    return CFArrayCreate(kCFAllocatorDefault, values, source ? 1 : 0,
        &kCFTypeArrayCallBacks);
}

ABRecordRef ABGroupCreate(void) {
    return LC32ABCreateRecord(kABGroupType);
}

ABRecordRef ABGroupCreateInSource(ABRecordRef source) {
    ABRecordRef group = ABGroupCreate();
    if(group && source)
        CFDictionarySetValue((CFMutableDictionaryRef)group,
            LC32ABRecordSourceKey, source);
    return group;
}

ABRecordRef ABGroupCopySource(ABRecordRef group) {
    if(!group) return NULL;
    ABRecordRef source = (ABRecordRef)CFDictionaryGetValue(
        (CFDictionaryRef)group, LC32ABRecordSourceKey);
    if(!source) source = LC32ABDefaultSource();
    return source ? (ABRecordRef)CFRetain(source) : NULL;
}

static CFMutableArrayRef LC32ABGroupMembers(
        ABRecordRef group, Boolean create) {
    if(!group || ABRecordGetRecordType(group) != kABGroupType) return NULL;
    CFMutableArrayRef members = (CFMutableArrayRef)CFDictionaryGetValue(
        (CFDictionaryRef)group, LC32ABGroupMembersKey);
    if(!members && create) {
        members = CFArrayCreateMutable(kCFAllocatorDefault, 0,
            &kCFTypeArrayCallBacks);
        if(members) {
            CFDictionarySetValue((CFMutableDictionaryRef)group,
                LC32ABGroupMembersKey, members);
            CFRelease(members);
            members = (CFMutableArrayRef)CFDictionaryGetValue(
                (CFDictionaryRef)group, LC32ABGroupMembersKey);
        }
    }
    return members;
}

CFArrayRef ABGroupCopyArrayOfAllMembers(ABRecordRef group) {
    CFArrayRef members = LC32ABGroupMembers(group, false);
    return members ? CFArrayCreateCopy(kCFAllocatorDefault, members) :
        CFArrayCreate(kCFAllocatorDefault, NULL, 0,
            &kCFTypeArrayCallBacks);
}

CFArrayRef ABGroupCopyArrayOfAllMembersWithSortOrdering(
        ABRecordRef group, ABPersonSortOrdering sortOrdering) {
    (void)sortOrdering;
    return ABGroupCopyArrayOfAllMembers(group);
}

bool ABGroupAddMember(ABRecordRef group, ABRecordRef person,
                      CFErrorRef *error) {
    if(error) *error = NULL;
    if(!person) return false;
    CFMutableArrayRef members = LC32ABGroupMembers(group, true);
    if(!members) return false;
    CFIndex count = CFArrayGetCount(members);
    if(CFArrayGetFirstIndexOfValue(
            members, CFRangeMake(0, count), person) == kCFNotFound)
        CFArrayAppendValue(members, person);
    return true;
}

bool ABGroupRemoveMember(ABRecordRef group, ABRecordRef member,
                         CFErrorRef *error) {
    if(error) *error = NULL;
    CFMutableArrayRef members = LC32ABGroupMembers(group, false);
    if(!members || !member) return false;
    CFIndex index = CFArrayGetFirstIndexOfValue(members,
        CFRangeMake(0, CFArrayGetCount(members)), member);
    if(index == kCFNotFound) return false;
    CFArrayRemoveValueAtIndex(members, index);
    return true;
}

ABRecordRef ABAddressBookGetGroupWithRecordID(
        ABAddressBookRef addressBook, ABRecordID recordID) {
    return LC32ABGetRecordWithID(addressBook, kABGroupType, recordID);
}

CFIndex ABAddressBookGetGroupCount(ABAddressBookRef addressBook) {
    CFArrayRef groups = ABAddressBookCopyArrayOfAllGroups(addressBook);
    CFIndex count = groups ? CFArrayGetCount(groups) : 0;
    if(groups) CFRelease(groups);
    return count;
}

CFArrayRef ABAddressBookCopyArrayOfAllGroups(
        ABAddressBookRef addressBook) {
    return LC32ABCopyRecords(addressBook, kABGroupType, NULL);
}

CFArrayRef ABAddressBookCopyArrayOfAllGroupsInSource(
        ABAddressBookRef addressBook, ABRecordRef source) {
    return LC32ABCopyRecords(addressBook, kABGroupType, source);
}

ABMutableMultiValueRef ABMultiValueCreateMutable(ABPropertyType type) {
    (void)type;
    return (ABMutableMultiValueRef)CFArrayCreateMutable(kCFAllocatorDefault,
        0, &kCFTypeArrayCallBacks);
}

ABPropertyType ABMultiValueGetPropertyType(ABMultiValueRef multiValue) {
    (void)multiValue;
    /* The backing array is intentionally untyped. Most clients only use this
     * result as a defensive hint before enumerating values. */
    return kABInvalidPropertyType;
}

ABMutableMultiValueRef ABMultiValueCreateMutableCopy(
        ABMultiValueRef multiValue) {
    if(!multiValue) return NULL;
    return (ABMutableMultiValueRef)CFArrayCreateMutableCopy(
        kCFAllocatorDefault, 0, (CFArrayRef)multiValue);
}

static CFMutableDictionaryRef LC32ABCreateMultiValueEntry(
        CFTypeRef value, CFStringRef label,
        ABMultiValueIdentifier *outIdentifier) {
    if(!value) return NULL;
    CFMutableDictionaryRef entry = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    if(!entry) return NULL;
    CFDictionarySetValue(entry, LC32ABMultiValueValueKey, value);
    if(label) CFDictionarySetValue(
        entry, LC32ABMultiValueLabelKey, label);

    ABMultiValueIdentifier identifier = __atomic_fetch_add(
        &LC32ABNextMultiValueIdentifier, 1, __ATOMIC_RELAXED);
    CFNumberRef number = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt32Type, &identifier);
    if(number) {
        CFDictionarySetValue(
            entry, LC32ABMultiValueIdentifierKey, number);
        CFRelease(number);
    }
    if(outIdentifier) *outIdentifier = identifier;
    return entry;
}

bool ABMultiValueAddValueAndLabel(ABMutableMultiValueRef multiValue,
                                  CFTypeRef value, CFStringRef label,
                                  ABMultiValueIdentifier *outIdentifier) {
    if(!multiValue || !value) return false;
    CFMutableDictionaryRef entry = LC32ABCreateMultiValueEntry(
        value, label, outIdentifier);
    if(!entry) return false;
    CFArrayAppendValue((CFMutableArrayRef)multiValue, entry);
    CFRelease(entry);
    return true;
}

bool ABMultiValueInsertValueAndLabelAtIndex(
        ABMutableMultiValueRef multiValue, CFTypeRef value,
        CFStringRef label, CFIndex index,
        ABMultiValueIdentifier *outIdentifier) {
    if(!multiValue || !value || index < 0 ||
            index > CFArrayGetCount((CFArrayRef)multiValue))
        return false;
    CFMutableDictionaryRef entry = LC32ABCreateMultiValueEntry(
        value, label, outIdentifier);
    if(!entry) return false;
    CFArrayInsertValueAtIndex(
        (CFMutableArrayRef)multiValue, index, entry);
    CFRelease(entry);
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

ABMultiValueIdentifier ABMultiValueGetIdentifierAtIndex(
        ABMultiValueRef multiValue, CFIndex index) {
    CFDictionaryRef entry = LC32ABMultiValueEntry(multiValue, index);
    if(!entry) return kABMultiValueInvalidIdentifier;
    CFNumberRef number = (CFNumberRef)CFDictionaryGetValue(
        entry, LC32ABMultiValueIdentifierKey);
    ABMultiValueIdentifier identifier = kABMultiValueInvalidIdentifier;
    if(number) CFNumberGetValue(
        number, kCFNumberSInt32Type, &identifier);
    return identifier;
}

CFIndex ABMultiValueGetIndexForIdentifier(
        ABMultiValueRef multiValue, ABMultiValueIdentifier identifier) {
    CFIndex count = ABMultiValueGetCount(multiValue);
    for(CFIndex index = 0; index < count; index++) {
        if(ABMultiValueGetIdentifierAtIndex(multiValue, index) == identifier)
            return index;
    }
    return kCFNotFound;
}

CFIndex ABMultiValueGetFirstIndexOfValue(
        ABMultiValueRef multiValue, CFTypeRef value) {
    if(!value) return kCFNotFound;
    CFIndex count = ABMultiValueGetCount(multiValue);
    for(CFIndex index = 0; index < count; index++) {
        CFTypeRef candidate = ABMultiValueCopyValueAtIndex(
            multiValue, index);
        Boolean equal = candidate &&
            (candidate == value || CFEqual(candidate, value));
        if(candidate) CFRelease(candidate);
        if(equal) return index;
    }
    return kCFNotFound;
}

bool ABMultiValueRemoveValueAndLabelAtIndex(
        ABMutableMultiValueRef multiValue, CFIndex index) {
    if(!multiValue || index < 0 ||
            index >= CFArrayGetCount((CFArrayRef)multiValue))
        return false;
    CFArrayRemoveValueAtIndex((CFMutableArrayRef)multiValue, index);
    return true;
}

bool ABMultiValueReplaceValueAtIndex(
        ABMutableMultiValueRef multiValue, CFTypeRef value,
        CFIndex index) {
    CFMutableDictionaryRef entry = (CFMutableDictionaryRef)
        LC32ABMultiValueEntry(multiValue, index);
    if(!entry || !value) return false;
    CFDictionarySetValue(entry, LC32ABMultiValueValueKey, value);
    return true;
}

bool ABMultiValueReplaceLabelAtIndex(
        ABMutableMultiValueRef multiValue, CFStringRef label,
        CFIndex index) {
    CFMutableDictionaryRef entry = (CFMutableDictionaryRef)
        LC32ABMultiValueEntry(multiValue, index);
    if(!entry) return false;
    if(label)
        CFDictionarySetValue(entry, LC32ABMultiValueLabelKey, label);
    else
        CFDictionaryRemoveValue(entry, LC32ABMultiValueLabelKey);
    return true;
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

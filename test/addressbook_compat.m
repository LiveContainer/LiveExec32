#import <AddressBook/AddressBook.h>
#import <CoreFoundation/CoreFoundation.h>

#include <stdio.h>

static int failures;

static void check(const char *name, bool condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static void externalChangeCallback(ABAddressBookRef addressBook,
                                   CFDictionaryRef info,
                                   void *context) {
    (void)addressBook;
    (void)info;
    (void)context;
    ++failures;
}

int main(void) {
    ABAddressBookRef addressBook = ABAddressBookCreate();
    ABRecordRef first = ABPersonCreate();
    ABRecordRef second = ABPersonCreate();

    const ABRecordID firstID = ABRecordGetRecordID(first);
    const ABRecordID secondID = ABRecordGetRecordID(second);
    check("addressbook-record-id", firstID != kABRecordInvalidID &&
        secondID != kABRecordInvalidID && firstID != secondID &&
        ABRecordGetRecordID(first) == firstID);

    check("addressbook-name-format",
        ABPersonGetCompositeNameFormat() ==
            kABPersonCompositeNameFormatFirstNameFirst &&
        ABPersonGetSortOrdering() == kABPersonSortByFirstName);

    int32_t personKind = -1;
    int32_t organizationKind = -1;
    check("addressbook-kind-constants",
        CFNumberGetValue(kABPersonKindPerson, kCFNumberSInt32Type,
            &personKind) && personKind == 0 &&
        CFNumberGetValue(kABPersonKindOrganization,
            kCFNumberSInt32Type, &organizationKind) &&
        organizationKind == 1);
    check("addressbook-authorization",
        ABAddressBookGetAuthorizationStatus() ==
            kABAuthorizationStatusAuthorized);

    check("addressbook-set-first-name", ABRecordSetValue(first,
        kABPersonFirstNameProperty, CFSTR("Ada"), NULL));
    check("addressbook-set-middle-name", ABRecordSetValue(first,
        kABPersonMiddleNameProperty, CFSTR("M"), NULL));
    check("addressbook-set-last-name", ABRecordSetValue(first,
        kABPersonLastNameProperty, CFSTR("Lovelace"), NULL));

    CFStringRef compositeName = ABRecordCopyCompositeName(first);
    check("addressbook-composite-name", compositeName &&
        CFEqual(compositeName, CFSTR("Ada M Lovelace")));
    if(compositeName) CFRelease(compositeName);

    CFStringRef localizedLabel = ABAddressBookCopyLocalizedLabel(
        kABHomeLabel);
    check("addressbook-localized-label", localizedLabel &&
        CFEqual(localizedLabel, kABHomeLabel));
    if(localizedLabel) CFRelease(localizedLabel);

    ABAddressBookRegisterExternalChangeCallback(addressBook,
        externalChangeCallback, &failures);
    ABAddressBookUnregisterExternalChangeCallback(addressBook,
        externalChangeCallback, &failures);

    check("addressbook-add-record",
        ABAddressBookAddRecord(addressBook, first, NULL));
    CFArrayRef people = ABAddressBookCopyArrayOfAllPeople(addressBook);
    check("addressbook-copy-people",
        people && CFArrayGetCount(people) == 1 &&
        CFArrayGetValueAtIndex(people, 0) == first);

    check("addressbook-find-record",
        ABAddressBookGetPersonCount(addressBook) == 1 &&
        ABAddressBookGetPersonWithRecordID(addressBook, firstID) == first);
    CFArrayRef matches = ABAddressBookCopyPeopleWithName(
        addressBook, CFSTR("lovelace"));
    check("addressbook-name-search",
        matches && CFArrayGetCount(matches) == 1 &&
        CFArrayGetValueAtIndex(matches, 0) == first);
    if(matches) CFRelease(matches);

    ABRecordRef source = ABAddressBookCopyDefaultSource(addressBook);
    ABRecordRef personSource = ABPersonCopySource(first);
    check("addressbook-default-source", source && personSource &&
        ABRecordGetRecordType(source) == kABSourceType &&
        CFEqual(source, personSource));
    if(personSource) CFRelease(personSource);

    ABRecordRef group = ABGroupCreateInSource(source);
    check("addressbook-group-create", group &&
        ABRecordGetRecordType(group) == kABGroupType &&
        ABAddressBookAddRecord(addressBook, group, NULL));
    check("addressbook-group-member",
        ABGroupAddMember(group, first, NULL));
    CFArrayRef members = ABGroupCopyArrayOfAllMembers(group);
    check("addressbook-copy-group-members",
        members && CFArrayGetCount(members) == 1 &&
        CFArrayGetValueAtIndex(members, 0) == first &&
        ABAddressBookGetGroupCount(addressBook) == 1);
    if(members) CFRelease(members);

    ABMutableMultiValueRef multiValue = ABMultiValueCreateMutable(
        kABMultiStringPropertyType);
    ABMultiValueIdentifier firstValueID = kABMultiValueInvalidIdentifier;
    ABMultiValueIdentifier insertedValueID = kABMultiValueInvalidIdentifier;
    check("addressbook-multivalue-add", ABMultiValueAddValueAndLabel(
        multiValue, CFSTR("one"), kABHomeLabel, &firstValueID));
    check("addressbook-multivalue-insert",
        ABMultiValueInsertValueAndLabelAtIndex(multiValue,
            CFSTR("zero"), kABWorkLabel, 0, &insertedValueID) &&
        firstValueID != insertedValueID &&
        ABMultiValueGetIndexForIdentifier(multiValue, firstValueID) == 1 &&
        ABMultiValueGetIdentifierAtIndex(multiValue, 0) == insertedValueID);
    check("addressbook-multivalue-find",
        ABMultiValueGetFirstIndexOfValue(multiValue, CFSTR("one")) == 1);
    check("addressbook-multivalue-replace-remove",
        ABMultiValueReplaceValueAtIndex(multiValue, CFSTR("updated"), 1) &&
        ABMultiValueRemoveValueAndLabelAtIndex(multiValue, 0) &&
        ABMultiValueGetCount(multiValue) == 1);
    if(multiValue) CFRelease(multiValue);

    const UInt8 imageBytes[] = { 1, 2, 3, 4 };
    CFDataRef image = CFDataCreate(
        kCFAllocatorDefault, imageBytes, sizeof(imageBytes));
    check("addressbook-image", ABPersonSetImageData(first, image, NULL) &&
        ABPersonHasImageData(first));
    CFDataRef copiedImage = ABPersonCopyImageData(first);
    check("addressbook-copy-image", copiedImage &&
        CFDataGetLength(copiedImage) == sizeof(imageBytes));
    if(copiedImage) CFRelease(copiedImage);
    check("addressbook-remove-image",
        ABPersonRemoveImageData(first, NULL) && !ABPersonHasImageData(first));
    if(image) CFRelease(image);

    check("addressbook-remove-record",
        ABAddressBookRemoveRecord(addressBook, first, NULL) &&
        ABAddressBookGetPersonCount(addressBook) == 0);

    if(people) CFRelease(people);
    if(group) CFRelease(group);
    if(source) CFRelease(source);
    if(second) CFRelease(second);
    if(first) CFRelease(first);
    if(addressBook) CFRelease(addressBook);
    return failures != 0;
}

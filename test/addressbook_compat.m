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

    if(people) CFRelease(people);
    if(second) CFRelease(second);
    if(first) CFRelease(first);
    if(addressBook) CFRelease(addressBook);
    return failures != 0;
}

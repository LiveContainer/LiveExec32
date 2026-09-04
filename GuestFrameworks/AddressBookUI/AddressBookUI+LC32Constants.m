#import <AddressBookUI/AddressBookUI.h>
#import <Foundation/Foundation+LC32.h>

/*
 * Keep guest exports at stable ARM32 addresses while binding each object to
 * the native framework constant. This preserves native key/identifier
 * identity when a guest collection crosses the bridge.
 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

LC32_CONST_STR_DECL(NSString *const ABPersonBirthdayProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonDatesProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonDepartmentNameProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonEmailAddressesProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonFamilyNameProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonGivenNameProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonInstantMessageAddressesProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonJobTitleProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonMiddleNameProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonNamePrefixProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonNameSuffixProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonNicknameProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonNoteProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonOrganizationNameProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonPhoneNumbersProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonPhoneticFamilyNameProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonPhoneticGivenNameProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonPhoneticMiddleNameProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonPostalAddressesProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonPreviousFamilyNameProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonRelatedNamesProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonSocialProfilesProperty)
LC32_CONST_STR_DECL(NSString *const ABPersonUrlAddressesProperty)

__attribute__((constructor)) static void LC32InitializeAddressBookUIConstants(void) {
    LC32LoadHostFramework("AddressBookUI");
    LC32_CONST_STR_INIT(ABPersonBirthdayProperty);
    LC32_CONST_STR_INIT(ABPersonDatesProperty);
    LC32_CONST_STR_INIT(ABPersonDepartmentNameProperty);
    LC32_CONST_STR_INIT(ABPersonEmailAddressesProperty);
    LC32_CONST_STR_INIT(ABPersonFamilyNameProperty);
    LC32_CONST_STR_INIT(ABPersonGivenNameProperty);
    LC32_CONST_STR_INIT(ABPersonInstantMessageAddressesProperty);
    LC32_CONST_STR_INIT(ABPersonJobTitleProperty);
    LC32_CONST_STR_INIT(ABPersonMiddleNameProperty);
    LC32_CONST_STR_INIT(ABPersonNamePrefixProperty);
    LC32_CONST_STR_INIT(ABPersonNameSuffixProperty);
    LC32_CONST_STR_INIT(ABPersonNicknameProperty);
    LC32_CONST_STR_INIT(ABPersonNoteProperty);
    LC32_CONST_STR_INIT(ABPersonOrganizationNameProperty);
    LC32_CONST_STR_INIT(ABPersonPhoneNumbersProperty);
    LC32_CONST_STR_INIT(ABPersonPhoneticFamilyNameProperty);
    LC32_CONST_STR_INIT(ABPersonPhoneticGivenNameProperty);
    LC32_CONST_STR_INIT(ABPersonPhoneticMiddleNameProperty);
    LC32_CONST_STR_INIT(ABPersonPostalAddressesProperty);
    LC32_CONST_STR_INIT(ABPersonPreviousFamilyNameProperty);
    LC32_CONST_STR_INIT(ABPersonRelatedNamesProperty);
    LC32_CONST_STR_INIT(ABPersonSocialProfilesProperty);
    LC32_CONST_STR_INIT(ABPersonUrlAddressesProperty);
}

#pragma clang diagnostic pop

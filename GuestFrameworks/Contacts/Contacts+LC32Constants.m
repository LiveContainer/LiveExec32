#import <Contacts/Contacts.h>
#import <Foundation/Foundation+LC32.h>

/*
 * Keep guest exports at stable ARM32 addresses while binding each object to
 * the native framework constant. This preserves native key/identifier
 * identity when a guest collection crosses the bridge.
 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

LC32_CONST_STR_DECL(NSString *const CNContactBirthdayKey)
LC32_CONST_STR_DECL(NSString *const CNContactDatesKey)
LC32_CONST_STR_DECL(NSString *const CNContactDepartmentNameKey)
LC32_CONST_STR_DECL(NSString *const CNContactEmailAddressesKey)
LC32_CONST_STR_DECL(NSString *const CNContactFamilyNameKey)
LC32_CONST_STR_DECL(NSString *const CNContactGivenNameKey)
LC32_CONST_STR_DECL(NSString *const CNContactIdentifierKey)
LC32_CONST_STR_DECL(NSString *const CNContactImageDataAvailableKey)
LC32_CONST_STR_DECL(NSString *const CNContactImageDataKey)
LC32_CONST_STR_DECL(NSString *const CNContactInstantMessageAddressesKey)
LC32_CONST_STR_DECL(NSString *const CNContactJobTitleKey)
LC32_CONST_STR_DECL(NSString *const CNContactMiddleNameKey)
LC32_CONST_STR_DECL(NSString *const CNContactNamePrefixKey)
LC32_CONST_STR_DECL(NSString *const CNContactNameSuffixKey)
LC32_CONST_STR_DECL(NSString *const CNContactNicknameKey)
LC32_CONST_STR_DECL(NSString *const CNContactNonGregorianBirthdayKey)
LC32_CONST_STR_DECL(NSString *const CNContactNoteKey)
LC32_CONST_STR_DECL(NSString *const CNContactOrganizationNameKey)
LC32_CONST_STR_DECL(NSString *const CNContactPhoneNumbersKey)
LC32_CONST_STR_DECL(NSString *const CNContactPhoneticFamilyNameKey)
LC32_CONST_STR_DECL(NSString *const CNContactPhoneticGivenNameKey)
LC32_CONST_STR_DECL(NSString *const CNContactPhoneticMiddleNameKey)
LC32_CONST_STR_DECL(NSString *const CNContactPhoneticOrganizationNameKey)
LC32_CONST_STR_DECL(NSString *const CNContactPostalAddressesKey)
LC32_CONST_STR_DECL(NSString *const CNContactPreviousFamilyNameKey)
LC32_CONST_STR_DECL(NSString *const CNContactPropertyAttribute)
LC32_CONST_STR_DECL(NSString *const CNContactPropertyNotFetchedExceptionName)
LC32_CONST_STR_DECL(NSString *const CNContactRelationsKey)
LC32_CONST_STR_DECL(NSString *const CNContactSocialProfilesKey)
LC32_CONST_STR_DECL(NSString *const CNContactStoreDidChangeNotification)
LC32_CONST_STR_DECL(NSString *const CNContactThumbnailImageDataKey)
LC32_CONST_STR_DECL(NSString *const CNContactTypeKey)
LC32_CONST_STR_DECL(NSString *const CNContactUrlAddressesKey)
LC32_CONST_STR_DECL(NSString *const CNContainerIdentifierKey)
LC32_CONST_STR_DECL(NSString *const CNContainerNameKey)
LC32_CONST_STR_DECL(NSString *const CNContainerTypeKey)
LC32_CONST_STR_DECL(NSString *const CNErrorDomain)
LC32_CONST_STR_DECL(NSString *const CNErrorUserInfoAffectedRecordIdentifiersKey)
LC32_CONST_STR_DECL(NSString *const CNErrorUserInfoAffectedRecordsKey)
LC32_CONST_STR_DECL(NSString *const CNErrorUserInfoKeyPathsKey)
LC32_CONST_STR_DECL(NSString *const CNErrorUserInfoValidationErrorsKey)
LC32_CONST_STR_DECL(NSString *const CNGroupIdentifierKey)
LC32_CONST_STR_DECL(NSString *const CNGroupNameKey)
LC32_CONST_STR_DECL(NSString *const CNInstantMessageAddressServiceKey)
LC32_CONST_STR_DECL(NSString *const CNInstantMessageAddressUsernameKey)
LC32_CONST_STR_DECL(NSString *const CNInstantMessageServiceAIM)
LC32_CONST_STR_DECL(NSString *const CNInstantMessageServiceFacebook)
LC32_CONST_STR_DECL(NSString *const CNInstantMessageServiceGaduGadu)
LC32_CONST_STR_DECL(NSString *const CNInstantMessageServiceGoogleTalk)
LC32_CONST_STR_DECL(NSString *const CNInstantMessageServiceICQ)
LC32_CONST_STR_DECL(NSString *const CNInstantMessageServiceJabber)
LC32_CONST_STR_DECL(NSString *const CNInstantMessageServiceMSN)
LC32_CONST_STR_DECL(NSString *const CNInstantMessageServiceQQ)
LC32_CONST_STR_DECL(NSString *const CNInstantMessageServiceSkype)
LC32_CONST_STR_DECL(NSString *const CNInstantMessageServiceYahoo)
LC32_CONST_STR_DECL(NSString *const CNLabelContactRelationAssistant)
LC32_CONST_STR_DECL(NSString *const CNLabelContactRelationBrother)
LC32_CONST_STR_DECL(NSString *const CNLabelContactRelationChild)
LC32_CONST_STR_DECL(NSString *const CNLabelContactRelationFather)
LC32_CONST_STR_DECL(NSString *const CNLabelContactRelationFriend)
LC32_CONST_STR_DECL(NSString *const CNLabelContactRelationManager)
LC32_CONST_STR_DECL(NSString *const CNLabelContactRelationMother)
LC32_CONST_STR_DECL(NSString *const CNLabelContactRelationParent)
LC32_CONST_STR_DECL(NSString *const CNLabelContactRelationPartner)
LC32_CONST_STR_DECL(NSString *const CNLabelContactRelationSister)
LC32_CONST_STR_DECL(NSString *const CNLabelContactRelationSpouse)
LC32_CONST_STR_DECL(NSString *const CNLabelDateAnniversary)
LC32_CONST_STR_DECL(NSString *const CNLabelEmailiCloud)
LC32_CONST_STR_DECL(NSString *const CNLabelHome)
LC32_CONST_STR_DECL(NSString *const CNLabelOther)
LC32_CONST_STR_DECL(NSString *const CNLabelPhoneNumberHomeFax)
LC32_CONST_STR_DECL(NSString *const CNLabelPhoneNumberMain)
LC32_CONST_STR_DECL(NSString *const CNLabelPhoneNumberMobile)
LC32_CONST_STR_DECL(NSString *const CNLabelPhoneNumberOtherFax)
LC32_CONST_STR_DECL(NSString *const CNLabelPhoneNumberPager)
LC32_CONST_STR_DECL(NSString *const CNLabelPhoneNumberWorkFax)
LC32_CONST_STR_DECL(NSString *const CNLabelPhoneNumberiPhone)
LC32_CONST_STR_DECL(NSString *const CNLabelURLAddressHomePage)
LC32_CONST_STR_DECL(NSString *const CNLabelWork)
LC32_CONST_STR_DECL(NSString *const CNPostalAddressCityKey)
LC32_CONST_STR_DECL(NSString *const CNPostalAddressCountryKey)
LC32_CONST_STR_DECL(NSString *const CNPostalAddressISOCountryCodeKey)
LC32_CONST_STR_DECL(NSString *const CNPostalAddressLocalizedPropertyNameAttribute)
LC32_CONST_STR_DECL(NSString *const CNPostalAddressPostalCodeKey)
LC32_CONST_STR_DECL(NSString *const CNPostalAddressPropertyAttribute)
LC32_CONST_STR_DECL(NSString *const CNPostalAddressStateKey)
LC32_CONST_STR_DECL(NSString *const CNPostalAddressStreetKey)
LC32_CONST_STR_DECL(NSString *const CNPostalAddressSubAdministrativeAreaKey)
LC32_CONST_STR_DECL(NSString *const CNPostalAddressSubLocalityKey)
LC32_CONST_STR_DECL(NSString *const CNSocialProfileServiceFacebook)
LC32_CONST_STR_DECL(NSString *const CNSocialProfileServiceFlickr)
LC32_CONST_STR_DECL(NSString *const CNSocialProfileServiceGameCenter)
LC32_CONST_STR_DECL(NSString *const CNSocialProfileServiceKey)
LC32_CONST_STR_DECL(NSString *const CNSocialProfileServiceLinkedIn)
LC32_CONST_STR_DECL(NSString *const CNSocialProfileServiceMySpace)
LC32_CONST_STR_DECL(NSString *const CNSocialProfileServiceSinaWeibo)
LC32_CONST_STR_DECL(NSString *const CNSocialProfileServiceTencentWeibo)
LC32_CONST_STR_DECL(NSString *const CNSocialProfileServiceTwitter)
LC32_CONST_STR_DECL(NSString *const CNSocialProfileServiceYelp)
LC32_CONST_STR_DECL(NSString *const CNSocialProfileURLStringKey)
LC32_CONST_STR_DECL(NSString *const CNSocialProfileUserIdentifierKey)
LC32_CONST_STR_DECL(NSString *const CNSocialProfileUsernameKey)

__attribute__((constructor)) static void LC32InitializeContactsConstants(void) {
    LC32LoadHostFramework("Contacts");
    LC32_CONST_STR_INIT(CNContactBirthdayKey);
    LC32_CONST_STR_INIT(CNContactDatesKey);
    LC32_CONST_STR_INIT(CNContactDepartmentNameKey);
    LC32_CONST_STR_INIT(CNContactEmailAddressesKey);
    LC32_CONST_STR_INIT(CNContactFamilyNameKey);
    LC32_CONST_STR_INIT(CNContactGivenNameKey);
    LC32_CONST_STR_INIT(CNContactIdentifierKey);
    LC32_CONST_STR_INIT(CNContactImageDataAvailableKey);
    LC32_CONST_STR_INIT(CNContactImageDataKey);
    LC32_CONST_STR_INIT(CNContactInstantMessageAddressesKey);
    LC32_CONST_STR_INIT(CNContactJobTitleKey);
    LC32_CONST_STR_INIT(CNContactMiddleNameKey);
    LC32_CONST_STR_INIT(CNContactNamePrefixKey);
    LC32_CONST_STR_INIT(CNContactNameSuffixKey);
    LC32_CONST_STR_INIT(CNContactNicknameKey);
    LC32_CONST_STR_INIT(CNContactNonGregorianBirthdayKey);
    LC32_CONST_STR_INIT(CNContactNoteKey);
    LC32_CONST_STR_INIT(CNContactOrganizationNameKey);
    LC32_CONST_STR_INIT(CNContactPhoneNumbersKey);
    LC32_CONST_STR_INIT(CNContactPhoneticFamilyNameKey);
    LC32_CONST_STR_INIT(CNContactPhoneticGivenNameKey);
    LC32_CONST_STR_INIT(CNContactPhoneticMiddleNameKey);
    LC32_CONST_STR_INIT(CNContactPhoneticOrganizationNameKey);
    LC32_CONST_STR_INIT(CNContactPostalAddressesKey);
    LC32_CONST_STR_INIT(CNContactPreviousFamilyNameKey);
    LC32_CONST_STR_INIT(CNContactPropertyAttribute);
    LC32_CONST_STR_INIT(CNContactPropertyNotFetchedExceptionName);
    LC32_CONST_STR_INIT(CNContactRelationsKey);
    LC32_CONST_STR_INIT(CNContactSocialProfilesKey);
    LC32_CONST_STR_INIT(CNContactStoreDidChangeNotification);
    LC32_CONST_STR_INIT(CNContactThumbnailImageDataKey);
    LC32_CONST_STR_INIT(CNContactTypeKey);
    LC32_CONST_STR_INIT(CNContactUrlAddressesKey);
    LC32_CONST_STR_INIT(CNContainerIdentifierKey);
    LC32_CONST_STR_INIT(CNContainerNameKey);
    LC32_CONST_STR_INIT(CNContainerTypeKey);
    LC32_CONST_STR_INIT(CNErrorDomain);
    LC32_CONST_STR_INIT(CNErrorUserInfoAffectedRecordIdentifiersKey);
    LC32_CONST_STR_INIT(CNErrorUserInfoAffectedRecordsKey);
    LC32_CONST_STR_INIT(CNErrorUserInfoKeyPathsKey);
    LC32_CONST_STR_INIT(CNErrorUserInfoValidationErrorsKey);
    LC32_CONST_STR_INIT(CNGroupIdentifierKey);
    LC32_CONST_STR_INIT(CNGroupNameKey);
    LC32_CONST_STR_INIT(CNInstantMessageAddressServiceKey);
    LC32_CONST_STR_INIT(CNInstantMessageAddressUsernameKey);
    LC32_CONST_STR_INIT(CNInstantMessageServiceAIM);
    LC32_CONST_STR_INIT(CNInstantMessageServiceFacebook);
    LC32_CONST_STR_INIT(CNInstantMessageServiceGaduGadu);
    LC32_CONST_STR_INIT(CNInstantMessageServiceGoogleTalk);
    LC32_CONST_STR_INIT(CNInstantMessageServiceICQ);
    LC32_CONST_STR_INIT(CNInstantMessageServiceJabber);
    LC32_CONST_STR_INIT(CNInstantMessageServiceMSN);
    LC32_CONST_STR_INIT(CNInstantMessageServiceQQ);
    LC32_CONST_STR_INIT(CNInstantMessageServiceSkype);
    LC32_CONST_STR_INIT(CNInstantMessageServiceYahoo);
    LC32_CONST_STR_INIT(CNLabelContactRelationAssistant);
    LC32_CONST_STR_INIT(CNLabelContactRelationBrother);
    LC32_CONST_STR_INIT(CNLabelContactRelationChild);
    LC32_CONST_STR_INIT(CNLabelContactRelationFather);
    LC32_CONST_STR_INIT(CNLabelContactRelationFriend);
    LC32_CONST_STR_INIT(CNLabelContactRelationManager);
    LC32_CONST_STR_INIT(CNLabelContactRelationMother);
    LC32_CONST_STR_INIT(CNLabelContactRelationParent);
    LC32_CONST_STR_INIT(CNLabelContactRelationPartner);
    LC32_CONST_STR_INIT(CNLabelContactRelationSister);
    LC32_CONST_STR_INIT(CNLabelContactRelationSpouse);
    LC32_CONST_STR_INIT(CNLabelDateAnniversary);
    LC32_CONST_STR_INIT(CNLabelEmailiCloud);
    LC32_CONST_STR_INIT(CNLabelHome);
    LC32_CONST_STR_INIT(CNLabelOther);
    LC32_CONST_STR_INIT(CNLabelPhoneNumberHomeFax);
    LC32_CONST_STR_INIT(CNLabelPhoneNumberMain);
    LC32_CONST_STR_INIT(CNLabelPhoneNumberMobile);
    LC32_CONST_STR_INIT(CNLabelPhoneNumberOtherFax);
    LC32_CONST_STR_INIT(CNLabelPhoneNumberPager);
    LC32_CONST_STR_INIT(CNLabelPhoneNumberWorkFax);
    LC32_CONST_STR_INIT(CNLabelPhoneNumberiPhone);
    LC32_CONST_STR_INIT(CNLabelURLAddressHomePage);
    LC32_CONST_STR_INIT(CNLabelWork);
    LC32_CONST_STR_INIT(CNPostalAddressCityKey);
    LC32_CONST_STR_INIT(CNPostalAddressCountryKey);
    LC32_CONST_STR_INIT(CNPostalAddressISOCountryCodeKey);
    LC32_CONST_STR_INIT(CNPostalAddressLocalizedPropertyNameAttribute);
    LC32_CONST_STR_INIT(CNPostalAddressPostalCodeKey);
    LC32_CONST_STR_INIT(CNPostalAddressPropertyAttribute);
    LC32_CONST_STR_INIT(CNPostalAddressStateKey);
    LC32_CONST_STR_INIT(CNPostalAddressStreetKey);
    LC32_CONST_STR_INIT(CNPostalAddressSubAdministrativeAreaKey);
    LC32_CONST_STR_INIT(CNPostalAddressSubLocalityKey);
    LC32_CONST_STR_INIT(CNSocialProfileServiceFacebook);
    LC32_CONST_STR_INIT(CNSocialProfileServiceFlickr);
    LC32_CONST_STR_INIT(CNSocialProfileServiceGameCenter);
    LC32_CONST_STR_INIT(CNSocialProfileServiceKey);
    LC32_CONST_STR_INIT(CNSocialProfileServiceLinkedIn);
    LC32_CONST_STR_INIT(CNSocialProfileServiceMySpace);
    LC32_CONST_STR_INIT(CNSocialProfileServiceSinaWeibo);
    LC32_CONST_STR_INIT(CNSocialProfileServiceTencentWeibo);
    LC32_CONST_STR_INIT(CNSocialProfileServiceTwitter);
    LC32_CONST_STR_INIT(CNSocialProfileServiceYelp);
    LC32_CONST_STR_INIT(CNSocialProfileURLStringKey);
    LC32_CONST_STR_INIT(CNSocialProfileUserIdentifierKey);
    LC32_CONST_STR_INIT(CNSocialProfileUsernameKey);
}

#pragma clang diagnostic pop

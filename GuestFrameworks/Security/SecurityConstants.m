// Public Security.framework constants exported by iOS 10.3.
//
// Security dictionary keys use compact wire spellings rather than their C
// symbol names.  Keep the CFStrings in guest memory: legacy binaries bind to
// the address of each variable and dereference it before calling SecItem.

#import <Security/Security.h>

#define LC32_SECURITY_STRING(name, value) \
    const CFStringRef name = CFSTR(value)

LC32_SECURITY_STRING(kSecAttrAccessControl, "accc");
LC32_SECURITY_STRING(kSecAttrAccessGroupToken, "com.apple.token");
LC32_SECURITY_STRING(kSecAttrAuthenticationType, "atyp");
LC32_SECURITY_STRING(kSecAttrAuthenticationTypeDPA, "dpaa");
LC32_SECURITY_STRING(kSecAttrAuthenticationTypeDefault, "dflt");
LC32_SECURITY_STRING(kSecAttrAuthenticationTypeHTMLForm, "form");
LC32_SECURITY_STRING(kSecAttrAuthenticationTypeHTTPBasic, "http");
LC32_SECURITY_STRING(kSecAttrAuthenticationTypeHTTPDigest, "httd");
LC32_SECURITY_STRING(kSecAttrAuthenticationTypeMSN, "msna");
LC32_SECURITY_STRING(kSecAttrAuthenticationTypeNTLM, "ntlm");
LC32_SECURITY_STRING(kSecAttrAuthenticationTypeRPA, "rpaa");
LC32_SECURITY_STRING(kSecAttrCertificateEncoding, "cenc");
LC32_SECURITY_STRING(kSecAttrCertificateType, "ctyp");
LC32_SECURITY_STRING(kSecAttrCreator, "crtr");
LC32_SECURITY_STRING(kSecAttrIsExtractable, "extr");
LC32_SECURITY_STRING(kSecAttrIsInvisible, "invi");
LC32_SECURITY_STRING(kSecAttrIsNegative, "nega");
LC32_SECURITY_STRING(kSecAttrIsSensitive, "sens");
LC32_SECURITY_STRING(kSecAttrIssuer, "issr");
LC32_SECURITY_STRING(kSecAttrKeyTypeEC, "73");
LC32_SECURITY_STRING(kSecAttrKeyTypeECSECPrimeRandom, "73");
LC32_SECURITY_STRING(kSecAttrPath, "path");
LC32_SECURITY_STRING(kSecAttrPort, "port");
LC32_SECURITY_STRING(kSecAttrProtocol, "ptcl");
LC32_SECURITY_STRING(kSecAttrProtocolAFP, "afp ");
LC32_SECURITY_STRING(kSecAttrProtocolAppleTalk, "atlk");
LC32_SECURITY_STRING(kSecAttrProtocolDAAP, "daap");
LC32_SECURITY_STRING(kSecAttrProtocolEPPC, "eppc");
LC32_SECURITY_STRING(kSecAttrProtocolFTP, "ftp ");
LC32_SECURITY_STRING(kSecAttrProtocolFTPAccount, "ftpa");
LC32_SECURITY_STRING(kSecAttrProtocolFTPProxy, "ftpx");
LC32_SECURITY_STRING(kSecAttrProtocolFTPS, "ftps");
LC32_SECURITY_STRING(kSecAttrProtocolHTTP, "http");
LC32_SECURITY_STRING(kSecAttrProtocolHTTPProxy, "htpx");
LC32_SECURITY_STRING(kSecAttrProtocolHTTPS, "htps");
LC32_SECURITY_STRING(kSecAttrProtocolHTTPSProxy, "htsx");
LC32_SECURITY_STRING(kSecAttrProtocolIMAP, "imap");
LC32_SECURITY_STRING(kSecAttrProtocolIMAPS, "imps");
LC32_SECURITY_STRING(kSecAttrProtocolIPP, "ipp ");
LC32_SECURITY_STRING(kSecAttrProtocolIRC, "irc ");
LC32_SECURITY_STRING(kSecAttrProtocolIRCS, "ircs");
LC32_SECURITY_STRING(kSecAttrProtocolLDAP, "ldap");
LC32_SECURITY_STRING(kSecAttrProtocolLDAPS, "ldps");
LC32_SECURITY_STRING(kSecAttrProtocolNNTP, "nntp");
LC32_SECURITY_STRING(kSecAttrProtocolNNTPS, "ntps");
LC32_SECURITY_STRING(kSecAttrProtocolPOP3, "pop3");
LC32_SECURITY_STRING(kSecAttrProtocolPOP3S, "pops");
LC32_SECURITY_STRING(kSecAttrProtocolRTSP, "rtsp");
LC32_SECURITY_STRING(kSecAttrProtocolRTSPProxy, "rtsx");
LC32_SECURITY_STRING(kSecAttrProtocolSMB, "smb ");
LC32_SECURITY_STRING(kSecAttrProtocolSMTP, "smtp");
LC32_SECURITY_STRING(kSecAttrProtocolSOCKS, "sox ");
LC32_SECURITY_STRING(kSecAttrProtocolSSH, "ssh ");
LC32_SECURITY_STRING(kSecAttrProtocolTelnet, "teln");
LC32_SECURITY_STRING(kSecAttrProtocolTelnetS, "tels");
LC32_SECURITY_STRING(kSecAttrPublicKeyHash, "pkhh");
LC32_SECURITY_STRING(kSecAttrSecurityDomain, "sdmn");
LC32_SECURITY_STRING(kSecAttrSerialNumber, "slnr");
LC32_SECURITY_STRING(kSecAttrServer, "srvr");
LC32_SECURITY_STRING(kSecAttrSubject, "subj");
LC32_SECURITY_STRING(kSecAttrSubjectKeyID, "skid");
LC32_SECURITY_STRING(kSecAttrSyncViewHint, "vwht");
LC32_SECURITY_STRING(kSecAttrTokenID, "tkid");
LC32_SECURITY_STRING(kSecAttrTokenIDSecureEnclave, "com.apple.setoken");
LC32_SECURITY_STRING(kSecAttrType, "type");

LC32_SECURITY_STRING(kSecImportExportPassphrase, "passphrase");
LC32_SECURITY_STRING(kSecImportItemCertChain, "chain");
LC32_SECURITY_STRING(kSecImportItemIdentity, "identity");
LC32_SECURITY_STRING(kSecImportItemKeyID, "keyid");
LC32_SECURITY_STRING(kSecImportItemLabel, "label");
LC32_SECURITY_STRING(kSecImportItemTrust, "trust");

LC32_SECURITY_STRING(kSecMatchCaseInsensitive, "m_CaseInsensitive");
LC32_SECURITY_STRING(kSecMatchEmailAddressIfPresent,
                     "m_EmailAddressIfPresent");
LC32_SECURITY_STRING(kSecMatchIssuers, "m_Issuers");
LC32_SECURITY_STRING(kSecMatchItemList, "m_ItemList");
LC32_SECURITY_STRING(kSecMatchPolicy, "m_Policy");
LC32_SECURITY_STRING(kSecMatchSearchList, "m_SearchList");
LC32_SECURITY_STRING(kSecMatchSubjectContains, "m_SubjectContains");
LC32_SECURITY_STRING(kSecMatchTrustedOnly, "m_TrustedOnly");
LC32_SECURITY_STRING(kSecMatchValidOnDate, "m_ValidOnDate");

LC32_SECURITY_STRING(kSecUseAuthenticationContext, "u_AuthCtx");
LC32_SECURITY_STRING(kSecUseAuthenticationUI, "u_AuthUI");
LC32_SECURITY_STRING(kSecUseAuthenticationUIAllow, "u_AuthUIA");
LC32_SECURITY_STRING(kSecUseAuthenticationUIFail, "u_AuthUIF");
LC32_SECURITY_STRING(kSecUseAuthenticationUISkip, "u_AuthUIS");
LC32_SECURITY_STRING(kSecUseItemList, "u_ItemList");

LC32_SECURITY_STRING(kSecPolicyAppleCodeSigning,
                     "1.2.840.113635.100.1.16");
LC32_SECURITY_STRING(kSecPolicyAppleEAP, "1.2.840.113635.100.1.9");
LC32_SECURITY_STRING(kSecPolicyAppleIDValidation,
                     "1.2.840.113635.100.1.18");
LC32_SECURITY_STRING(kSecPolicyAppleIPsec, "1.2.840.113635.100.1.11");
LC32_SECURITY_STRING(kSecPolicyApplePKINITClient,
                     "1.2.840.113635.100.1.14");
LC32_SECURITY_STRING(kSecPolicyApplePKINITServer,
                     "1.2.840.113635.100.1.15");
LC32_SECURITY_STRING(kSecPolicyApplePassbookSigning,
                     "1.2.840.113635.100.1.22");
LC32_SECURITY_STRING(kSecPolicyApplePayIssuerEncryption,
                     "1.2.840.113635.100.1.39");
LC32_SECURITY_STRING(kSecPolicyAppleRevocation,
                     "1.2.840.113635.100.1.21");
LC32_SECURITY_STRING(kSecPolicyAppleSMIME, "1.2.840.113635.100.1.8");
LC32_SECURITY_STRING(kSecPolicyAppleSSL, "1.2.840.113635.100.1.3");
LC32_SECURITY_STRING(kSecPolicyAppleTimeStamping,
                     "1.2.840.113635.100.1.20");
LC32_SECURITY_STRING(kSecPolicyAppleX509Basic,
                     "1.2.840.113635.100.1.2");
LC32_SECURITY_STRING(kSecPolicyClient, "SecPolicyClient");
LC32_SECURITY_STRING(kSecPolicyMacAppStoreReceipt,
                     "1.2.840.113635.100.1.19");
LC32_SECURITY_STRING(kSecPolicyName, "SecPolicyName");
LC32_SECURITY_STRING(kSecPolicyOid, "SecPolicyOid");
LC32_SECURITY_STRING(kSecPolicyRevocationFlags,
                     "SecPolicyRevocationFlags");
LC32_SECURITY_STRING(kSecPolicyTeamIdentifier,
                     "SecPolicyTeamIdentifier");

LC32_SECURITY_STRING(kSecPrivateKeyAttrs, "private");
LC32_SECURITY_STRING(kSecPublicKeyAttrs, "public");
LC32_SECURITY_STRING(kSecPropertyTypeError, "error");
LC32_SECURITY_STRING(kSecPropertyTypeTitle, "title");
LC32_SECURITY_STRING(kSecSharedPassword, "spwd");

LC32_SECURITY_STRING(kSecTrustCertificateTransparency,
                     "TrustCertificateTransparency");
LC32_SECURITY_STRING(kSecTrustCertificateTransparencyWhiteList,
                     "TrustCertificateTransparencyWhiteList");
LC32_SECURITY_STRING(kSecTrustEvaluationDate, "TrustEvaluationDate");
LC32_SECURITY_STRING(kSecTrustExtendedValidation,
                     "TrustExtendedValidation");
LC32_SECURITY_STRING(kSecTrustOrganizationName, "Organization");
LC32_SECURITY_STRING(kSecTrustResultValue, "TrustResultValue");
LC32_SECURITY_STRING(kSecTrustRevocationChecked,
                     "TrustRevocationChecked");
LC32_SECURITY_STRING(kSecTrustRevocationValidUntilDate,
                     "TrustExpirationDate");

#define LC32_SECURITY_ALGORITHM(name, value) \
    const SecKeyAlgorithm name = CFSTR(value)

LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDHKeyExchangeCofactor,
                        "algid:keyexchange:ECDHC");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDHKeyExchangeCofactorX963SHA1,
                        "algid:keyexchange:ECDHC:KDFX963:SHA1");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDHKeyExchangeCofactorX963SHA224,
                        "algid:keyexchange:ECDHC:KDFX963:SHA224");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDHKeyExchangeCofactorX963SHA256,
                        "algid:keyexchange:ECDHC:KDFX963:SHA256");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDHKeyExchangeCofactorX963SHA384,
                        "algid:keyexchange:ECDHC:KDFX963:SHA384");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDHKeyExchangeCofactorX963SHA512,
                        "algid:keyexchange:ECDHC:KDFX963:SHA512");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDHKeyExchangeStandard,
                        "algid:keyexchange:ECDH");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA1,
                        "algid:keyexchange:ECDH:KDFX963:SHA1");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA224,
                        "algid:keyexchange:ECDH:KDFX963:SHA224");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA256,
                        "algid:keyexchange:ECDH:KDFX963:SHA256");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA384,
                        "algid:keyexchange:ECDH:KDFX963:SHA384");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA512,
                        "algid:keyexchange:ECDH:KDFX963:SHA512");

LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDSASignatureDigestX962,
                        "algid:sign:ECDSA:digest-X962");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDSASignatureDigestX962SHA1,
                        "algid:sign:ECDSA:digest-X962:SHA1");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDSASignatureDigestX962SHA224,
                        "algid:sign:ECDSA:digest-X962:SHA224");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDSASignatureDigestX962SHA256,
                        "algid:sign:ECDSA:digest-X962:SHA256");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDSASignatureDigestX962SHA384,
                        "algid:sign:ECDSA:digest-X962:SHA384");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDSASignatureDigestX962SHA512,
                        "algid:sign:ECDSA:digest-X962:SHA512");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDSASignatureMessageX962SHA1,
                        "algid:sign:ECDSA:message-X962:SHA1");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDSASignatureMessageX962SHA224,
                        "algid:sign:ECDSA:message-X962:SHA224");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                        "algid:sign:ECDSA:message-X962:SHA256");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDSASignatureMessageX962SHA384,
                        "algid:sign:ECDSA:message-X962:SHA384");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDSASignatureMessageX962SHA512,
                        "algid:sign:ECDSA:message-X962:SHA512");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECDSASignatureRFC4754,
                        "algid:sign:ECDSA:RFC4754");

/* The C symbol uses Standard/Cofactor while Security's wire value uses
 * ECDH/ECDHC.  Spell these out instead of relying on token stringification. */
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECIESEncryptionStandardX963SHA1AESGCM,
                        "algid:encrypt:ECIES:ECDH:KDFX963:SHA1:AESGCM");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECIESEncryptionStandardX963SHA224AESGCM,
                        "algid:encrypt:ECIES:ECDH:KDFX963:SHA224:AESGCM");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECIESEncryptionStandardX963SHA256AESGCM,
                        "algid:encrypt:ECIES:ECDH:KDFX963:SHA256:AESGCM");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECIESEncryptionStandardX963SHA384AESGCM,
                        "algid:encrypt:ECIES:ECDH:KDFX963:SHA384:AESGCM");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECIESEncryptionStandardX963SHA512AESGCM,
                        "algid:encrypt:ECIES:ECDH:KDFX963:SHA512:AESGCM");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECIESEncryptionCofactorX963SHA1AESGCM,
                        "algid:encrypt:ECIES:ECDHC:KDFX963:SHA1:AESGCM");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECIESEncryptionCofactorX963SHA224AESGCM,
                        "algid:encrypt:ECIES:ECDHC:KDFX963:SHA224:AESGCM");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECIESEncryptionCofactorX963SHA256AESGCM,
                        "algid:encrypt:ECIES:ECDHC:KDFX963:SHA256:AESGCM");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECIESEncryptionCofactorX963SHA384AESGCM,
                        "algid:encrypt:ECIES:ECDHC:KDFX963:SHA384:AESGCM");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmECIESEncryptionCofactorX963SHA512AESGCM,
                        "algid:encrypt:ECIES:ECDHC:KDFX963:SHA512:AESGCM");

LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSAEncryptionRaw,
                        "algid:encrypt:RSA:raw");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSAEncryptionPKCS1,
                        "algid:encrypt:RSA:PKCS1");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSAEncryptionOAEPSHA1,
                        "algid:encrypt:RSA:OAEP:SHA1");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSAEncryptionOAEPSHA224,
                        "algid:encrypt:RSA:OAEP:SHA224");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSAEncryptionOAEPSHA256,
                        "algid:encrypt:RSA:OAEP:SHA256");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSAEncryptionOAEPSHA384,
                        "algid:encrypt:RSA:OAEP:SHA384");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSAEncryptionOAEPSHA512,
                        "algid:encrypt:RSA:OAEP:SHA512");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSAEncryptionOAEPSHA1AESGCM,
                        "algid:encrypt:RSA:OAEP:SHA1:AESGCM");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSAEncryptionOAEPSHA224AESGCM,
                        "algid:encrypt:RSA:OAEP:SHA224:AESGCM");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSAEncryptionOAEPSHA256AESGCM,
                        "algid:encrypt:RSA:OAEP:SHA256:AESGCM");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSAEncryptionOAEPSHA384AESGCM,
                        "algid:encrypt:RSA:OAEP:SHA384:AESGCM");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSAEncryptionOAEPSHA512AESGCM,
                        "algid:encrypt:RSA:OAEP:SHA512:AESGCM");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSASignatureRaw,
                        "algid:sign:RSA:raw");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSASignatureDigestPKCS1v15Raw,
                        "algid:sign:RSA:digest-PKCS1v15");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA224,
                        "algid:sign:RSA:digest-PKCS1v15:SHA224");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA1,
                        "algid:sign:RSA:message-PKCS1v15:SHA1");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA224,
                        "algid:sign:RSA:message-PKCS1v15:SHA224");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,
                        "algid:sign:RSA:message-PKCS1v15:SHA256");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA384,
                        "algid:sign:RSA:message-PKCS1v15:SHA384");
LC32_SECURITY_ALGORITHM(kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA512,
                        "algid:sign:RSA:message-PKCS1v15:SHA512");

const SecKeyKeyExchangeParameter kSecKeyKeyExchangeParameterRequestedSize =
    CFSTR("requestedSize");
const SecKeyKeyExchangeParameter kSecKeyKeyExchangeParameterSharedInfo =
    CFSTR("sharedInfo");

#undef LC32_SECURITY_ALGORITHM
#undef LC32_SECURITY_STRING

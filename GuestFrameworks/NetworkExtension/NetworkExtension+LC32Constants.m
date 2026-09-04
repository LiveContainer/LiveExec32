#import <NetworkExtension/NetworkExtension.h>
#import <Foundation/Foundation+LC32.h>

/*
 * Keep guest exports at stable ARM32 addresses while binding each object to
 * the native framework constant. This preserves native key/identifier
 * identity when a guest collection crosses the bridge.
 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

LC32_CONST_STR_DECL(NSString *const NEAppProxyErrorDomain)
LC32_CONST_STR_DECL(NSString *const NEFilterConfigurationDidChangeNotification)
LC32_CONST_STR_DECL(NSString *const NEFilterErrorDomain)
LC32_CONST_STR_DECL(const NSString *NEFilterProviderRemediationMapRemediationButtonTexts)
LC32_CONST_STR_DECL(const NSString *NEFilterProviderRemediationMapRemediationURLs)
LC32_CONST_STR_DECL(NSString *const NETunnelProviderErrorDomain)
LC32_CONST_STR_DECL(NSString *const NEVPNConfigurationChangeNotification)
LC32_CONST_STR_DECL(NSString *const NEVPNConnectionStartOptionPassword)
LC32_CONST_STR_DECL(NSString *const NEVPNConnectionStartOptionUsername)
LC32_CONST_STR_DECL(NSString *const NEVPNErrorDomain)
LC32_CONST_STR_DECL(NSString *const NEVPNStatusDidChangeNotification)
LC32_CONST_STR_DECL(const NSString *kNEHotspotHelperOptionDisplayName)

__attribute__((constructor)) static void LC32InitializeNetworkExtensionConstants(void) {
    LC32LoadHostFramework("NetworkExtension");
    LC32_CONST_STR_INIT(NEAppProxyErrorDomain);
    LC32_CONST_STR_INIT(NEFilterConfigurationDidChangeNotification);
    LC32_CONST_STR_INIT(NEFilterErrorDomain);
    LC32_CONST_STR_INIT(NEFilterProviderRemediationMapRemediationButtonTexts);
    LC32_CONST_STR_INIT(NEFilterProviderRemediationMapRemediationURLs);
    LC32_CONST_STR_INIT(NETunnelProviderErrorDomain);
    LC32_CONST_STR_INIT(NEVPNConfigurationChangeNotification);
    LC32_CONST_STR_INIT(NEVPNConnectionStartOptionPassword);
    LC32_CONST_STR_INIT(NEVPNConnectionStartOptionUsername);
    LC32_CONST_STR_INIT(NEVPNErrorDomain);
    LC32_CONST_STR_INIT(NEVPNStatusDidChangeNotification);
    LC32_CONST_STR_INIT(kNEHotspotHelperOptionDisplayName);
}

#pragma clang diagnostic pop

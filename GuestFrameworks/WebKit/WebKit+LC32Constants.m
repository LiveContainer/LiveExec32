#import <WebKit/WebKit.h>

#define LC32_WEBKIT_STRING(symbol, value) \
    NSString *const LC32_WEBKIT_##symbol __asm__("_" #symbol) = value;

LC32_WEBKIT_STRING(WKErrorDomain, @"WKErrorDomain")
LC32_WEBKIT_STRING(WKPreviewActionItemIdentifierAddToReadingList,
    @"WKPreviewActionItemIdentifierAddToReadingList")
LC32_WEBKIT_STRING(WKPreviewActionItemIdentifierCopy,
    @"WKPreviewActionItemIdentifierCopy")
LC32_WEBKIT_STRING(WKPreviewActionItemIdentifierOpen,
    @"WKPreviewActionItemIdentifierOpen")
LC32_WEBKIT_STRING(WKPreviewActionItemIdentifierShare,
    @"WKPreviewActionItemIdentifierShare")
LC32_WEBKIT_STRING(WKWebsiteDataTypeCookies, @"WKWebsiteDataTypeCookies")
LC32_WEBKIT_STRING(WKWebsiteDataTypeDiskCache, @"WKWebsiteDataTypeDiskCache")
LC32_WEBKIT_STRING(WKWebsiteDataTypeIndexedDBDatabases,
    @"WKWebsiteDataTypeIndexedDBDatabases")
LC32_WEBKIT_STRING(WKWebsiteDataTypeLocalStorage,
    @"WKWebsiteDataTypeLocalStorage")
LC32_WEBKIT_STRING(WKWebsiteDataTypeMemoryCache,
    @"WKWebsiteDataTypeMemoryCache")
LC32_WEBKIT_STRING(WKWebsiteDataTypeOfflineWebApplicationCache,
    @"WKWebsiteDataTypeOfflineWebApplicationCache")
LC32_WEBKIT_STRING(WKWebsiteDataTypeSessionStorage,
    @"WKWebsiteDataTypeSessionStorage")
LC32_WEBKIT_STRING(WKWebsiteDataTypeWebSQLDatabases,
    @"WKWebsiteDataTypeWebSQLDatabases")

#undef LC32_WEBKIT_STRING

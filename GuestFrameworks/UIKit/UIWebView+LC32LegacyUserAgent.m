#import <UIKit/UIKit.h>
#import <LC32/LC32.h>

/*
 * Older UIWebView releases added their User-Agent header before asking the
 * delegate whether a request should start.  Some legacy SDKs load the
 * deliberately incomplete URL "http://", read that header in
 * webView:shouldStartLoadWithRequest:navigationType:, cancel the request, and
 * synchronously pump the run loop until the value appears.  Current UIKit
 * normalizes that sentinel to a file URL without adding the header, leaving
 * those callers in an infinite launch loop.
 *
 * Preserve ordinary web requests.  For this well-known sentinel, deliver the
 * delegate probe synchronously and do not ask current UIKit to load the
 * malformed URL: modern UIWebView may never issue a delegate callback for it.
 */
@implementation UIWebView (LC32LegacyUserAgent)

- (void)loadRequest:(NSURLRequest *)request {
    if([request.URL.absoluteString isEqualToString:@"http://"]) {
        NSMutableURLRequest *probeRequest = [request mutableCopy];
        if(![probeRequest valueForHTTPHeaderField:@"User-Agent"]) {
            [probeRequest setValue:
            @"Mozilla/5.0 (iPhone; CPU iPhone OS 10_3_3 like Mac OS X) "
             "AppleWebKit/603.3.8 (KHTML, like Gecko) Mobile/14G60"
            forHTTPHeaderField:@"User-Agent"];
        }

        id<UIWebViewDelegate> delegate = self.delegate;
        SEL probeSelector =
            @selector(webView:shouldStartLoadWithRequest:navigationType:);
        if([delegate respondsToSelector:probeSelector]) {
            [delegate webView:self
                shouldStartLoadWithRequest:probeRequest
                navigationType:UIWebViewNavigationTypeOther];
        }
        return;
    }

    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    LC32InvokeHostSelector(self.host_self, selector,
        request.host_self, (uint64_t)0);
}

@end

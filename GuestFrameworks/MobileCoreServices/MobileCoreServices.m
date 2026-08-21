// Compatibility shell for MobileCoreServices.framework.
//
// Some legacy applications carry a load command for MobileCoreServices even
// when they do not import any of its symbols.  Loading the original iOS 10
// binary would unnecessarily pull its LaunchServices/XPC dependency graph
// into the small-shim runtime.  Keep that graph out until an application
// actually needs a MobileCoreServices API that can be bridged deliberately.

void LC32MobileCoreServicesCompatibilityStub(void) {
}

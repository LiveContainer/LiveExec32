// Compatibility shell for Security.framework.
//
// Some legacy applications carry a load command for Security even when they
// do not import any Security symbols.  Loading the original iOS 10 framework
// needlessly brings its system-service dependency graph into the small-shim
// runtime.  Keep that graph out until an application needs a Security API
// that can be bridged deliberately.

void LC32SecurityCompatibilityStub(void) {
}

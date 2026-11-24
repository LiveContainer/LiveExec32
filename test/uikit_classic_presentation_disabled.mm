#import "LC32ClassicPresentation.h"

// The native-only rotation fixture does not load the guest runtime or request
// forced Classic presentation. Keep its original non-Classic baseline explicit.
bool LC32GetClassicScreenGeometry(UIScreen *, LC32ClassicScreenGeometry *) {
    return false;
}

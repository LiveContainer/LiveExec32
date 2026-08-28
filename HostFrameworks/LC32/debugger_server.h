#pragma once

void DebuggerConfigureForGuestRoot(const char *rootPath);
bool ResolveDebuggerImagePath(const char *guestPath, char *hostPath);
int setupGDBStub(const char *gdbListenAddress);

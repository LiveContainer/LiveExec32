#ifndef LC32_GUEST_BOOTSTRAP_H
#define LC32_GUEST_BOOTSTRAP_H

#include <cstddef>
#include <cstdint>
#include <map>
#include <string>
#include <vector>
#include "../../include/LC32LegacyBundleLayout.h"

namespace LC32GuestBootstrap {

inline constexpr char EnvironmentPrefix[] = "LC32_GUEST_ENV_";
inline constexpr std::size_t InitialStackGap = 0x1000;

// LiveContainer's HOME is the selected guest data container, while its
// Foundation home can still identify the outer container. Return an owning
// snapshot before launcher setenv calls can invalidate environment pointers.
// Simulator launches may resolve an explicitly shortened container symlink;
// leave device path spellings unchanged by default, including jailbreak paths.
std::string SelectConfiguredHomeDirectory(
    const char *explicitGuestHome,
    const char *liveContainerHome,
    const char *processHome,
    bool resolveSymlinks = false);

inline constexpr char LegacyBundleAliasName[] = LC32_LEGACY_BUNDLE_ALIAS_NAME;
inline constexpr char LegacyBundleManagedTarget[] = LC32_LEGACY_BUNDLE_MANAGED_TARGET;
inline constexpr char LegacyBundleInnerAliasName[] = LC32_LEGACY_BUNDLE_INNER_ALIAS_NAME;

// Pre-iOS-8 apps may discover their bundle by enumerating HOME for an .app
// child. Restore that layout only for a configured app container, never the
// CLI runner's fallback home. The reserved alias is deliberately short for
// old path buffers. An installer-created outer alias whose exact relative
// target is LegacyBundleManagedTarget establishes ownership of the reserved
// inner symlink. That symlink may be retargeted as the bundle moves; no other
// existing entry (including a non-symlink inner entry) is replaced. Otherwise
// use a relative direct link for LiveContainer, so moving the outer container
// preserves it. Upgrade an existing absolute direct link only if it resolves
// to this bundle; preserve other entries and already-valid relative links.
// Returns zero for success/not applicable, or an errno value for a failure.
int EnsureLegacyBundleLayout(
    const std::string &configuredHome,
    const std::string &executablePath,
    std::uint32_t sdkVersion);

struct EnvironmentSelection {
    std::map<std::string, std::string> values;
    std::vector<std::string> rejectedSourceNames;
};

// Only explicitly prefixed entries cross into the guest. The prefix is
// stripped, empty values are preserved, and a later duplicate name wins.
EnvironmentSelection CollectEnvironment(char *const environment[]);

// Launcher-owned values override explicitly forwarded entries so the guest
// cannot disagree with the host about its home, thread mode, or dyld setup.
std::vector<std::string> FinalizeEnvironment(
    EnvironmentSelection selection,
    const std::string &guestHome,
    const std::string &nativeGuestThreads,
    std::vector<std::string> *overriddenNames = nullptr);

struct InitialStackString {
    std::uint32_t address = 0;
    std::string value;
};

struct InitialStackImage {
    std::uint32_t stackPointer = 0;
    std::vector<InitialStackString> strings;
    std::vector<std::uint32_t> words;
};

// Builds the complete Darwin initial stack table without touching guest
// memory. `arguments` excludes the LiveExec32 launcher itself and therefore
// maps directly to the guest's argc/argv. The resulting words are laid out as
// [executable Mach header, argc, argv..., 0, envp..., 0, apple..., 0].
bool BuildInitialStackImage(
    std::uint32_t stackBase,
    std::uint32_t stackSize,
    std::uint32_t executableAddress,
    const std::vector<std::string> &arguments,
    const std::vector<std::string> &environment,
    const std::vector<std::string> &apple,
    InitialStackImage *image,
    std::string *error = nullptr,
    std::size_t reservedGap = InitialStackGap);

} // namespace LC32GuestBootstrap

#endif

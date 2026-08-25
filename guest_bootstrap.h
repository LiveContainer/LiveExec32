#ifndef LC32_GUEST_BOOTSTRAP_H
#define LC32_GUEST_BOOTSTRAP_H

#include <cstddef>
#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace LC32GuestBootstrap {

inline constexpr char EnvironmentPrefix[] = "LC32_GUEST_ENV_";
inline constexpr std::size_t InitialStackGap = 0x1000;

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
    const std::string &objcTrace,
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

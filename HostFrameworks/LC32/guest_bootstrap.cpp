#include "guest_bootstrap.h"

#include <cctype>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <limits>
#include <limits.h>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>

namespace LC32GuestBootstrap {
namespace {

bool IsEnvironmentName(const std::string &name) {
    if(name.empty()) return false;
    const auto first = static_cast<unsigned char>(name.front());
    if(first != '_' && !std::isalpha(first)) return false;
    for(const char character : name) {
        const auto value = static_cast<unsigned char>(character);
        if(value != '_' && !std::isalnum(value)) return false;
    }
    return true;
}

void SetError(std::string *error, const char *message) {
    if(error) *error = message;
}

bool AddSize(std::size_t left, std::size_t right, std::size_t *result) {
    if(right > std::numeric_limits<std::size_t>::max() - left) return false;
    *result = left + right;
    return true;
}

struct DirectoryDescriptor {
    int value;
    ~DirectoryDescriptor() {
        if(value >= 0) close(value);
    }
};

bool IsManagedOuterAlias(int home) {
    char target[sizeof(LegacyBundleManagedTarget)];
    const ssize_t length = readlinkat(
        home, LegacyBundleAliasName, target, sizeof(target));
    return length == sizeof(LegacyBundleManagedTarget) - 1 &&
        memcmp(target, LegacyBundleManagedTarget, length) == 0;
}

int ReplaceExistingAlias(int directory, const char *name, const char *target,
                         const struct stat &expected) {
    // Stage in the validated directory, without following/deleting the old
    // target. Refuse an entry replaced since the caller validated it.
    char temporaryName[80];
    bool temporaryCreated = false;
    for(unsigned attempt = 0; attempt < 8; ++attempt) {
        unsigned long long nonce = 0;
        arc4random_buf(&nonce, sizeof(nonce));
        snprintf(temporaryName, sizeof(temporaryName),
            ".LiveExec32.app.%016llx.tmp", nonce);
        if(symlinkat(target, directory, temporaryName) == 0) {
            temporaryCreated = true;
            break;
        }
        if(errno != EEXIST) return errno;
    }
    if(!temporaryCreated) return EEXIST;
    int error = 0;
    struct stat existing = {};
    if(fstatat(directory, name, &existing,
            AT_SYMLINK_NOFOLLOW) != 0) {
        error = errno;
    } else if(!S_ISLNK(existing.st_mode) ||
            existing.st_dev != expected.st_dev ||
            existing.st_ino != expected.st_ino) {
        error = EEXIST;
    } else if(renameat(directory, temporaryName, directory, name) != 0) {
        error = errno;
    }
    if(error != 0) (void)unlinkat(directory, temporaryName, 0);
    return error;
}

int UpdateManagedInnerAlias(int home, const char *resolvedBundle,
                           const struct stat &bundleMetadata) {
    DirectoryDescriptor documents{openat(home, "Documents",
        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)};
    if(documents.value < 0) return errno;

    struct stat existing = {};
    if(fstatat(documents.value, LegacyBundleInnerAliasName, &existing,
            AT_SYMLINK_NOFOLLOW) != 0) {
        if(errno != ENOENT) return errno;
        if(symlinkat(resolvedBundle, documents.value,
                LegacyBundleInnerAliasName) == 0) return 0;
        if(errno != EEXIST) return errno;
        // A concurrent launch may have installed the managed symlink.
        if(fstatat(documents.value, LegacyBundleInnerAliasName, &existing,
                AT_SYMLINK_NOFOLLOW) != 0) return errno;
    }
    if(!S_ISLNK(existing.st_mode)) return EEXIST;
    struct stat target = {};
    if(fstatat(documents.value, LegacyBundleInnerAliasName, &target, 0) == 0 &&
            target.st_dev == bundleMetadata.st_dev &&
            target.st_ino == bundleMetadata.st_ino) return 0;

    // The exact outer-link convention owns this inner symlink, even if its
    // earlier bundle target is now missing or elsewhere.
    return ReplaceExistingAlias(documents.value, LegacyBundleInnerAliasName,
        resolvedBundle, existing);
}

std::string RelativeBundleTarget(const char *resolvedHome,
                                 const char *resolvedBundle) {
    // Canonical paths avoid counting symlink aliases (including /var) as
    // actual parent directories. Compare complete components, not prefixes.
    const std::string home = std::string(resolvedHome) + "/";
    const std::string bundle = std::string(resolvedBundle) + "/";
    std::size_t common = 0;
    for(std::size_t index = 0; index < home.size() && index < bundle.size() &&
            home[index] == bundle[index]; ++index) {
        if(home[index] == '/') common = index + 1;
    }
    std::string target;
    for(std::size_t index = common; index < home.size(); ++index) {
        if(home[index] == '/') target += "../";
    }
    target += bundle.substr(common);
    if(target.empty()) return ".";
    target.pop_back(); // Both component sequences end in a slash.
    return target;
}

} // anonymous namespace

std::string SelectConfiguredHomeDirectory(
        const char *explicitGuestHome,
        const char *liveContainerHome,
        const char *processHome,
        bool resolveSymlinks) {
    std::string selected;
    if(explicitGuestHome && explicitGuestHome[0] == '/') {
        selected = explicitGuestHome;
    } else if(liveContainerHome && processHome && processHome[0] == '/') {
        selected = processHome;
    }
    if(resolveSymlinks && !selected.empty()) {
        char resolved[PATH_MAX];
        if(realpath(selected.c_str(), resolved)) return resolved;
    }
    return selected;
}

int EnsureLegacyBundleLayout(
        const std::string &configuredHome,
        const std::string &executablePath,
        std::uint32_t sdkVersion) {
    if(sdkVersion >= 0x00080000 || configuredHome.empty() ||
            configuredHome.front() != '/' || configuredHome == "/" ||
            executablePath.empty() || executablePath.front() != '/') {
        return 0;
    }
    char resolvedHome[PATH_MAX];
    if(!realpath(configuredHome.c_str(), resolvedHome)) return errno;
    if(resolvedHome[1] == '\0') return 0;

    const std::size_t slash = executablePath.find_last_of('/');
    const std::string bundlePath = executablePath.substr(0, slash);
    const std::string executableName = executablePath.substr(slash + 1);
    if(bundlePath.size() <= 4 ||
            bundlePath.compare(bundlePath.size() - 4, 4, ".app") != 0 ||
            executableName.empty() || executableName == "." ||
            executableName == "..") {
        return 0;
    }

    char resolvedBundle[PATH_MAX];
    if(!realpath(bundlePath.c_str(), resolvedBundle)) return errno;
    DirectoryDescriptor bundle{
        open(resolvedBundle, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)};
    if(bundle.value < 0) return errno;

    struct stat metadata = {};
    if(fstatat(bundle.value, "Info.plist", &metadata,
            AT_SYMLINK_NOFOLLOW) != 0 || !S_ISREG(metadata.st_mode)) {
        return 0;
    }
    if(fstatat(bundle.value, executableName.c_str(), &metadata,
            AT_SYMLINK_NOFOLLOW) != 0 || !S_ISREG(metadata.st_mode)) {
        return 0;
    }

    DirectoryDescriptor home{
        open(configuredHome.c_str(),
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)};
    if(home.value < 0) return errno;

    // The real pre-iOS-8 layout already has its bundle in HOME. Do not add a
    // second .app entry in that case, including when HOME has a path alias.
    struct stat homeMetadata = {};
    struct stat parentMetadata = {};
    if(fstat(home.value, &homeMetadata) != 0) return errno;
    if(fstatat(bundle.value, "..", &parentMetadata, 0) != 0) return errno;
    if(homeMetadata.st_dev == parentMetadata.st_dev &&
            homeMetadata.st_ino == parentMetadata.st_ino) {
        return 0;
    }

    struct stat bundleMetadata = {};
    if(fstat(bundle.value, &bundleMetadata) != 0) return errno;
    // The installer owns the outer link because an app sandbox cannot create
    // entries at HOME's root. The app can maintain the inner Documents link.
    if(IsManagedOuterAlias(home.value)) {
        return UpdateManagedInnerAlias(
            home.value, resolvedBundle, bundleMetadata);
    }
    const std::string relativeTarget =
        RelativeBundleTarget(resolvedHome, resolvedBundle);
    auto checkExistingAlias = [&]() {
        struct stat entry = {};
        if(fstatat(home.value, LegacyBundleAliasName, &entry,
                AT_SYMLINK_NOFOLLOW) != 0) {
            return errno;
        }
        if(!S_ISLNK(entry.st_mode)) return EEXIST;
        struct stat target = {};
        if(fstatat(home.value, LegacyBundleAliasName, &target, 0) == 0 &&
                target.st_dev == bundleMetadata.st_dev &&
                target.st_ino == bundleMetadata.st_ino) {
            char firstCharacter;
            if(readlinkat(home.value, LegacyBundleAliasName,
                    &firstCharacter, sizeof(firstCharacter)) < 0) return errno;
            // Migrate an older absolute alias only after confirming it still
            // names this bundle. Other existing relative links stay intact.
            if(firstCharacter == '/') {
                return ReplaceExistingAlias(home.value, LegacyBundleAliasName,
                    relativeTarget.c_str(), entry);
            }
            return 0;
        }
        return EEXIST;
    };

    const int existingError = checkExistingAlias();
    if(existingError != ENOENT) return existingError;
    if(symlinkat(relativeTarget.c_str(), home.value, LegacyBundleAliasName) == 0) {
        return 0;
    }
    // Another launch may have created the same alias after our lookup.
    return errno == EEXIST ? checkExistingAlias() : errno;
}

EnvironmentSelection CollectEnvironment(char *const environment[]) {
    EnvironmentSelection selection;
    if(!environment) return selection;

    const std::string prefix(EnvironmentPrefix);
    for(std::size_t index = 0; environment[index]; index++) {
        const std::string entry(environment[index]);
        const std::size_t equals = entry.find('=');
        const std::string sourceName = entry.substr(0, equals);
        if(sourceName.compare(0, prefix.size(), prefix) != 0) continue;

        const std::string guestName = sourceName.substr(prefix.size());
        if(equals == std::string::npos || !IsEnvironmentName(guestName)) {
            selection.rejectedSourceNames.push_back(sourceName);
            continue;
        }
        selection.values[guestName] = entry.substr(equals + 1);
    }
    return selection;
}

std::vector<std::string> FinalizeEnvironment(
        EnvironmentSelection selection,
        const std::string &guestHome,
        const std::string &nativeGuestThreads,
        std::vector<std::string> *overriddenNames) {
    auto setLauncherValue = [&](const char *name, const std::string &value) {
        if(overriddenNames && selection.values.count(name)) {
            overriddenNames->push_back(name);
        }
        selection.values[name] = value;
    };

    setLauncherValue("HOME", guestHome);
    setLauncherValue("NATIVE_GUEST_THREADS", nativeGuestThreads);
    setLauncherValue("DYLD_SHARED_REGION", "private");

    std::vector<std::string> result;
    result.reserve(selection.values.size());
    for(const auto &entry : selection.values) {
        result.push_back(entry.first + "=" + entry.second);
    }
    return result;
}

bool BuildInitialStackImage(
        std::uint32_t stackBase,
        std::uint32_t stackSize,
        std::uint32_t executableAddress,
        const std::vector<std::string> &arguments,
        const std::vector<std::string> &environment,
        const std::vector<std::string> &apple,
        InitialStackImage *image,
        std::string *error,
        std::size_t reservedGap) {
    if(!image) {
        SetError(error, "missing initial stack output");
        return false;
    }
    if(error) error->clear();

    const std::uint64_t stackTop =
        static_cast<std::uint64_t>(stackBase) + stackSize;
    if(stackSize == 0 || stackTop > UINT64_C(0x100000000)) {
        SetError(error, "guest stack range exceeds the 32-bit address space");
        return false;
    }
    if(arguments.size() > std::numeric_limits<std::uint32_t>::max()) {
        SetError(error, "guest argument count exceeds UINT32_MAX");
        return false;
    }

    InitialStackImage candidate;
    std::uint64_t cursor = stackTop;
    auto placeStrings = [&](const std::vector<std::string> &values,
                            std::vector<std::uint32_t> *addresses) {
        addresses->resize(values.size());
        for(std::size_t index = values.size(); index > 0; index--) {
            const std::string &value = values[index - 1];
            if(value.size() == std::numeric_limits<std::size_t>::max()) {
                return false;
            }
            const std::size_t byteCount = value.size() + 1;
            if(byteCount > cursor - stackBase) return false;
            cursor -= byteCount;
            if(cursor > std::numeric_limits<std::uint32_t>::max()) {
                return false;
            }
            const std::uint32_t address =
                static_cast<std::uint32_t>(cursor);
            (*addresses)[index - 1] = address;
            candidate.strings.push_back({address, value});
        }
        return true;
    };

    std::vector<std::uint32_t> argumentAddresses;
    std::vector<std::uint32_t> environmentAddresses;
    std::vector<std::uint32_t> appleAddresses;
    if(!placeStrings(arguments, &argumentAddresses) ||
            !placeStrings(environment, &environmentAddresses) ||
            !placeStrings(apple, &appleAddresses)) {
        SetError(error, "guest launch strings do not fit on the initial stack");
        return false;
    }

    cursor &= ~UINT64_C(3);
    if(cursor < stackBase) {
        SetError(error, "guest launch string alignment does not fit");
        return false;
    }
    if(reservedGap > cursor - stackBase) {
        SetError(error, "guest initial stack gap does not fit");
        return false;
    }
    cursor -= reservedGap;

    std::size_t wordCount = 2; // executable address and argc
    if(!AddSize(wordCount, argumentAddresses.size(), &wordCount) ||
            !AddSize(wordCount, environmentAddresses.size(), &wordCount) ||
            !AddSize(wordCount, appleAddresses.size(), &wordCount) ||
            !AddSize(wordCount, 3, &wordCount) ||
            wordCount > std::numeric_limits<std::size_t>::max() /
                sizeof(std::uint32_t)) {
        SetError(error, "guest initial stack table size overflow");
        return false;
    }
    const std::size_t tableBytes = wordCount * sizeof(std::uint32_t);
    if(tableBytes > cursor - stackBase) {
        SetError(error, "guest initial stack table does not fit");
        return false;
    }
    const std::uint64_t unalignedStackPointer = cursor - tableBytes;
    const std::uint64_t stackPointer =
        unalignedStackPointer & ~UINT64_C(15);
    if(stackPointer < stackBase ||
            stackPointer > std::numeric_limits<std::uint32_t>::max()) {
        SetError(error, "guest initial stack alignment does not fit");
        return false;
    }

    candidate.stackPointer = static_cast<std::uint32_t>(stackPointer);
    candidate.words.reserve(wordCount);
    candidate.words.push_back(executableAddress);
    candidate.words.push_back(static_cast<std::uint32_t>(arguments.size()));
    candidate.words.insert(candidate.words.end(),
                           argumentAddresses.begin(), argumentAddresses.end());
    candidate.words.push_back(0);
    candidate.words.insert(candidate.words.end(),
                           environmentAddresses.begin(),
                           environmentAddresses.end());
    candidate.words.push_back(0);
    candidate.words.insert(candidate.words.end(),
                           appleAddresses.begin(), appleAddresses.end());
    candidate.words.push_back(0);

    if(candidate.words.size() != wordCount) {
        SetError(error, "guest initial stack table count mismatch");
        return false;
    }
    *image = std::move(candidate);
    return true;
}

} // namespace LC32GuestBootstrap

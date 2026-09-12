#include "guest_bootstrap.h"

#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <iostream>
#include <limits.h>
#include <map>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>
#include <vector>

namespace {

int failures = 0;

void Check(bool condition, const char *expression, int line) {
    if(condition) return;
    std::cerr << "guest_bootstrap_host.cpp:" << line
              << ": check failed: " << expression << '\n';
    failures++;
}

#define CHECK(expression) Check((expression), #expression, __LINE__)

std::map<std::string, std::string> ParseEnvironment(
        const std::vector<std::string> &environment) {
    std::map<std::string, std::string> result;
    for(const std::string &entry : environment) {
        const std::size_t equals = entry.find('=');
        CHECK(equals != std::string::npos);
        if(equals == std::string::npos) continue;
        const std::string name = entry.substr(0, equals);
        CHECK(result.count(name) == 0);
        result[name] = entry.substr(equals + 1);
    }
    return result;
}

bool Contains(const std::vector<std::string> &values,
              const std::string &value) {
    return std::find(values.begin(), values.end(), value) != values.end();
}

void TestConfiguredHomeDirectory() {
    using LC32GuestBootstrap::SelectConfiguredHomeDirectory;
    CHECK(SelectConfiguredHomeDirectory(
        "/explicit", "/outer", "/selected") == "/explicit");
    CHECK(SelectConfiguredHomeDirectory(
        "/explicit", nullptr, "/native") == "/explicit");
    CHECK(SelectConfiguredHomeDirectory(
        nullptr, "/outer", "/selected") == "/selected");
    CHECK(SelectConfiguredHomeDirectory(
        "", "/outer", "/selected") == "/selected");
    CHECK(SelectConfiguredHomeDirectory(
        "relative", "/outer", "/selected") == "/selected");
    CHECK(SelectConfiguredHomeDirectory(
        nullptr, nullptr, "/native").empty());
    CHECK(SelectConfiguredHomeDirectory(
        nullptr, "/outer", "relative").empty());
    CHECK(SelectConfiguredHomeDirectory(
        nullptr, "/outer", nullptr).empty());

    char selectedHome[] = "/selected";
    const std::string snapshot = SelectConfiguredHomeDirectory(
        nullptr, "/outer", selectedHome);
    selectedHome[1] = 'X';
    CHECK(snapshot == "/selected");
}

struct BundleLayoutFixture {
    std::string root;
    std::string home;
    std::string bundle;
    std::string executable;
    std::string alias;
    std::vector<std::pair<std::string, bool>> cleanup;

    BundleLayoutFixture() {
        char temporaryPath[] = "/private/tmp/lc32-bootstrap-XXXXXX";
        char *created = mkdtemp(temporaryPath);
        CHECK(created != nullptr);
        if(!created) return;
        root = created;
        home = root + "/Home";
        bundle = root + "/Game.app";
        executable = bundle + "/Game";
        alias = home + "/" + LC32GuestBootstrap::LegacyBundleAliasName;
        MakeDirectory(home);
        MakeDirectory(bundle);
        MakeFile(bundle + "/Info.plist");
        MakeFile(executable);
    }

    ~BundleLayoutFixture() {
        // Only remove the exact fixture entries, never follow symlinks or
        // recursively remove the directory supplied as a link's target.
        for(auto entry = cleanup.rbegin(); entry != cleanup.rend(); ++entry) {
            const int result = entry->second ?
                rmdir(entry->first.c_str()) : unlink(entry->first.c_str());
            CHECK(result == 0 || errno == ENOENT);
        }
        if(!root.empty()) CHECK(rmdir(root.c_str()) == 0);
    }

    void Track(const std::string &path, bool directory = false) {
        CHECK(!root.empty() && path.compare(0, root.size() + 1,
            root + "/") == 0);
        cleanup.emplace_back(path, directory);
    }

    void MakeDirectory(const std::string &path) {
        CHECK(mkdir(path.c_str(), 0700) == 0);
        Track(path, true);
    }

    void MakeFile(const std::string &path) {
        const int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0600);
        CHECK(fd >= 0);
        if(fd >= 0) CHECK(close(fd) == 0);
        Track(path);
    }

    void MakeLink(const std::string &target, const std::string &path) {
        CHECK(symlink(target.c_str(), path.c_str()) == 0);
        Track(path);
    }

    bool MoveDirectory(const std::string &from, const std::string &to) {
        const int result = rename(from.c_str(), to.c_str());
        CHECK(result == 0);
        if(result != 0) return false;
        for(auto &entry : cleanup) {
            if(entry.first == from ||
                    entry.first.compare(0, from.size() + 1, from + "/") == 0) {
                entry.first.replace(0, from.size(), to);
            }
        }
        return true;
    }
};

std::string ReadLink(const std::string &path) {
    char value[PATH_MAX];
    const ssize_t length = readlink(path.c_str(), value, sizeof(value));
    CHECK(length >= 0);
    return length >= 0 ? std::string(value, static_cast<std::size_t>(length)) :
        std::string();
}

bool EntryExists(const std::string &path) {
    struct stat metadata = {};
    return lstat(path.c_str(), &metadata) == 0;
}

void TestConfiguredHomeResolution() {
    using LC32GuestBootstrap::SelectConfiguredHomeDirectory;
    BundleLayoutFixture fixture;
    if(fixture.root.empty()) return;
    const std::string homeLink = fixture.root + "/LongContainerPath";
    fixture.MakeLink(fixture.home, homeLink);
    CHECK(SelectConfiguredHomeDirectory(
        nullptr, "/outer", homeLink.c_str()) == homeLink);
    CHECK(SelectConfiguredHomeDirectory(
        nullptr, "/outer", homeLink.c_str(), false) == homeLink);
    CHECK(SelectConfiguredHomeDirectory(
        nullptr, "/outer", homeLink.c_str(), true) == fixture.home);
    CHECK(SelectConfiguredHomeDirectory(
        homeLink.c_str(), "/outer", fixture.bundle.c_str(), true) ==
        fixture.home);
    CHECK(SelectConfiguredHomeDirectory(
        homeLink.c_str(), nullptr, fixture.bundle.c_str(), false) == homeLink);
    CHECK(SelectConfiguredHomeDirectory(
        "relative", "/outer", homeLink.c_str(), true) == fixture.home);
    CHECK(SelectConfiguredHomeDirectory(
        nullptr, nullptr, homeLink.c_str(), true).empty());
    const std::string missing = fixture.root + "/MissingHome";
    CHECK(SelectConfiguredHomeDirectory(
        missing.c_str(), "/outer", homeLink.c_str(), true) == missing);
    CHECK(SelectConfiguredHomeDirectory(
        nullptr, "/outer", missing.c_str(), true) == missing);
}

void TestLegacyBundleLayout() {
    using LC32GuestBootstrap::EnsureLegacyBundleLayout;
    {
        BundleLayoutFixture fixture;
        if(fixture.root.empty()) return;
        fixture.Track(fixture.alias);
        CHECK(EnsureLegacyBundleLayout(
            fixture.home, fixture.executable, 0x00070000) == 0);
        CHECK(ReadLink(fixture.alias) == "../Game.app");
        struct stat original = {};
        CHECK(lstat(fixture.alias.c_str(), &original) == 0);
        CHECK(EnsureLegacyBundleLayout(
            fixture.home, fixture.executable, 0) == 0);
        struct stat repeated = {};
        CHECK(lstat(fixture.alias.c_str(), &repeated) == 0);
        CHECK(S_ISLNK(repeated.st_mode));
        CHECK(original.st_ino == repeated.st_ino);
    }
    {
        BundleLayoutFixture fixture;
        if(fixture.root.empty()) return;
        fixture.MakeLink(fixture.bundle, fixture.alias);
        CHECK(EnsureLegacyBundleLayout(
            fixture.home, fixture.executable, 0) == 0);
        CHECK(ReadLink(fixture.alias) == "../Game.app");
    }
    {
        BundleLayoutFixture fixture;
        if(fixture.root.empty()) return;
        fixture.MakeLink("../Game.app", fixture.alias);
        CHECK(EnsureLegacyBundleLayout(
            fixture.home, fixture.executable, 0) == 0);
        CHECK(ReadLink(fixture.alias) == "../Game.app");
    }
    for(int kind = 0; kind < 4; kind++) {
        BundleLayoutFixture fixture;
        if(fixture.root.empty()) return;
        if(kind == 0) {
            fixture.MakeFile(fixture.alias);
        } else if(kind == 1) {
            fixture.MakeDirectory(fixture.alias);
            fixture.MakeFile(fixture.alias + "/user-data");
        } else {
            fixture.MakeLink(kind == 2 ? fixture.root :
                fixture.root + "/missing-target", fixture.alias);
        }
        struct stat original = {};
        CHECK(lstat(fixture.alias.c_str(), &original) == 0);
        CHECK(EnsureLegacyBundleLayout(
            fixture.home, fixture.executable, 0) == EEXIST);
        struct stat preserved = {};
        CHECK(lstat(fixture.alias.c_str(), &preserved) == 0);
        CHECK(original.st_ino == preserved.st_ino);
        CHECK(original.st_mode == preserved.st_mode);
        if(kind == 1) CHECK(EntryExists(fixture.alias + "/user-data"));
        if(kind >= 2) CHECK(ReadLink(fixture.alias) ==
            (kind == 2 ? fixture.root : fixture.root + "/missing-target"));
    }
    {
        BundleLayoutFixture fixture;
        if(fixture.root.empty()) return;
        CHECK(EnsureLegacyBundleLayout(
            fixture.home, fixture.executable, 0x00080000) == 0);
        CHECK(EnsureLegacyBundleLayout(
            "", fixture.executable, 0) == 0);
        CHECK(EnsureLegacyBundleLayout(
            "relative", fixture.executable, 0) == 0);
        CHECK(EnsureLegacyBundleLayout(
            "/", fixture.executable, 0) == 0);
        CHECK(EnsureLegacyBundleLayout(
            "/private/tmp/../..", fixture.executable, 0) == 0);
        CHECK(EnsureLegacyBundleLayout(
            fixture.home, "/usr/bin/test", 0) == 0);
        CHECK(EnsureLegacyBundleLayout(
            fixture.home, "Game.app/Game", 0) == 0);
        CHECK(EnsureLegacyBundleLayout(
            fixture.home, fixture.bundle + "/missing", 0) == 0);
        CHECK(!EntryExists(fixture.alias));
        CHECK(unlink((fixture.bundle + "/Info.plist").c_str()) == 0);
        CHECK(EnsureLegacyBundleLayout(
            fixture.home, fixture.executable, 0) == 0);
        CHECK(!EntryExists(fixture.alias));
    }
    {
        BundleLayoutFixture fixture;
        if(fixture.root.empty()) return;
        CHECK(EnsureLegacyBundleLayout(
            fixture.root + "/missing-home", fixture.executable, 0) == ENOENT);
        const std::string homeLink = fixture.root + "/HomeLink";
        fixture.MakeLink(fixture.home, homeLink);
        CHECK(EnsureLegacyBundleLayout(homeLink, fixture.executable, 0) != 0);
        CHECK(!EntryExists(fixture.alias));
        CHECK(EnsureLegacyBundleLayout(
            fixture.root, fixture.executable, 0) == 0);
        CHECK(!EntryExists(fixture.root + "/" +
            LC32GuestBootstrap::LegacyBundleAliasName));
    }
}

void TestLiveContainerRelativeBundleLayout() {
    using LC32GuestBootstrap::EnsureLegacyBundleLayout;
    using LC32GuestBootstrap::SelectConfiguredHomeDirectory;
    BundleLayoutFixture fixture;
    if(fixture.root.empty()) return;
    const std::string container = fixture.root + "/Container";
    const std::string home = container + "/Data/Application/Selected";
    const std::string bundle = container + "/Documents/Applications/Game.app";
    const std::string alias = home + "/" + LC32GuestBootstrap::LegacyBundleAliasName;
    for(const char *directory : {"", "/Data", "/Data/Application",
            "/Data/Application/Selected", "/Documents", "/Documents/Applications",
            "/Documents/Applications/Game.app"}) {
        fixture.MakeDirectory(container + directory);
    }
    fixture.MakeFile(bundle + "/Info.plist");
    fixture.MakeFile(bundle + "/Game");
    fixture.Track(alias);

    // Different aliases of the common ancestor must not add spurious ".."
    // components. LiveContainer's HOME selects the guest container, not LC_HOME_PATH.
    const std::string containerAlias = fixture.root + "/ContainerAlias";
    fixture.MakeLink(container, containerAlias);
    const std::string homeSpelling = containerAlias + "/Data/Application/Selected";
    const std::string selected = SelectConfiguredHomeDirectory(
        nullptr, container.c_str(), homeSpelling.c_str());
    CHECK(selected == homeSpelling);
    CHECK(EnsureLegacyBundleLayout(selected, bundle + "/Game", 0) == 0);
    CHECK(ReadLink(alias) == "../../../Documents/Applications/Game.app");
    CHECK(!EntryExists(container + "/" + LC32GuestBootstrap::LegacyBundleAliasName));

    // Reinstalling/moving the whole outer container must not break this link.
    const std::string moved = fixture.root + "/MovedContainer";
    if(!fixture.MoveDirectory(container, moved)) return;
    const std::string movedHome = moved + "/Data/Application/Selected";
    const std::string movedBundle = moved + "/Documents/Applications/Game.app";
    const std::string movedAlias = movedHome + "/" + LC32GuestBootstrap::LegacyBundleAliasName;
    struct stat followed = {}, expected = {}, original = {}, repeated = {};
    CHECK(stat(movedAlias.c_str(), &followed) == 0);
    CHECK(stat(movedBundle.c_str(), &expected) == 0);
    CHECK(followed.st_dev == expected.st_dev && followed.st_ino == expected.st_ino);
    CHECK(lstat(movedAlias.c_str(), &original) == 0);
    CHECK(EnsureLegacyBundleLayout(movedHome, movedBundle + "/Game", 0x70000) == 0);
    CHECK(lstat(movedAlias.c_str(), &repeated) == 0);
    CHECK(original.st_ino == repeated.st_ino);

    // A simulator's explicitly shortened HOME symlink is resolved first.
    const std::string shortHome = fixture.root + "/ShortHome";
    fixture.MakeLink(movedHome, shortHome);
    CHECK(EnsureLegacyBundleLayout(SelectConfiguredHomeDirectory(
        nullptr, moved.c_str(), shortHome.c_str(), true),
        movedBundle + "/Game", 0) == 0);
    CHECK(ReadLink(movedAlias) == "../../../Documents/Applications/Game.app");
}

void TestRelativeBundleComponents() {
    using LC32GuestBootstrap::EnsureLegacyBundleLayout;
    for(bool descendant : {false, true}) {
        BundleLayoutFixture fixture;
        if(fixture.root.empty()) return;
        const std::string bundle = descendant ? fixture.home + "/Game.app" :
            fixture.root + "/HomeGame.app";
        fixture.MakeDirectory(bundle);
        fixture.MakeFile(bundle + "/Info.plist");
        fixture.MakeFile(bundle + "/Game");
        fixture.Track(fixture.alias);
        CHECK(EnsureLegacyBundleLayout(fixture.home, bundle + "/Game", 0) == 0);
        if(descendant) {
            // Already at the original pre-iOS-8 location; no duplicate alias.
            CHECK(!EntryExists(fixture.alias));
        } else {
            CHECK(ReadLink(fixture.alias) == "../HomeGame.app");
        }
    }
}

void CheckOnlyManagedInnerEntry(const std::string &documents) {
    DIR *directory = opendir(documents.c_str());
    CHECK(directory != nullptr);
    if(!directory) return;
    unsigned entries = 0;
    while(struct dirent *entry = readdir(directory)) {
        if(strcmp(entry->d_name, ".") == 0 ||
           strcmp(entry->d_name, "..") == 0) continue;
        CHECK(strcmp(entry->d_name,
            LC32GuestBootstrap::LegacyBundleInnerAliasName) == 0);
        ++entries;
    }
    CHECK(entries == 1);
    CHECK(closedir(directory) == 0);
}

void TestManagedLegacyBundleLayout() {
    using LC32GuestBootstrap::EnsureLegacyBundleLayout;
    for(int initial = 0; initial < 4; ++initial) {
        BundleLayoutFixture fixture;
        if(fixture.root.empty()) return;
        const std::string documents = fixture.home + "/Documents";
        const std::string inner = documents + "/" +
            LC32GuestBootstrap::LegacyBundleInnerAliasName;
        fixture.MakeDirectory(documents);
        fixture.MakeLink(LC32GuestBootstrap::LegacyBundleManagedTarget,
                         fixture.alias);
        if(initial == 0) fixture.Track(inner);
        if(initial == 1) fixture.MakeLink(fixture.bundle, inner);
        if(initial == 2) fixture.MakeLink(fixture.root + "/removed.app", inner);
        if(initial == 3) fixture.MakeLink(fixture.executable, inner);
        struct stat outerBefore = {};
        CHECK(lstat(fixture.alias.c_str(), &outerBefore) == 0);
        CHECK(EnsureLegacyBundleLayout(fixture.home, fixture.executable, 0) == 0);
        CHECK(ReadLink(inner) == fixture.bundle);
        CHECK(ReadLink(fixture.alias) ==
            LC32GuestBootstrap::LegacyBundleManagedTarget);
        struct stat outerAfter = {}, innerBefore = {}, innerAfter = {};
        CHECK(lstat(fixture.alias.c_str(), &outerAfter) == 0);
        CHECK(outerAfter.st_ino == outerBefore.st_ino);
        CHECK(lstat(inner.c_str(), &innerBefore) == 0);
        CHECK(EnsureLegacyBundleLayout(fixture.home, fixture.executable, 0) == 0);
        CHECK(lstat(inner.c_str(), &innerAfter) == 0);
        CHECK(innerAfter.st_ino == innerBefore.st_ino);
        CHECK(EntryExists(fixture.executable));
        struct stat followed = {}, bundle = {};
        CHECK(stat(fixture.alias.c_str(), &followed) == 0);
        CHECK(stat(fixture.bundle.c_str(), &bundle) == 0);
        CHECK(followed.st_dev == bundle.st_dev && followed.st_ino == bundle.st_ino);
        CheckOnlyManagedInnerEntry(documents);
    }
    for(int conflict = 0; conflict < 2; ++conflict) {
        BundleLayoutFixture fixture;
        if(fixture.root.empty()) return;
        const std::string documents = fixture.home + "/Documents";
        const std::string inner = documents + "/" +
            LC32GuestBootstrap::LegacyBundleInnerAliasName;
        fixture.MakeDirectory(documents);
        fixture.MakeLink(LC32GuestBootstrap::LegacyBundleManagedTarget,
                         fixture.alias);
        if(conflict == 0) fixture.MakeFile(inner);
        else {
            fixture.MakeDirectory(inner);
            fixture.MakeFile(inner + "/user-data");
        }
        struct stat before = {}, after = {};
        CHECK(lstat(inner.c_str(), &before) == 0);
        CHECK(EnsureLegacyBundleLayout(fixture.home, fixture.executable, 0) == EEXIST);
        CHECK(lstat(inner.c_str(), &after) == 0);
        CHECK(before.st_ino == after.st_ino && before.st_mode == after.st_mode);
        if(conflict == 1) CHECK(EntryExists(inner + "/user-data"));
    }
    for(int kind = 0; kind < 3; ++kind) {
        BundleLayoutFixture fixture;
        if(fixture.root.empty()) return;
        const std::string documents = fixture.home + "/Documents";
        const std::string outside = fixture.root + "/Outside";
        fixture.MakeDirectory(outside);
        if(kind == 1) fixture.MakeLink(outside, documents);
        if(kind == 2) fixture.MakeFile(documents);
        fixture.MakeLink(LC32GuestBootstrap::LegacyBundleManagedTarget,
                         fixture.alias);
        CHECK(EnsureLegacyBundleLayout(fixture.home, fixture.executable, 0) != 0);
        CHECK(!EntryExists(outside + "/" +
            LC32GuestBootstrap::LegacyBundleInnerAliasName));
        CHECK(ReadLink(fixture.alias) ==
            LC32GuestBootstrap::LegacyBundleManagedTarget);
    }
    {
        BundleLayoutFixture fixture;
        if(fixture.root.empty()) return;
        const std::string documents = fixture.home + "/Documents";
        fixture.MakeDirectory(documents);
        fixture.MakeLink("Documents/./.LiveExec32.app", fixture.alias);
        CHECK(EnsureLegacyBundleLayout(fixture.home, fixture.executable, 0) == EEXIST);
        CHECK(!EntryExists(documents + "/" +
            LC32GuestBootstrap::LegacyBundleInnerAliasName));
    }
    {
        BundleLayoutFixture fixture;
        if(fixture.root.empty()) return;
        const std::string documents = fixture.home + "/Documents";
        fixture.MakeDirectory(documents);
        fixture.MakeLink(LC32GuestBootstrap::LegacyBundleManagedTarget,
                         fixture.alias);
        CHECK(EnsureLegacyBundleLayout(fixture.home, fixture.executable, 0x80000) == 0);
        CHECK(!EntryExists(documents + "/" +
            LC32GuestBootstrap::LegacyBundleInnerAliasName));
    }
}

void TestEnvironmentSelection() {
    char ignored[] = "PATH=/usr/bin";
    char firstDuplicate[] = "LC32_GUEST_ENV_FEATURE=first";
    char empty[] = "LC32_GUEST_ENV_EMPTY=";
    char explicitDyld[] = "LC32_GUEST_ENV_DYLD_PRINT_ENV=1";
    char secondDuplicate[] = "LC32_GUEST_ENV_FEATURE=second";
    char missingName[] = "LC32_GUEST_ENV_=value";
    char invalidName[] = "LC32_GUEST_ENV_BAD-NAME=value";
    char missingEquals[] = "LC32_GUEST_ENV_NO_EQUALS";
    char *source[] = {
        ignored,
        firstDuplicate,
        empty,
        explicitDyld,
        secondDuplicate,
        missingName,
        invalidName,
        missingEquals,
        nullptr,
    };

    LC32GuestBootstrap::EnvironmentSelection selection =
        LC32GuestBootstrap::CollectEnvironment(source);
    CHECK(selection.values.size() == 3);
    CHECK(selection.values.count("PATH") == 0);
    CHECK(selection.values.at("FEATURE") == "second");
    CHECK(selection.values.at("EMPTY").empty());
    CHECK(selection.values.at("DYLD_PRINT_ENV") == "1");
    CHECK(selection.rejectedSourceNames.size() == 3);
    CHECK(Contains(selection.rejectedSourceNames, "LC32_GUEST_ENV_"));
    CHECK(Contains(selection.rejectedSourceNames,
                   "LC32_GUEST_ENV_BAD-NAME"));
    CHECK(Contains(selection.rejectedSourceNames,
                   "LC32_GUEST_ENV_NO_EQUALS"));

    LC32GuestBootstrap::EnvironmentSelection emptySelection =
        LC32GuestBootstrap::CollectEnvironment(nullptr);
    CHECK(emptySelection.values.empty());
    CHECK(emptySelection.rejectedSourceNames.empty());
}

void TestEnvironmentFinalization() {
    char home[] = "LC32_GUEST_ENV_HOME=/spoofed";
    char trace[] = "LC32_GUEST_ENV_LC32_OBJC_TRACE=forwarded";
    char threads[] = "LC32_GUEST_ENV_NATIVE_GUEST_THREADS=spoofed";
    char sharedRegion[] = "LC32_GUEST_ENV_DYLD_SHARED_REGION=spoofed";
    char custom[] = "LC32_GUEST_ENV_CUSTOM=value";
    char *source[] = {
        home, trace, threads, sharedRegion, custom, nullptr,
    };

    std::vector<std::string> overridden;
    const std::vector<std::string> finalized =
        LC32GuestBootstrap::FinalizeEnvironment(
            LC32GuestBootstrap::CollectEnvironment(source),
            "/var/mobile", "0", &overridden);
    const std::map<std::string, std::string> values =
        ParseEnvironment(finalized);

    CHECK(values.at("HOME") == "/var/mobile");
    // The trace name is now an ordinary forwarded value, not a launcher
    // setting. Guest tracing itself is configured at compile time.
    CHECK(values.at("LC32_OBJC_TRACE") == "forwarded");
    CHECK(values.at("NATIVE_GUEST_THREADS") == "0");
    CHECK(values.at("DYLD_SHARED_REGION") == "private");
    CHECK(values.at("CUSTOM") == "value");
    CHECK(overridden.size() == 3);
    CHECK(Contains(overridden, "HOME"));
    CHECK(!Contains(overridden, "LC32_OBJC_TRACE"));
    CHECK(Contains(overridden, "NATIVE_GUEST_THREADS"));
    CHECK(Contains(overridden, "DYLD_SHARED_REGION"));
}

void TestDyldPrintOptIn() {
    char unrelated[] = "LC32_GUEST_ENV_APPLICATION_MODE=test";
    char hostTrace[] = "LC32_OBJC_TRACE=1";
    char *defaultSource[] = {unrelated, hostTrace, nullptr};
    const std::vector<std::string> defaults =
        LC32GuestBootstrap::FinalizeEnvironment(
            LC32GuestBootstrap::CollectEnvironment(defaultSource),
            "/var/mobile", "0");
    CHECK(ParseEnvironment(defaults).count("LC32_OBJC_TRACE") == 0);
    for(const std::string &entry : defaults) {
        CHECK(entry.compare(0, std::strlen("DYLD_PRINT_"),
                            "DYLD_PRINT_") != 0);
    }

    char printEnvironment[] =
        "LC32_GUEST_ENV_DYLD_PRINT_ENV=1";
    char printInitializers[] =
        "LC32_GUEST_ENV_DYLD_PRINT_INITIALIZERS=1";
    char *optInSource[] = {
        printEnvironment, printInitializers, nullptr,
    };
    const std::map<std::string, std::string> optedIn =
        ParseEnvironment(LC32GuestBootstrap::FinalizeEnvironment(
            LC32GuestBootstrap::CollectEnvironment(optInSource),
            "/var/mobile", "0"));
    CHECK(optedIn.at("DYLD_PRINT_ENV") == "1");
    CHECK(optedIn.at("DYLD_PRINT_INITIALIZERS") == "1");
}

struct MaterializedStack {
    std::uint32_t base;
    std::vector<unsigned char> bytes;

    std::uint32_t ReadWord(std::uint32_t address) const {
        CHECK(address >= base);
        const std::size_t offset = address - base;
        CHECK(offset <= bytes.size());
        CHECK(bytes.size() - std::min(offset, bytes.size()) >=
              sizeof(std::uint32_t));
        if(offset > bytes.size() ||
                bytes.size() - offset < sizeof(std::uint32_t)) {
            return 0;
        }
        std::uint32_t value = 0;
        std::memcpy(&value, bytes.data() + offset, sizeof(value));
        return value;
    }

    std::string ReadString(std::uint32_t address) const {
        CHECK(address >= base);
        const std::size_t offset = address - base;
        CHECK(offset < bytes.size());
        if(offset >= bytes.size()) return {};
        const auto begin = bytes.begin() + static_cast<std::ptrdiff_t>(offset);
        const auto terminator = std::find(begin, bytes.end(), 0);
        CHECK(terminator != bytes.end());
        return std::string(begin, terminator);
    }
};

MaterializedStack Materialize(
        std::uint32_t stackBase,
        std::uint32_t stackSize,
        const LC32GuestBootstrap::InitialStackImage &image) {
    MaterializedStack result{stackBase,
                             std::vector<unsigned char>(stackSize, 0xa5)};
    for(const LC32GuestBootstrap::InitialStackString &string : image.strings) {
        CHECK(string.address >= stackBase);
        const std::size_t offset = string.address - stackBase;
        const std::size_t byteCount = string.value.size() + 1;
        CHECK(offset <= result.bytes.size());
        CHECK(offset <= result.bytes.size() &&
              byteCount <= result.bytes.size() - offset);
        if(offset <= result.bytes.size() &&
                byteCount <= result.bytes.size() - offset) {
            std::memcpy(result.bytes.data() + offset,
                        string.value.data(), byteCount);
            CHECK(result.bytes[offset + string.value.size()] == 0);
        }
    }

    CHECK(image.stackPointer >= stackBase);
    const std::size_t tableOffset = image.stackPointer - stackBase;
    const std::size_t tableBytes =
        image.words.size() * sizeof(std::uint32_t);
    CHECK(tableOffset <= result.bytes.size());
    CHECK(tableOffset <= result.bytes.size() &&
          tableBytes <= result.bytes.size() - tableOffset);
    if(tableOffset <= result.bytes.size() &&
            tableBytes <= result.bytes.size() - tableOffset) {
        std::memcpy(result.bytes.data() + tableOffset,
                    image.words.data(), tableBytes);
    }
    return result;
}

void CheckStringTable(
        const MaterializedStack &stack,
        std::uint32_t &cursor,
        const std::vector<std::string> &expected) {
    for(const std::string &value : expected) {
        const std::uint32_t address = stack.ReadWord(cursor);
        CHECK(address != 0);
        CHECK(stack.ReadString(address) == value);
        cursor += sizeof(std::uint32_t);
    }
    CHECK(stack.ReadWord(cursor) == 0);
    cursor += sizeof(std::uint32_t);
}

void CheckStackLayout(
        std::uint32_t stackBase,
        std::uint32_t stackSize,
        std::uint32_t executableAddress,
        const std::vector<std::string> &arguments,
        const std::vector<std::string> &environment,
        const std::vector<std::string> &apple,
        const LC32GuestBootstrap::InitialStackImage &image) {
    const std::size_t expectedWordCount =
        2 + arguments.size() + 1 + environment.size() + 1 +
        apple.size() + 1;
    CHECK(image.stackPointer % 16 == 0);
    CHECK(image.stackPointer >= stackBase);
    CHECK(static_cast<std::uint64_t>(image.stackPointer) +
              expectedWordCount * sizeof(std::uint32_t) <=
          static_cast<std::uint64_t>(stackBase) + stackSize);
    CHECK(image.words.size() == expectedWordCount);

    const MaterializedStack stack = Materialize(stackBase, stackSize, image);
    std::uint32_t cursor = image.stackPointer;
    CHECK(stack.ReadWord(cursor) == executableAddress);
    cursor += sizeof(std::uint32_t);
    CHECK(stack.ReadWord(cursor) == arguments.size());
    cursor += sizeof(std::uint32_t);
    CheckStringTable(stack, cursor, arguments);
    CheckStringTable(stack, cursor, environment);
    CheckStringTable(stack, cursor, apple);
    CHECK(cursor == image.stackPointer +
          expectedWordCount * sizeof(std::uint32_t));
}

void TestArgumentCountsAndAlignment() {
    constexpr std::uint32_t stackBase = 0x70000000;
    constexpr std::uint32_t stackSize = 0x20000;
    constexpr std::uint32_t executableAddress = 0x11000000;
    const std::vector<std::string> environment = {
        "HOME=/var/mobile", "EMPTY=",
    };
    const std::vector<std::string> apple = {
        "/Applications/Test.app/Test", "pfz=0xffffffff",
    };

    for(std::size_t count = 0; count <= 8; count++) {
        std::vector<std::string> arguments;
        for(std::size_t index = 0; index < count; index++) {
            arguments.push_back("argument-" + std::to_string(index));
        }
        LC32GuestBootstrap::InitialStackImage image;
        std::string error = "stale";
        CHECK(LC32GuestBootstrap::BuildInitialStackImage(
            stackBase, stackSize, executableAddress,
            arguments, environment, apple, &image, &error));
        CHECK(error.empty());
        CheckStackLayout(stackBase, stackSize, executableAddress,
                         arguments, environment, apple, image);
    }
}

void TestLargeArgumentVector() {
    constexpr std::uint32_t stackBase = 0x71000000;
    constexpr std::uint32_t stackSize = 0x200000;
    std::vector<std::string> arguments;
    arguments.reserve(1500);
    for(std::size_t index = 0; index < 1500; index++) {
        arguments.push_back("arg-" + std::to_string(index));
    }
    const std::vector<std::string> environment = {"HOME=/var/mobile"};
    const std::vector<std::string> apple = {"/Test"};
    LC32GuestBootstrap::InitialStackImage image;
    std::string error;
    CHECK(LC32GuestBootstrap::BuildInitialStackImage(
        stackBase, stackSize, 0x11000000,
        arguments, environment, apple, &image, &error));
    CHECK(error.empty());
    CheckStackLayout(stackBase, stackSize, 0x11000000,
                     arguments, environment, apple, image);
}

void TestLongAndEmptyStrings() {
    constexpr std::uint32_t stackBase = 0x72000000;
    constexpr std::uint32_t stackSize = 0x100000;
    const std::string longArgument(128 * 1024, 'a');
    const std::string longEnvironment =
        "LONG=" + std::string(96 * 1024, 'e');
    const std::vector<std::string> arguments = {"", longArgument};
    const std::vector<std::string> environment = {"EMPTY=", longEnvironment};
    const std::vector<std::string> apple = {""};
    LC32GuestBootstrap::InitialStackImage image;
    std::string error;
    CHECK(LC32GuestBootstrap::BuildInitialStackImage(
        stackBase, stackSize, 0x11000000,
        arguments, environment, apple, &image, &error));
    CHECK(error.empty());
    CheckStackLayout(stackBase, stackSize, 0x11000000,
                     arguments, environment, apple, image);
}

void TestStackExhaustion() {
    LC32GuestBootstrap::InitialStackImage image;
    image.stackPointer = 0x12345678;
    image.strings.push_back({0x1000, "sentinel"});
    image.words.push_back(0xabcdef01);
    std::string error;

    CHECK(!LC32GuestBootstrap::BuildInitialStackImage(
        0x73000000, 0x1000, 0x11000000,
        {}, {}, {}, &image, &error));
    CHECK(!error.empty());
    CHECK(image.stackPointer == 0x12345678);
    CHECK(image.strings.size() == 1);
    CHECK(image.strings.front().value == "sentinel");
    CHECK(image.words.size() == 1);
    CHECK(image.words.front() == 0xabcdef01);

    error.clear();
    const std::vector<std::string> oversized = {
        std::string(0x3000, 'x'),
    };
    CHECK(!LC32GuestBootstrap::BuildInitialStackImage(
        0x73000000, 0x2000, 0x11000000,
        oversized, {}, {}, &image, &error, 0));
    CHECK(!error.empty());

    error.clear();
    CHECK(!LC32GuestBootstrap::BuildInitialStackImage(
        0xfffffffe, 1, 0x11000000,
        {}, {}, {}, &image, &error, 0));
    CHECK(!error.empty());
}

} // anonymous namespace

int main() {
    TestConfiguredHomeDirectory();
    TestConfiguredHomeResolution();
    TestLegacyBundleLayout();
    TestLiveContainerRelativeBundleLayout();
    TestRelativeBundleComponents();
    TestManagedLegacyBundleLayout();
    TestEnvironmentSelection();
    TestEnvironmentFinalization();
    TestDyldPrintOptIn();
    TestArgumentCountsAndAlignment();
    TestLargeArgumentVector();
    TestLongAndEmptyStrings();
    TestStackExhaustion();

    if(failures != 0) {
        std::cerr << failures << " guest bootstrap check(s) failed\n";
        return 1;
    }
    std::cout << "guest bootstrap host checks passed\n";
    return 0;
}

#include "guest_bootstrap.h"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <map>
#include <string>
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
    char trace[] = "LC32_GUEST_ENV_LC32_OBJC_TRACE=spoofed";
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
            "/var/mobile", "1", "0", &overridden);
    const std::map<std::string, std::string> values =
        ParseEnvironment(finalized);

    CHECK(values.at("HOME") == "/var/mobile");
    CHECK(values.at("LC32_OBJC_TRACE") == "1");
    CHECK(values.at("NATIVE_GUEST_THREADS") == "0");
    CHECK(values.at("DYLD_SHARED_REGION") == "private");
    CHECK(values.at("CUSTOM") == "value");
    CHECK(overridden.size() == 4);
    CHECK(Contains(overridden, "HOME"));
    CHECK(Contains(overridden, "LC32_OBJC_TRACE"));
    CHECK(Contains(overridden, "NATIVE_GUEST_THREADS"));
    CHECK(Contains(overridden, "DYLD_SHARED_REGION"));
}

void TestDyldPrintOptIn() {
    char unrelated[] = "LC32_GUEST_ENV_APPLICATION_MODE=test";
    char *defaultSource[] = {unrelated, nullptr};
    const std::vector<std::string> defaults =
        LC32GuestBootstrap::FinalizeEnvironment(
            LC32GuestBootstrap::CollectEnvironment(defaultSource),
            "/var/mobile", "0", "0");
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
            "/var/mobile", "0", "0"));
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

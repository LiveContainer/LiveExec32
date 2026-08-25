#include "guest_bootstrap.h"

#include <cctype>
#include <limits>
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

} // anonymous namespace

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
        const std::string &objcTrace,
        const std::string &nativeGuestThreads,
        std::vector<std::string> *overriddenNames) {
    auto setLauncherValue = [&](const char *name, const std::string &value) {
        if(overriddenNames && selection.values.count(name)) {
            overriddenNames->push_back(name);
        }
        selection.values[name] = value;
    };

    setLauncherValue("HOME", guestHome);
    setLauncherValue("LC32_OBJC_TRACE", objcTrace);
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

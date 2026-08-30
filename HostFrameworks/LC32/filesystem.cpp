#include <array>
#include <cstring>
#include <errno.h>
#include <unistd.h>
#include "dynarmic.h"
#include "darwin_file_syscalls.h"
#include "filesystem.h"

using namespace std;

namespace {

bool NormalizeGuestAbsolutePath(const char *input, char output[PATH_MAX]) {
    if(input == nullptr || output == nullptr) {
        errno = EFAULT;
        return false;
    }
    if(input[0] != '/') {
        errno = EINVAL;
        return false;
    }

    size_t inputLength = 0;
    while(inputLength < PATH_MAX && input[inputLength] != '\0') {
        ++inputLength;
    }
    if(inputLength == PATH_MAX) {
        errno = ENAMETOOLONG;
        return false;
    }

    size_t terminalEnd = inputLength;
    while(terminalEnd > 1 && input[terminalEnd - 1] == '/') {
        --terminalEnd;
    }
    size_t terminalStart = terminalEnd;
    while(terminalStart > 0 && input[terminalStart - 1] != '/') {
        --terminalStart;
    }
    const size_t terminalLength = terminalEnd - terminalStart;
    const bool preserveTerminalDirectoryComponent =
        (terminalLength == 1 && input[terminalStart] == '.') ||
        (terminalLength == 2 && input[terminalStart] == '.' &&
            input[terminalStart + 1] == '.');

    /* Store the output length before each retained component. Popping that
     * length for `..` clamps traversal at the guest root without ever
     * constructing a host path outside the selected mount. */
    std::array<size_t, PATH_MAX / 2 + 1> componentRewind{};
    size_t componentCount = 0;
    size_t outputLength = 1;
    output[0] = '/';

    size_t cursor = 0;
    while(cursor < inputLength) {
        while(cursor < inputLength && input[cursor] == '/') {
            ++cursor;
        }
        const size_t componentStart = cursor;
        while(cursor < inputLength && input[cursor] != '/') {
            ++cursor;
        }
        const size_t componentLength = cursor - componentStart;
        if(componentLength == 0 ||
                (componentLength == 1 && input[componentStart] == '.')) {
            continue;
        }
        if(componentLength == 2 && input[componentStart] == '.' &&
                input[componentStart + 1] == '.') {
            if(componentCount != 0) {
                outputLength = componentRewind[--componentCount];
            }
            continue;
        }

        const size_t separatorLength = outputLength == 1 ? 0 : 1;
        if(componentLength >=
                PATH_MAX - outputLength - separatorLength) {
            errno = ENAMETOOLONG;
            return false;
        }
        componentRewind[componentCount++] = outputLength;
        if(separatorLength != 0) {
            output[outputLength++] = '/';
        }
        memcpy(output + outputLength, input + componentStart,
            componentLength);
        outputLength += componentLength;
    }

    if(preserveTerminalDirectoryComponent) {
        const size_t suffixLength = outputLength == 1 ? 1 : 2;
        if(outputLength + suffixLength >= PATH_MAX) {
            errno = ENAMETOOLONG;
            return false;
        }
        if(outputLength != 1) {
            output[outputLength++] = '/';
        }
        output[outputLength++] = '.';
    } else if(inputLength > 1 && input[inputLength - 1] == '/' &&
            outputLength > 1) {
        if(outputLength + 1 >= PATH_MAX) {
            errno = ENAMETOOLONG;
            return false;
        }
        output[outputLength++] = '/';
    }
    output[outputLength] = '\0';
    return true;
}

} // anonymous namespace

// Returns true if a target path starts with base
bool LC32Filesystem::isSubpath(const string& target, const string& base) {
    size_t baseSize = base.size();
    if(target.size() < baseSize) {
        return false;
    }
    const char *lastChar = &target[baseSize];
    return target.rfind(base, 0) == 0 && (*lastChar == 0 || *lastChar == '/');
}

void LC32Filesystem::addMountpoint(string guest, string host) {
    char realHostPath[PATH_MAX];
    if(realpath(host.c_str(), realHostPath) == nullptr) {
        return;
    }
    guestmpVec.push_back(guest);
    hostmpVec.push_back(realHostPath);
}

// Translate path between emulated mount point paths
bool LC32Filesystem::pathLeftToRight(vector<string> leftVec, vector<string> rightVec, const char *input, char *output) {
    if(input == nullptr || output == nullptr) {
        errno = EFAULT;
        return false;
    }
    if(input[0] != '/') {
        // guest->host catches relative paths beforehand; host->guest paths
        // must always be absolute.
        errno = EINVAL;
        return false;
    }

    string rightRootfsPath;
    vector<string>::iterator rmp, lmp;
    for(rmp = rightVec.begin(), lmp = leftVec.begin(); rmp < rightVec.end(); rmp++, lmp++) {
        if(*lmp == "/") {
          // make sure we don't append / twice
          rightRootfsPath = *rmp;
        } else if(isSubpath(input, *lmp)) {
            size_t leftmpLen = lmp->size();
            input += leftmpLen;
            // make sure we don't append / twice
            const int length = snprintf(
                output, PATH_MAX, "%s%s",
                (*rmp == "/" && input[0] != 0) ? "" : rmp->c_str(),
                input);
            if(length < 0 || length >= PATH_MAX) {
                errno = ENAMETOOLONG;
                return false;
            }
            return true;
        }
    }

    const int length = snprintf(
        output, PATH_MAX, "%s%s", rightRootfsPath.c_str(), input);
    if(length < 0 || length >= PATH_MAX) {
        errno = ENAMETOOLONG;
        return false;
    }
    return true;
}

bool LC32Filesystem::pathGuestToHost(const char *input, char *output) {
    if(input == nullptr || output == nullptr) {
        errno = EFAULT;
        return false;
    }
    if(input[0] == '\0') {
        errno = ENOENT;
        return false;
    }
    // FIXME: resolving guest symlink (eg /tmp -> /private/var/tmp -> (host)/tmp)
    char normalizedPath[PATH_MAX];
    if(input[0] != '/') {
        // relative path is more complex as we have to prepend cwd then translate the path back and forth
        char hostCWD[PATH_MAX];
        char guestCWD[PATH_MAX];
        char guestPath[PATH_MAX];
        if(getcwd(hostCWD, sizeof(hostCWD)) == nullptr ||
                !pathHostToGuest(hostCWD, guestCWD)) {
            return false;
        }
        const int length = snprintf(
            guestPath, sizeof(guestPath), "%s/%s", guestCWD, input);
        if(length < 0 || length >= static_cast<int>(sizeof(guestPath))) {
            errno = ENAMETOOLONG;
            return false;
        }
        if(!NormalizeGuestAbsolutePath(guestPath, normalizedPath)) {
            return false;
        }
    } else if(!NormalizeGuestAbsolutePath(input, normalizedPath)) {
        return false;
    }
    return pathLeftToRight(
        guestmpVec, hostmpVec, normalizedPath, output);
}

bool LC32Filesystem::pathGuestToHost(u32 inputAddr, char *output) {
    const int error = LC32GuestPathToHost(inputAddr, output);
    if(error != 0) {
        errno = error;
        return false;
    }
    return true;
}

bool LC32Filesystem::pathHostToGuest(const char *input, char *output) {
    if(input == nullptr || output == nullptr) {
        errno = EFAULT;
        return false;
    }
    return pathLeftToRight(hostmpVec, guestmpVec, input, output);
}

bool LC32Filesystem::pathHostToGuest(const char *input, u32 outputAddr) {
    if(input == nullptr || outputAddr == 0) {
        errno = EFAULT;
        return false;
    }
    DynarmicHostString output(outputAddr);
    if(output.hostPtr == nullptr) {
        errno = EFAULT;
        return false;
    }
    return pathLeftToRight(hostmpVec, guestmpVec, input, output.hostPtrForWriting());
}

#if 0
void test() {
    LC32Filesystem fs;
    fs.addMountpoint("/var/mobile", "/var/tmp");
    fs.addMountpoint("/rootfs", "/");
    fs.addMountpoint("/", "/var/mobile/rootfs");
    char buffer[PATH_MAX];
    
    // host to guest rootfs
    bzero(buffer, PATH_MAX);
    fs.pathHostToGuest("/var/mobile/rootfs/var/mobile/hello.txt", buffer);
    printf("path=%s\n", buffer);
    
    // host to guest unmounted
    bzero(buffer, PATH_MAX);
    fs.pathHostToGuest("/var/unmounted/tmp/mobile/fake/hello.txt", buffer);
    printf("path=%s\n", buffer);
    
    // host to guest mounted
    bzero(buffer, PATH_MAX);
    fs.pathHostToGuest("/var/tmp/test/fake/hello.txt", buffer);
    printf("path=%s\n", buffer);
    
    // guest to host rootfs
    bzero(buffer, PATH_MAX);
    fs.pathGuestToHost("/rootfs", buffer);
    printf("GTHpath=%s\n", buffer);
    
    // guest to host rootfs
    bzero(buffer, PATH_MAX);
    fs.pathGuestToHost("/rootfs/var/mobile/test.txt", buffer);
    printf("GTHpath=%s\n", buffer);
    
    // guest mounted to host
    bzero(buffer, PATH_MAX);
    fs.pathGuestToHost("/var/mobile/test.txt", buffer);
    printf("GTHpath=%s\n", buffer);
    
    // guest to host rootfs
    bzero(buffer, PATH_MAX);
    fs.pathGuestToHost("/System/Library/test.txt", buffer);
    printf("GTHpath=%s\n", buffer);
}
#endif

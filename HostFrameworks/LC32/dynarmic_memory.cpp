#include "dynarmic_internal.h"

////////
int guestMappingLen = 0;
guest_file_mapping guestMappings[1000];
size_t guestMappingGeneration = 0;

static void AppendDyldGuestImages(
    std::vector<GuestImageSnapshot> &images);

std::vector<GuestImageSnapshot> SnapshotGuestImages() {
    std::vector<GuestImageSnapshot> images;
    {
        std::lock_guard<std::mutex> lock(guestMappingMutex);
        const int count = std::max(0, std::min(guestMappingLen, 1000));
        images.reserve(static_cast<size_t>(count));
        for (int index = 0; index < count; ++index) {
            const guest_file_mapping &mapping = guestMappings[index];
            images.push_back({
                mapping.start,
                mapping.end,
                mapping.name != nullptr
                    ? std::string(mapping.name,
                        strnlen(mapping.name, PATH_MAX))
                    : "(unknown image)",
            });
        }
    }

    /*
     * The synthetic dyld Mach-port notification is optional and may not have
     * run before a guest crashes.  guestMappings then contains only the main
     * executable and dyld, leaving every system-library frame nameless.  The
     * all-image-info array is dyld's authoritative, already-published image
     * list. Treat it as a best-effort snapshot: every pointer, range, and
     * Mach-O header is validated below in case a non-crash diagnostic races
     * an image update.
     */
    AppendDyldGuestImages(images);
    return images;
}

static bool GuestImageLoadCommandsAreSane(
        const mach_header *header) {
    return header != nullptr && header->magic == MH_MAGIC &&
        header->ncmds <= 4096 && header->sizeofcmds <= 1024 * 1024;
}

struct GuestMachOImage {
    mach_header header{};
    std::vector<uint8_t> loadCommands;
};

static bool ReadGuestMachOImage(
        const GuestImageSnapshot &mapping,
        GuestMachOImage &image) {
    if (!read_guest_memory_with_permissions(
            mapping.start, &image.header, sizeof(image.header),
            PROT_READ) ||
            !GuestImageLoadCommandsAreSane(&image.header)) {
        return false;
    }

    image.loadCommands.resize(image.header.sizeofcmds);
    return image.loadCommands.empty() ||
        read_guest_memory_with_permissions(
            static_cast<u64>(mapping.start) + sizeof(image.header),
            image.loadCommands.data(), image.loadCommands.size(),
            PROT_READ);
}

static u32 GuestImageSlide(
        const GuestImageSnapshot &mapping,
        const GuestMachOImage &image) {
    size_t cursor = 0;
    for (uint32_t index = 0; index < image.header.ncmds; ++index) {
        if (cursor + sizeof(load_command) > image.loadCommands.size()) {
            break;
        }
        load_command command{};
        memcpy(&command, image.loadCommands.data() + cursor,
            sizeof(command));
        if (command.cmdsize < sizeof(load_command) ||
                command.cmdsize > image.loadCommands.size() - cursor) {
            break;
        }
        if (command.cmd == LC_SEGMENT &&
                command.cmdsize >= sizeof(segment_command)) {
            segment_command segment{};
            memcpy(&segment, image.loadCommands.data() + cursor,
                sizeof(segment));
            if (strncmp(segment.segname, "__PAGEZERO",
                    sizeof(segment.segname)) != 0) {
                return mapping.start - segment.vmaddr;
            }
        }
        cursor += command.cmdsize;
    }
    return mapping.start;
}

struct DyldAllImageInfosPrefix32 {
    uint32_t version;
    uint32_t infoArrayCount;
    uint32_t infoArray;
};

struct DyldImageInfo32 {
    uint32_t imageLoadAddress;
    uint32_t imageFilePath;
    uint32_t imageFileModDate;
};

static bool GuestImageTextRange(
        const GuestImageSnapshot &mapping,
        const GuestMachOImage &image,
        u32 *textStart, u32 *textEnd) {
    const u32 slide = GuestImageSlide(mapping, image);
    size_t cursor = 0;
    for (uint32_t index = 0; index < image.header.ncmds; ++index) {
        if (cursor + sizeof(load_command) > image.loadCommands.size()) {
            return false;
        }
        load_command command{};
        memcpy(&command, image.loadCommands.data() + cursor,
            sizeof(command));
        if (command.cmdsize < sizeof(load_command) ||
                command.cmdsize > image.loadCommands.size() - cursor) {
            return false;
        }
        if (command.cmd == LC_SEGMENT &&
                command.cmdsize >= sizeof(segment_command)) {
            segment_command segment{};
            memcpy(&segment, image.loadCommands.data() + cursor,
                sizeof(segment));
            if (strncmp(segment.segname, SEG_TEXT,
                    sizeof(segment.segname)) == 0) {
                const u64 start = static_cast<u64>(slide) + segment.vmaddr;
                const u64 end = start + segment.vmsize;
                if (start > UINT32_MAX || end > UINT32_MAX || end <= start) {
                    return false;
                }
                *textStart = static_cast<u32>(start);
                *textEnd = static_cast<u32>(end);
                return true;
            }
        }
        cursor += command.cmdsize;
    }
    return false;
}

static void AppendDyldGuestImages(
        std::vector<GuestImageSnapshot> &images) {
    const u32 allImageInfosAddress =
        sharedHandle.dyld_info_guest_address;
    if (allImageInfosAddress == 0) {
        return;
    }

    DyldAllImageInfosPrefix32 allImageInfos{};
    if (!read_guest_memory_with_permissions(
            allImageInfosAddress, &allImageInfos,
            sizeof(allImageInfos), PROT_READ) ||
            allImageInfos.infoArrayCount == 0 ||
            allImageInfos.infoArrayCount > 4096 ||
            allImageInfos.infoArray == 0) {
        return;
    }

    const u64 infosSize =
        static_cast<u64>(allImageInfos.infoArrayCount) *
        sizeof(DyldImageInfo32);
    if (!GuestAddressRangeIsValid32(
            allImageInfos.infoArray, infosSize)) {
        return;
    }
    std::vector<DyldImageInfo32> dyldImages(
        allImageInfos.infoArrayCount);
    if (!read_guest_memory_with_permissions(
            allImageInfos.infoArray, dyldImages.data(),
            static_cast<size_t>(infosSize), PROT_READ)) {
        return;
    }

    for (const DyldImageInfo32 &dyldImage : dyldImages) {
        if (dyldImage.imageLoadAddress == 0) {
            continue;
        }
        const auto existing = std::find_if(
            images.begin(), images.end(),
            [&dyldImage](const GuestImageSnapshot &image) {
                return image.start == dyldImage.imageLoadAddress;
            });
        if (existing != images.end()) {
            continue;
        }

        GuestImageSnapshot mapping{
            dyldImage.imageLoadAddress,
            dyldImage.imageLoadAddress,
            CopyGuestCStringForCrash(
                dyldImage.imageFilePath, PATH_MAX),
        };
        if (mapping.name.empty()) {
            mapping.name = "(unknown image)";
        }
        GuestMachOImage image;
        u32 textStart = 0;
        u32 textEnd = 0;
        if (!ReadGuestMachOImage(mapping, image) ||
                !GuestImageTextRange(
                    mapping, image, &textStart, &textEnd)) {
            continue;
        }
        mapping.start = textStart;
        mapping.end = textEnd;
        images.push_back(std::move(mapping));
    }
}

static bool GuestFileOffsetAddress(
        const GuestMachOImage &image, u32 slide,
        uint32_t fileOffset, u64 size, u32 *address) {
    size_t cursor = 0;
    for (uint32_t index = 0; index < image.header.ncmds; ++index) {
        if (cursor + sizeof(load_command) > image.loadCommands.size()) {
            return false;
        }
        load_command command{};
        memcpy(&command, image.loadCommands.data() + cursor,
            sizeof(command));
        if (command.cmdsize < sizeof(load_command) ||
                command.cmdsize > image.loadCommands.size() - cursor) {
            return false;
        }
        if (command.cmd == LC_SEGMENT &&
                command.cmdsize >= sizeof(segment_command)) {
            segment_command segment{};
            memcpy(&segment, image.loadCommands.data() + cursor,
                sizeof(segment));
            const u64 segmentFileStart = segment.fileoff;
            const u64 segmentFileEnd =
                segmentFileStart + segment.filesize;
            const u64 requestedStart = fileOffset;
            const u64 requestedEnd = requestedStart + size;
            if (segmentFileEnd >= segmentFileStart &&
                    requestedEnd >= requestedStart &&
                    requestedStart >= segmentFileStart &&
                    requestedEnd <= segmentFileEnd) {
                const u64 resolved = static_cast<u64>(slide) +
                    segment.vmaddr +
                    (requestedStart - segmentFileStart);
                if (resolved <= UINT32_MAX &&
                        size <= UINT32_MAX - resolved + 1) {
                    *address = static_cast<u32>(resolved);
                    return true;
                }
                return false;
            }
        }
        cursor += command.cmdsize;
    }
    return false;
}

std::vector<GuestCrashAnnotation>
CollectGuestCrashAnnotations(
        const std::vector<GuestImageSnapshot> &images) {
    std::vector<GuestCrashAnnotation> annotations;
    std::unordered_set<std::string> seenMessages;
    size_t annotationBytes = 0;
    for (const GuestImageSnapshot &mapping : images) {
        if (annotations.size() >= LC32_CRASH_ANNOTATIONS_MAX ||
                annotationBytes >= LC32_CRASH_ANNOTATION_BYTES_MAX) {
            break;
        }
        GuestMachOImage image;
        if (!ReadGuestMachOImage(mapping, image)) {
            continue;
        }
        const u32 slide = GuestImageSlide(mapping, image);
        size_t cursor = 0;
        u32 crashInfoAddress = 0;
        uint32_t crashInfoSize = 0;
        for (uint32_t index = 0; index < image.header.ncmds; ++index) {
            if (cursor + sizeof(load_command) > image.loadCommands.size()) {
                break;
            }
            load_command command{};
            memcpy(&command, image.loadCommands.data() + cursor,
                sizeof(command));
            if (command.cmdsize < sizeof(load_command) ||
                    command.cmdsize > image.loadCommands.size() - cursor) {
                break;
            }
            if (command.cmd == LC_SEGMENT &&
                    command.cmdsize >= sizeof(segment_command)) {
                segment_command segment{};
                memcpy(&segment, image.loadCommands.data() + cursor,
                    sizeof(segment));
                const size_t sectionsBytes =
                    command.cmdsize - sizeof(segment_command);
                if (segment.nsects <=
                        sectionsBytes / sizeof(section)) {
                    for (uint32_t sectionIndex = 0;
                            sectionIndex < segment.nsects; ++sectionIndex) {
                        section currentSection{};
                        memcpy(&currentSection,
                            image.loadCommands.data() + cursor +
                                sizeof(segment_command) +
                                static_cast<size_t>(sectionIndex) *
                                    sizeof(section),
                            sizeof(currentSection));
                        if (strncmp(currentSection.sectname,
                                "__crash_info",
                                sizeof(currentSection.sectname)) == 0) {
                            const u64 address = static_cast<u64>(slide) +
                                currentSection.addr;
                            if (address <= UINT32_MAX) {
                                crashInfoAddress = static_cast<u32>(address);
                                crashInfoSize = currentSection.size;
                            }
                            break;
                        }
                    }
                }
            }
            if (crashInfoAddress != 0) {
                break;
            }
            cursor += command.cmdsize;
        }

        if (crashInfoAddress == 0 ||
                crashInfoSize < sizeof(crashreporter_annotations_t)) {
            continue;
        }
        crashreporter_annotations_t annotation{};
        if (!read_guest_memory_with_permissions(
                crashInfoAddress, &annotation, sizeof(annotation),
                PROT_READ)) {
            continue;
        }
        const uint64_t messageAddresses[] = {
            annotation.message,
            annotation.message2,
        };
        for (const uint64_t messageAddress : messageAddresses) {
            const size_t remainingBytes =
                LC32_CRASH_ANNOTATION_BYTES_MAX - annotationBytes;
            if (annotations.size() >= LC32_CRASH_ANNOTATIONS_MAX ||
                    remainingBytes == 0) {
                break;
            }
            std::string message = CopyGuestCStringForCrash(
                messageAddress,
                std::min<size_t>(16 * 1024, remainingBytes));
            if (message.size() > remainingBytes) {
                message.resize(remainingBytes);
            }
            if (message.empty() || !seenMessages.insert(message).second) {
                continue;
            }
            annotationBytes += message.size();
            annotations.push_back({
                mapping.name,
                std::move(message),
                annotation.abort_cause,
            });
        }
    }
    return annotations;
}

static void load_symbols_for_image(
        const GuestImageSnapshot &mapping,
        void (^iterator)(u32 address, const char *name)) {
    GuestMachOImage image;
    if (!ReadGuestMachOImage(mapping, image)) {
        return;
    }
    const u32 slide = GuestImageSlide(mapping, image);
    symtab_command symbolTable{};
    bool foundSymbolTable = false;
    size_t cursor = 0;
    for (uint32_t index = 0; index < image.header.ncmds; ++index) {
        if (cursor + sizeof(load_command) > image.loadCommands.size()) {
            break;
        }
        load_command command{};
        memcpy(&command, image.loadCommands.data() + cursor,
            sizeof(command));
        if (command.cmdsize < sizeof(load_command) ||
                command.cmdsize > image.loadCommands.size() - cursor) {
            break;
        }
        if (command.cmd == LC_SYMTAB &&
                command.cmdsize >= sizeof(symtab_command)) {
            memcpy(&symbolTable, image.loadCommands.data() + cursor,
                sizeof(symbolTable));
            foundSymbolTable = true;
            break;
        }
        cursor += command.cmdsize;
    }

    iterator(mapping.start, "(unknown symbol)");
    if (!foundSymbolTable ||
            symbolTable.nsyms > LC32_CRASH_SYMBOLS_MAX) {
        return;
    }

    const u64 symbolTableSize =
        static_cast<u64>(symbolTable.nsyms) * sizeof(struct nlist);
    u32 symbolTableAddress = 0;
    u32 stringTableAddress = 0;
    /*
     * LC_SYMTAB offsets are file offsets, not offsets from the Mach header.
     * Those happen to be equivalent for ordinary split-segment images, but
     * not for images whose __LINKEDIT was rearranged in a dyld shared cache.
     * Translate each offset through the segment that owns its file range and
     * then apply the image slide.
     */
    if (!GuestFileOffsetAddress(
            image, slide, symbolTable.symoff,
            symbolTableSize, &symbolTableAddress) ||
            !GuestFileOffsetAddress(
                image, slide, symbolTable.stroff,
                symbolTable.strsize, &stringTableAddress) ||
            !GuestAddressRangeIsValid32(
                symbolTableAddress, symbolTableSize) ||
            !GuestAddressRangeIsValid32(
                stringTableAddress, symbolTable.strsize)) {
        return;
    }
    for (uint32_t index = 0; index < symbolTable.nsyms; ++index) {
        const u64 entryAddress = symbolTableAddress +
            static_cast<u64>(index) * sizeof(struct nlist);
        struct nlist entry{};
        if (!read_guest_memory_with_permissions(
                entryAddress, &entry, sizeof(entry), PROT_READ)) {
            break;
        }
        if ((entry.n_type & N_STAB) != 0 ||
                (entry.n_type & N_TYPE) != N_SECT ||
                entry.n_un.n_strx == 0 ||
                entry.n_un.n_strx >= symbolTable.strsize ||
                entry.n_value == 0) {
            continue;
        }
        const u64 resolvedAddress =
            static_cast<u64>(entry.n_value) + slide;
        if (resolvedAddress < mapping.start ||
                resolvedAddress >= mapping.end) {
            continue;
        }
        const size_t maximumNameLength = std::min<size_t>(
            1024, symbolTable.strsize - entry.n_un.n_strx);
        std::string name = CopyGuestCStringForCrash(
            stringTableAddress + entry.n_un.n_strx,
            maximumNameLength);
        if (!name.empty()) {
            iterator(static_cast<u32>(resolvedAddress), name.c_str());
        }
    }
}

void symbolicate_call_stack(
        symbolicated_call *callStack, int callStackLen,
        const std::vector<GuestImageSnapshot> &images) {
    for (const GuestImageSnapshot &mapping : images) {
        bool containsFrame = false;
        for (int index = 0; index < callStackLen; ++index) {
            symbolicated_call &call = callStack[index];
            if (call.address >= mapping.start && call.address < mapping.end) {
                call.imageName = mapping.name;
                call.symbolOffset = call.address - mapping.start;
                containsFrame = true;
            }
        }
        if (!containsFrame) {
            continue;
        }
        load_symbols_for_image(mapping, ^(u32 address, const char *name) {
            for (int index = 0; index < callStackLen; ++index) {
                symbolicated_call &call = callStack[index];
                if (call.address < mapping.start ||
                        call.address >= mapping.end ||
                        call.address < address) {
                    continue;
                }
                const u32 offset = call.address - address;
                if (call.symbolName.empty() || offset < call.symbolOffset) {
                    call.imageName = mapping.name;
                    call.symbolName = name;
                    call.symbolOffset = offset;
                }
            }
        });
    }
}

char *get_memory_page(u64 vaddr) {
    size_t num_page_table_entries = sharedHandle.num_page_table_entries;
    void **page_table = sharedHandle.page_table;
    khash_t(memory) *memory = sharedHandle.memory;
    u64 idx = vaddr >> DYN_PAGE_BITS;
    if(page_table && idx < num_page_table_entries) {
      char *fastPage = static_cast<char *>(
          __atomic_load_n(
              &page_table[idx], __ATOMIC_ACQUIRE));
      if (fastPage != nullptr) return fastPage;
    }
    std::lock_guard<std::recursive_mutex> lock(guestVmMutex);
    u64 base = vaddr & ~DYN_PAGE_MASK;
    khiter_t k = kh_get(memory, memory, base);
    if(k == kh_end(memory)) {
      return NULL;
    }
    t_memory_page page = kh_value(memory, k);
    return (char *)page->addr;
}

void *get_memory(u64 vaddr) {
    char *page = get_memory_page(vaddr);
    return page ? &page[vaddr & DYN_PAGE_MASK] : NULL;
}

int HostProtectionForGuestPermissions(
        int permissions) {
    int hostProtection =
        permissions & (PROT_READ | PROT_WRITE);
    /*
     * Guest execute permission is implemented by MemoryReadCode rather than
     * host execution, but translating execute-only pages still needs to read
     * their instruction bytes.
     */
    if ((permissions & PROT_EXEC) != 0) {
        hostProtection |= PROT_READ;
    }
    return hostProtection;
}

void *GuestPageTablePointer(
        u64 guestPageAddress,
        const t_memory_page page) {
    if (page == nullptr || page->addr == nullptr) {
        return nullptr;
    }
#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
    if (GuestMemoryWatchContainsPage(guestPageAddress)) {
        return nullptr;
    }
#endif
    if (page->enforceDataPermissions &&
            (page->perms &
                (PROT_READ | PROT_WRITE)) !=
                (PROT_READ | PROT_WRITE)) {
        return nullptr;
    }
    return page->addr;
}

#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
bool SnapshotGuestMemoryWatchLocked(u32 *value) {
    if (value == nullptr || sharedHandle.memory == nullptr) {
        return false;
    }

    u32 snapshot = 0;
    auto *output = reinterpret_cast<uint8_t *>(&snapshot);
    u64 address = guestMemoryWatchAddress;
    size_t remaining = sizeof(snapshot);
    while (remaining != 0) {
        const u64 pageAddress = address & ~u64(DYN_PAGE_MASK);
        const khiter_t iterator = kh_get(
            memory, sharedHandle.memory, pageAddress);
        if (iterator == kh_end(sharedHandle.memory)) {
            return false;
        }
        const t_memory_page page =
            kh_value(sharedHandle.memory, iterator);
        if (page == nullptr || page->addr == nullptr) {
            return false;
        }
        const size_t pageOffset = address & DYN_PAGE_MASK;
        const size_t chunk = std::min(
            remaining,
            static_cast<size_t>(DYN_PAGE_SIZE - pageOffset));
        memcpy(output,
            static_cast<const uint8_t *>(page->addr) + pageOffset,
            chunk);
        output += chunk;
        address += chunk;
        remaining -= chunk;
    }
    *value = snapshot;
    return true;
}

void LogGuestMemoryWatchConsistencyLocked(
        const char *reason) {
    const u64 pageAddress =
        guestMemoryWatchAddress & ~u64(DYN_PAGE_MASK);
    const u64 pageIndex = pageAddress >> DYN_PAGE_BITS;
    void *pageTablePointer = nullptr;
    if (sharedHandle.page_table != nullptr &&
            pageIndex < sharedHandle.num_page_table_entries) {
        pageTablePointer = __atomic_load_n(
            &sharedHandle.page_table[pageIndex],
            __ATOMIC_ACQUIRE);
    }

    t_memory_page page = nullptr;
    if (sharedHandle.memory != nullptr) {
        const khiter_t iterator = kh_get(
            memory, sharedHandle.memory, pageAddress);
        if (iterator != kh_end(sharedHandle.memory)) {
            page = kh_value(sharedHandle.memory, iterator);
        }
    }

    u32 authoritativeValue = 0;
    const bool hasAuthoritativeValue =
        SnapshotGuestMemoryWatchLocked(&authoritativeValue);
    fprintf(stderr,
        "LC32 guest memory watch snapshot: reason=%s "
        "guest=0x%08llx page=0x%08llx index=0x%llx "
        "pte=%p khash_page=%p khash_addr=%p "
        "perms=0x%x enforce=%d backing=%p backing_addr=%p "
        "backing_size=0x%zx value=%s%08x match=%d\n",
        reason != nullptr ? reason : "unknown",
        guestMemoryWatchAddress, pageAddress, pageIndex,
        pageTablePointer, static_cast<void *>(page),
        page != nullptr ? page->addr : nullptr,
        page != nullptr ? page->perms : 0,
        page != nullptr ? page->enforceDataPermissions : false,
        page != nullptr
            ? static_cast<void *>(page->backing) : nullptr,
        page != nullptr && page->backing != nullptr
            ? page->backing->addr : nullptr,
        page != nullptr && page->backing != nullptr
            ? page->backing->size : 0,
        hasAuthoritativeValue ? "" : "unmapped/",
        authoritativeValue,
        page != nullptr && pageTablePointer == page->addr);
}

void LogGuestMemoryWatchConsistency(
        const char *reason) {
    std::lock_guard<std::recursive_mutex> lock(
        guestVmMutex);
    LogGuestMemoryWatchConsistencyLocked(reason);
}

void LogGuestMemoryWatchWriteLocked(
        const char *operation, u64 address, size_t size,
        bool hadOldValue, u32 oldValue) {
    if (!GuestMemoryWatchOverlaps(address, size)) {
        return;
    }
    u32 newValue = 0;
    const bool hasNewValue =
        SnapshotGuestMemoryWatchLocked(&newValue);
    const u32 pc = threadHandle.jit != nullptr
        ? threadHandle.jit->Regs()[Reg::PC] : 0;
    const u32 lr = threadHandle.jit != nullptr
        ? threadHandle.jit->Regs()[Reg::LR] : 0;
    fprintf(stderr,
        "LC32 guest memory watch: op=%s write=0x%08llx+0x%zx "
        "old=%s%08x new=%s%08x pc=%08x lr=%08x host_thread=%u\n",
        operation, address, size,
        hadOldValue ? "" : "unmapped/", oldValue,
        hasNewValue ? "" : "unmapped/", newValue,
        pc, lr, pthread_mach_thread_np(pthread_self()));
}
#endif

char *get_memory_page_with_permissions(
        u64 vaddr, int requiredPermissions) {
    std::lock_guard<std::recursive_mutex> lock(
        guestVmMutex);
    khash_t(memory) *memory = sharedHandle.memory;
    if (memory == nullptr) {
        return nullptr;
    }
    const u64 base = vaddr & ~DYN_PAGE_MASK;
    const khiter_t iterator =
        kh_get(memory, memory, base);
    if (iterator == kh_end(memory)) {
        return nullptr;
    }
    const t_memory_page page =
        kh_value(memory, iterator);
    if (page == nullptr ||
            (page->perms & requiredPermissions) !=
                requiredPermissions) {
        return nullptr;
    }
    return static_cast<char *>(page->addr);
}

bool GuestAddressRangeIsValid32(
        u64 address, u64 size) {
    constexpr u64 addressSpaceSize =
        UINT64_C(1) << 32;
    return address < addressSpaceSize &&
        size <= addressSpaceSize - address;
}

enum class GuestVmRangeStatus {
    Valid,
    InvalidAddress,
    ProtectionFailure,
};

static GuestVmRangeStatus ValidateGuestVmRangeLocked(
        u64 address, size_t size,
        int requiredPermissions) {
    if (!GuestAddressRangeIsValid32(address, size)) {
        return GuestVmRangeStatus::InvalidAddress;
    }
    khash_t(memory) *memory = sharedHandle.memory;
    if (memory == nullptr) {
        return GuestVmRangeStatus::InvalidAddress;
    }
    while (size != 0) {
        const u64 pageAddress =
            address & ~u64(DYN_PAGE_MASK);
        const khiter_t iterator =
            kh_get(memory, memory, pageAddress);
        if (iterator == kh_end(memory)) {
            return GuestVmRangeStatus::InvalidAddress;
        }
        const t_memory_page page =
            kh_value(memory, iterator);
        if (page == nullptr || page->addr == nullptr) {
            return GuestVmRangeStatus::InvalidAddress;
        }
        if ((page->perms & requiredPermissions) !=
                requiredPermissions) {
            return GuestVmRangeStatus::ProtectionFailure;
        }
        const size_t pageOffset =
            address & DYN_PAGE_MASK;
        const size_t chunk = std::min(
            size, static_cast<size_t>(
                DYN_PAGE_SIZE - pageOffset));
        address += chunk;
        size -= chunk;
    }
    return GuestVmRangeStatus::Valid;
}

static kern_return_t GuestVmRangeStatusToKernReturn(
        GuestVmRangeStatus status) {
    switch (status) {
        case GuestVmRangeStatus::Valid:
            return KERN_SUCCESS;
        case GuestVmRangeStatus::InvalidAddress:
            return KERN_INVALID_ADDRESS;
        case GuestVmRangeStatus::ProtectionFailure:
            return KERN_PROTECTION_FAILURE;
    }
    return KERN_FAILURE;
}

kern_return_t CopyGuestVmMemory(
        u32 source, u32 destination, u32 size) {
    /* vm_copy accepts an empty range without inspecting either address. */
    if (size == 0) {
        return KERN_SUCCESS;
    }

    std::lock_guard<std::recursive_mutex> lock(
        guestVmMutex);
    const GuestVmRangeStatus sourceStatus =
        ValidateGuestVmRangeLocked(
            source, size, PROT_READ);
    if (sourceStatus != GuestVmRangeStatus::Valid) {
        return GuestVmRangeStatusToKernReturn(
            sourceStatus);
    }
    const GuestVmRangeStatus destinationStatus =
        ValidateGuestVmRangeLocked(
            destination, size, PROT_WRITE);
    if (destinationStatus != GuestVmRangeStatus::Valid) {
        return GuestVmRangeStatusToKernReturn(
            destinationStatus);
    }

    /*
     * XNU snapshots the source with vm_map_copyin before overwriting the
     * destination. A complete private copy preserves that behavior for
     * forward/backward overlap and for two guest virtual ranges that alias
     * the same backing memory.
     */
    std::vector<uint8_t> snapshot;
    try {
        snapshot.resize(size);
    } catch (const std::exception &) {
        return KERN_RESOURCE_SHORTAGE;
    }
    if (!read_guest_memory_with_permissions(
            source, snapshot.data(), snapshot.size(),
            PROT_READ) ||
        !write_guest_memory_with_permissions(
            destination, snapshot.data(), snapshot.size(),
            PROT_WRITE)) {
        /* The map is locked and was fully validated, so this is defensive. */
        return KERN_FAILURE;
    }
    return KERN_SUCCESS;
}

bool GuestProtectionIsValid(int protection) {
    constexpr int supportedProtection =
        PROT_READ | PROT_WRITE | PROT_EXEC;
    return (protection & ~supportedProtection) == 0;
}

bool guest_memory_range_has_permissions(
        u64 address, size_t size,
        int requiredPermissions) {
    if (!GuestAddressRangeIsValid32(address, size)) {
        return false;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestVmMutex);
    while (size != 0) {
        if (get_memory_page_with_permissions(
                address, requiredPermissions) == nullptr) {
            return false;
        }
        const size_t pageOffset =
            address & DYN_PAGE_MASK;
        const size_t chunk = std::min(
            size, static_cast<size_t>(
                DYN_PAGE_SIZE - pageOffset));
        address += chunk;
        size -= chunk;
    }
    return true;
}

bool read_guest_memory_with_permissions(
        u64 address, void *destination, size_t size,
        int requiredPermissions) {
    if (!GuestAddressRangeIsValid32(
            address, size)) {
        return false;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestVmMutex);
    u64 validationAddress = address;
    size_t validationSize = size;
    while (validationSize != 0) {
        if (get_memory_page_with_permissions(
                validationAddress,
                requiredPermissions) == nullptr) {
            return false;
        }
        const size_t pageOffset =
            validationAddress & DYN_PAGE_MASK;
        const size_t chunk = std::min(
            validationSize,
            static_cast<size_t>(
                DYN_PAGE_SIZE - pageOffset));
        validationAddress += chunk;
        validationSize -= chunk;
    }

    auto *output = static_cast<uint8_t *>(
        destination);
    while (size != 0) {
        char *page =
            get_memory_page_with_permissions(
                address, requiredPermissions);
        if (page == nullptr) {
            return false;
        }
        const size_t pageOffset =
            address & DYN_PAGE_MASK;
        const size_t chunk = std::min(
            size,
            static_cast<size_t>(
                DYN_PAGE_SIZE - pageOffset));
        memcpy(output, page + pageOffset, chunk);
        output += chunk;
        address += chunk;
        size -= chunk;
    }
    return true;
}

std::string CopyGuestCStringForCrash(
        u64 guestAddress, size_t maximumLength) {
    if (guestAddress == 0 || maximumLength == 0 ||
            guestAddress > UINT32_MAX) {
        return {};
    }

    std::string result;
    result.reserve(std::min<size_t>(maximumLength, 256));
    while (result.size() < maximumLength) {
        const u64 address = guestAddress + result.size();
        if (address > UINT32_MAX) {
            break;
        }
        const size_t pageRemaining =
            DYN_PAGE_SIZE - (address & DYN_PAGE_MASK);
        const size_t chunkLength = std::min(
            maximumLength - result.size(), pageRemaining);
        std::array<char, DYN_PAGE_SIZE> chunk{};
        if (!read_guest_memory_with_permissions(
                address, chunk.data(), chunkLength,
                PROT_READ)) {
            break;
        }
        const void *terminator =
            memchr(chunk.data(), '\0', chunkLength);
        const size_t copiedLength = terminator != nullptr
            ? static_cast<const char *>(terminator) - chunk.data()
            : chunkLength;
        result.append(chunk.data(), copiedLength);
        if (terminator != nullptr) {
            return result;
        }
    }
    if (result.size() == maximumLength) {
        result.append(" [truncated]");
    } else if (!result.empty()) {
        result.append(" [unreadable]");
    }
    return result;
}

bool write_guest_memory_with_permissions(
        u64 address, const void *source, size_t size,
        int requiredPermissions) {
    if (!GuestAddressRangeIsValid32(
            address, size)) {
        return false;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestVmMutex);
#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
    const u64 originalAddress = address;
    const size_t originalSize = size;
#endif
    /*
     * Validate the complete range before modifying it. An unaligned scalar
     * store may span two guest pages; discovering a protected second page
     * after writing the first would make a faulting instruction partially
     * visible even though it has not retired.
     */
    u64 validationAddress = address;
    size_t validationSize = size;
    while (validationSize != 0) {
        if (get_memory_page_with_permissions(
                validationAddress,
                requiredPermissions) == nullptr) {
            return false;
        }
        const size_t pageOffset =
            validationAddress & DYN_PAGE_MASK;
        const size_t chunk = std::min(
            validationSize,
            static_cast<size_t>(
                DYN_PAGE_SIZE - pageOffset));
        validationAddress += chunk;
        validationSize -= chunk;
    }

    const auto *input =
        static_cast<const uint8_t *>(source);
#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
    u32 oldWatchedValue = 0;
    const bool hadOldWatchedValue =
        GuestMemoryWatchOverlaps(address, size) &&
        SnapshotGuestMemoryWatchLocked(&oldWatchedValue);
#endif
    while (size != 0) {
        char *page =
            get_memory_page_with_permissions(
                address, requiredPermissions);
        if (page == nullptr) {
            return false;
        }
        const size_t pageOffset =
            address & DYN_PAGE_MASK;
        const size_t chunk = std::min(
            size,
            static_cast<size_t>(
                DYN_PAGE_SIZE - pageOffset));
        memcpy(page + pageOffset, input, chunk);
        input += chunk;
        address += chunk;
        size -= chunk;
    }
#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
    LogGuestMemoryWatchWriteLocked(
        "permissioned", originalAddress, originalSize,
        hadOldWatchedValue, oldWatchedValue);
#endif
    return true;
}

struct __attribute__((packed, aligned(4))) GuestKevent32 {
    u32 ident;
    int16_t filter;
    uint16_t flags;
    uint32_t fflags;
    int32_t data;
    u32 udata;
};

struct __attribute__((packed, aligned(4))) GuestTimespec32 {
    int32_t tv_sec;
    int32_t tv_nsec;
};

static_assert(sizeof(GuestKevent32) == 20,
    "iOS 10 armv7 kevent ABI changed");
static_assert(sizeof(GuestTimespec32) == 8,
    "iOS 10 armv7 timespec ABI changed");

int guest_kevent(int kqueueDescriptor, u32 guestChanges,
        int changeCount, u32 guestEvents, int eventCount,
        u32 guestTimeout) {
    /* XNU treats negative counts as empty lists. Bound host-side staging. */
    changeCount = std::max(changeCount, 0);
    eventCount = std::max(eventCount, 0);
    constexpr int MaximumStagedKevents = 4096;
    if (changeCount > MaximumStagedKevents ||
            eventCount > MaximumStagedKevents) {
        return return_with_carry_direct(EINVAL, true);
    }

    std::vector<GuestKevent32> guestChangeStorage;
    std::vector<struct kevent> hostChangeStorage;
    std::vector<struct kevent> hostEventStorage;
    try {
        guestChangeStorage.resize(static_cast<size_t>(changeCount));
        hostChangeStorage.resize(static_cast<size_t>(changeCount));
        hostEventStorage.resize(static_cast<size_t>(eventCount));
    } catch (const std::exception &) {
        return return_with_carry_direct(ENOMEM, true);
    }

    if (changeCount != 0) {
        if (guestChanges == 0 ||
                !read_guest_memory_with_permissions(
                    guestChanges, guestChangeStorage.data(),
                    guestChangeStorage.size() * sizeof(GuestKevent32),
                    PROT_READ)) {
            return return_with_carry_direct(EFAULT, true);
        }
        for (int index = 0; index < changeCount; ++index) {
            const GuestKevent32 &guest =
                guestChangeStorage[static_cast<size_t>(index)];
            struct kevent &host =
                hostChangeStorage[static_cast<size_t>(index)];
            host.ident = static_cast<uintptr_t>(guest.ident);
            host.filter = guest.filter;
            host.flags = guest.flags;
            host.fflags = guest.fflags;
            host.data = static_cast<intptr_t>(guest.data);
            host.udata = reinterpret_cast<void *>(
                static_cast<uintptr_t>(guest.udata));
        }
    }

    struct timespec hostTimeout = {};
    const struct timespec *hostTimeoutPointer = nullptr;
    if (guestTimeout != 0) {
        GuestTimespec32 guestTimespec = {};
        if (!read_guest_memory_with_permissions(
                guestTimeout, &guestTimespec,
                sizeof(guestTimespec), PROT_READ)) {
            return return_with_carry_direct(EFAULT, true);
        }
        if (guestTimespec.tv_sec < 0 || guestTimespec.tv_nsec < 0 ||
                guestTimespec.tv_nsec >= 1000000000) {
            return return_with_carry_direct(EINVAL, true);
        }
        hostTimeout.tv_sec = guestTimespec.tv_sec;
        hostTimeout.tv_nsec = guestTimespec.tv_nsec;
        hostTimeoutPointer = &hostTimeout;
    }

    const bool potentiallyBlocking = eventCount > 0 &&
        (hostTimeoutPointer == nullptr || hostTimeout.tv_sec != 0 ||
         hostTimeout.tv_nsec != 0);
    const auto invokeHost = [&](const struct timespec *timeout,
                                bool includeChanges = true) {
        return syscallRetCarry(
            SYS_kevent, kqueueDescriptor,
            includeChanges && changeCount != 0
                ? hostChangeStorage.data() : nullptr,
            includeChanges ? changeCount : 0,
            eventCount != 0 ? hostEventStorage.data() : nullptr,
            eventCount, timeout, 0);
    };
    const auto invokeBlockingHost = [&](bool includeChanges = true) {
        const bool workqueueMayBlock =
            NativeGuestWorkqueueIsCurrent();
        if (workqueueMayBlock) {
            NativeGuestWorkqueueHostBlockEnter();
        }
        const int hostResult = debugger_aware_host_wait(
            [&] {
                return invokeHost(
                    hostTimeoutPointer, includeChanges);
            },
            return_with_carry_direct(EINTR, true));
        if (workqueueMayBlock) {
            NativeGuestWorkqueueHostBlockExit();
        }
        return hostResult;
    };

    int result;
    if (potentiallyBlocking && GuestThreadCanYieldBeforeBlocking()) {
        const struct timespec immediate = {};
        result = invokeHost(&immediate);
        if (!threadHandle.cpsr->hasCarry() && result == 0) {
            if (GuestThreadYieldBeforeBlocking()) {
                return return_with_carry_direct(EINTR, true);
            }
            /* The last runnable peer retired between the probe and yield. */
            result = invokeBlockingHost(false);
        }
    } else {
        if (potentiallyBlocking) {
            result = invokeBlockingHost();
        } else {
            result = invokeHost(hostTimeoutPointer);
        }
    }

    if (threadHandle.cpsr->hasCarry() || result <= 0) {
        return result;
    }
    if (result > eventCount || guestEvents == 0) {
        return return_with_carry_direct(EFAULT, true);
    }

    std::vector<GuestKevent32> guestEventStorage;
    try {
        guestEventStorage.resize(static_cast<size_t>(result));
    } catch (const std::exception &) {
        return return_with_carry_direct(ENOMEM, true);
    }
    for (int index = 0; index < result; ++index) {
        const struct kevent &host =
            hostEventStorage[static_cast<size_t>(index)];
        GuestKevent32 &guest =
            guestEventStorage[static_cast<size_t>(index)];
        guest.ident = static_cast<u32>(host.ident);
        guest.filter = host.filter;
        guest.flags = host.flags;
        guest.fflags = host.fflags;
        guest.data = static_cast<int32_t>(host.data);
        guest.udata = static_cast<u32>(
            reinterpret_cast<uintptr_t>(host.udata));
    }
    if (!write_guest_memory_with_permissions(
            guestEvents, guestEventStorage.data(),
            guestEventStorage.size() * sizeof(GuestKevent32),
            PROT_WRITE)) {
        return return_with_carry_direct(EFAULT, true);
    }
    return result;
}

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <time.h>
#include <assert.h>
#include <signal.h>
#include <libgen.h>

#include <dlfcn.h>
#include <sys/mman.h>
#include <mach-o/fat.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/reloc.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <sys/syscall.h>

#include <string.h>
#include "dynarmic.h"
#include "arm_dynarmic_cp15.h"

#define SEG_DATA_CONST  "__DATA_CONST"

// /var/mobile/Documents/TrollExperiments/CProjects/dynarmic

u32 Dynarmic_map_file(bool isDyld, u32 target, const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        printf("Dynarmic_map_file %s failed: %s\n", path, strerror(errno));
        exit(1);
    }
    
    struct stat file_info;
    fstat(fd, &file_info);
    size_t len = ALIGN_SIZE(file_info.st_size);
    uintptr_t map = (uintptr_t)mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    close(fd);
    
    // Map mach_header first
    //u32 addr = Dynarmic_direct_mmap(target, 0x1000, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, map, 0);
    
    guestMappings[guestMappingLen].name = strdup(basename((char *)path));
    
    // FIXME: may leak other unused slices
    if(*(uint32_t *)map == FAT_CIGAM) {
        struct fat_header *fatheader = (struct fat_header *)map;
        struct fat_arch *arch = (struct fat_arch *)&fatheader[1];
        map = 0;
        for(int i = 0; i < OSSwapInt32(fatheader->nfat_arch); i++) {
            int subtype = OSSwapInt32(arch->cpusubtype);
            int offset = OSSwapInt32(arch->offset);
            if(subtype == CPU_SUBTYPE_ARM_V7S) {
                map = (uintptr_t)fatheader + offset;
                // preferred subtype
                break;
            } else if(subtype == CPU_SUBTYPE_ARM_V7) {
                map = (uintptr_t)fatheader + offset;
                // look for armv7s
            } else if(subtype == CPU_SUBTYPE_ARM_V6 && !map) {
                map = (uintptr_t)fatheader + offset;
                // look for armv7s or armv7
            }
            arch = &arch[1];
        }
    }
    guestMappings[guestMappingLen].hostAddr = map;
    struct mach_header *header = (struct mach_header *)map;
    assert(header->magic == MH_MAGIC && header->cputype == CPU_TYPE_ARM);
    
    uintptr_t cur = (uintptr_t)header + sizeof(mach_header);
    load_command *lc;
    int firstIndex = 0;
    for (uint i = 0; i < header->ncmds; i++, cur += lc->cmdsize) {
        lc = (load_command *)cur;
        if (lc->cmd == LC_SEGMENT) {
            segment_command *seg = (segment_command *)lc;
            if(!strncmp(seg->segname, "__PAGEZERO", 10)) {
                firstIndex = 1;
                continue;
            }
            u32 filesize = ALIGN_DYN_SIZE(seg->filesize);
            if(seg->vmsize > seg->filesize) {
                // round up the page
                printf("vmsize 0x%x != filesize 0x%x\n", seg->vmsize, filesize);
                //abort();
            }
            if (i == firstIndex && seg->vmaddr >= 0x10000000) {
                target = 0;
            }
            printf("Mapping 0x%lx-0x%lx to 0x%x\n", map + seg->fileoff, map + seg->fileoff + seg->vmsize, target + seg->vmaddr);
            u32 mappedAddr = 0;
            if(filesize > 0) {
                mappedAddr = Dynarmic_direct_mmap(target + seg->vmaddr, filesize, PROT_READ | PROT_WRITE, MAP_FIXED | MAP_PRIVATE | MAP_ANONYMOUS, (void *)(map + seg->fileoff), 0);
                assert(mappedAddr != -1);
            }
            
            u32 vmMappedAddr = Dynarmic_mmap(target + seg->vmaddr + filesize, seg->vmsize - filesize, PROT_READ | PROT_WRITE, MAP_FIXED | MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            if(filesize == 0) {
                mappedAddr = vmMappedAddr;
            }
            
            if (i == firstIndex) {
                guestMappings[guestMappingLen].start = mappedAddr;
                guestMappings[guestMappingLen].end = mappedAddr + seg->vmsize;
            }
        } else if (lc->cmd == LC_UNIXTHREAD) {
            thread_command *tc = (thread_command *)lc;
            arm_thread_state_t *state = (arm_thread_state_t *)((uint64_t)tc + sizeof(uint32_t)*4);
            state->__pc += target;
            for (int i = 0; i < 13; i++) {
                threadHandle.jit->Regs()[i] = state->__r[i];
            }
            threadHandle.jit->Regs()[Reg::SP] = state->__sp;
            threadHandle.jit->Regs()[Reg::LR] = state->__lr;
            threadHandle.jit->Regs()[Reg::PC] = state->__pc;
            threadHandle.jit->SetCpsr(state->__cpsr);
        }
    }
    
    if(isDyld) {
        u32 dyldInfoSize;
        sharedHandle.dyld_info_section = (dyld_all_image_infos_32 *)((uintptr_t)getsectdatafromheader(header, SEG_DATA, "__all_image_info", &dyldInfoSize) + map);
        // register a fake Mach port which is used to notify us about loading/unloading Mach-O libraries
        sharedHandle.dyld_info_section->notifyMachPorts[0] = -1;
    }
    
    u32 addr = guestMappings[guestMappingLen].start;
    guestMappingLen++;
    return addr;
}

u32 prependString(u32& address, const char* fmt, ...) {
    char buffer[1000];
    va_list args;
    va_start(args, fmt);
    u32 len = vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    
    address -= len + 1;
    Dynarmic_mem_1write(address, len, buffer);
    return address;
}

void setupPathEnvs(char* argv0) {
    char path[PATH_MAX];
    
    // resolve default rootfs path to /path/to/LiveExec32.app/RootFS
    snprintf(path, sizeof(path), "%s/RootFS", dirname(argv0));
    setenv("ROOT_PATH", path, 0);
    const char *rootPath = getenv("ROOT_PATH");
    if (getuid() == 0) {
        chroot(rootPath);
        chdir("/");
    } else {
        chdir(rootPath);
        //sharedHandle.fs->addMountpoint("/rootfs", "/");
        sharedHandle.fs->addMountpoint("/", rootPath);
        sharedHandle.fs->addMountpoint("/dev", "/dev");
        // redirecting symlink doesn't work currently, so we add both
        sharedHandle.fs->addMountpoint("/private/var", "/private/var");
        sharedHandle.fs->addMountpoint("/var", "/var");
    }
    
    // resolve default dyld path to ${ROOT_PATH}/usr/lib/dyld
    const char *guestDyldPath = "/usr/lib/dyld";
    sharedHandle.fs->pathGuestToHost(guestDyldPath, path);
    setenv("DYLD_PATH", path, 0);
}

extern "C"
int main(int argc, char* argv[], char* envp[]) {
    if (argc == 1) {
        //printf("Usage: %s <path> argv...\n", argv[0]);
        // TODO: display help or setup wizard
        return 1;
    }
    
    // initialize page table, callback, Jit objects, paths
    Dynarmic_nativeInitialize();
    setupPathEnvs(argv[0]);
    
    // map the main executable first
    const char *execPath = argv[1];
    u32 execAddr = Dynarmic_map_file(false, 0x11000000, execPath);
    
    // map dyld
    const char *dyldPath = getenv("DYLD_PATH");
    printf("Loading dyld at DYLD_PATH %s\n", dyldPath);
    Dynarmic_map_file(true, 0x10000000, dyldPath);
    printf("entry point: 0x%x\n", threadHandle.jit->Regs()[15]);
    
    // commpage 0xffff4000+0x1000
    u32 commpage = Dynarmic_mmap(0xffff4000, 0x1000, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    sharedHandle.ucb->MemoryWrite16(commpage + 0x1E, 3); // version
    sharedHandle.ucb->MemoryWrite32(commpage + 0x20, 0x9000);
    sharedHandle.ucb->MemoryWrite8(commpage + 0x22, 1); // number of CPUs
    sharedHandle.ucb->MemoryWrite8(commpage + 0x24, DYN_PAGE_BITS); // 32-bit page shift
    sharedHandle.ucb->MemoryWrite16(commpage + 0x26, 128); // cache line size, 32? 64?
    //sharedHandle.ucb->MemoryWrite32(commpage + 0x28, 128); // sched count
    sharedHandle.ucb->MemoryWrite8(commpage + 0x34, 1); // active CPU
    sharedHandle.ucb->MemoryWrite8(commpage + 0x35, 1); // physical CPU
    sharedHandle.ucb->MemoryWrite8(commpage + 0x36, 1); // logical CPU
    sharedHandle.ucb->MemoryWrite8(commpage + 0x37, DYN_PAGE_BITS); // kernel page shift
    sharedHandle.ucb->MemoryWrite32(commpage + 0x38, 0x40000000u); // max memory size, 1GB
    // TODO: mach time stuff
    //sharedHandle.ucb->MemoryWrite64(commpage + 0x40, 0x4141414141414141); // FIXME
    //sharedHandle.ucb->MemoryWrite64(commpage + 0x80, 0x41414141); // FIXME
    sharedHandle.ucb->MemoryWrite64(commpage + 0x84, 1); // dev firmware
    
    // allocate stack guards and stack buffer for dyld
    u32 dyldStackGuardStart = Dynarmic_mmap(0x80000000, 0x1000, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    u32 dyldStack = Dynarmic_mmap(0x80000000, 0xff000, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    Dynarmic_mmap(0x80000000, 0x1000, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    
    u32 dyldStackPtr = dyldStack - 0x1000 + 0x100000;
    
    // write strings to the stack
    u32 guest_apple[] = {
        0, // separator
        // apple
        // comment out these if you want ASLR
        prependString(dyldStackPtr, "malloc_entropy=0xf0ef08e3de46c995,0xd5adb183cbc1fed0"),
        prependString(dyldStackPtr, "stack_guard=0xff39f7772c708a80"),
        
        prependString(dyldStackPtr, "pfz=0xffffffff"),
        prependString(dyldStackPtr, "main_stack=0x%x,0xff000,0x%x,0x100000", dyldStackGuardStart + 0x100000, dyldStackGuardStart),
        prependString(dyldStackPtr, "%s", execPath),
    };
    u32 guest_envp[] = {
        0, // separator
        // envp
        //prependString(dyldStackPtr, "OBJC_PRINT_LOAD_METHODS=1"),
        //prependString(dyldStackPtr, "OBJC_PRINT_RESOLVED_METHODS=1"),
        //prependString(dyldStackPtr, "OBJC_PRINT_CLASS_SETUP=1"),
        prependString(dyldStackPtr, "DYLD_SHARED_REGION=private"),
        prependString(dyldStackPtr, "DYLD_PRINT_OPTS=1"),
        prependString(dyldStackPtr, "DYLD_PRINT_ENV=1"),
        prependString(dyldStackPtr, "DYLD_PRINT_SEGMENTS=1"),
        prependString(dyldStackPtr, "DYLD_PRINT_INITIALIZERS=1"),
        //prependString(dyldStackPtr, "MallocTracing=YES"),
        //prependString(dyldStackPtr, "MallocStackLogging=YES"),
        //prependString(dyldStackPtr, "MallocScribble=YES"),
        //prependString(dyldStackPtr, "MallocLogFile=/tmp/a.malloc.log")
    };
    u32 guest_argv[1000] = {0};
    guest_argv[0] = argc - 1;
    // CAUTION: write backwards!!
    for (int i = argc-1; i >= 1; i--) {
        guest_argv[i] = prependString(dyldStackPtr, "%s", argv[i]);
    }
    
    // align
    dyldStackPtr &= ~(sizeof(u32)-1);
    dyldStackPtr -= 0x1000;
    
    // calculate for alignment...
    int toBeWritten = sizeof(guest_apple) + sizeof(guest_envp) + sizeof(guest_argv) + sizeof(u32) * 2;
    dyldStackPtr -= (dyldStackPtr - toBeWritten) & 0xF;
    
    // write apple
    for (int i = 0; i < sizeof(guest_apple)/sizeof(u32); i++) {
        sharedHandle.ucb->MemoryWrite32(dyldStackPtr -= sizeof(u32), guest_apple[i]);
    }
    
    // write envp
    for (int i = 0; i < sizeof(guest_envp)/sizeof(u32); i++) {
        sharedHandle.ucb->MemoryWrite32(dyldStackPtr -= sizeof(u32), guest_envp[i]);
    }
    
    // write argv and argc
    for (int i = argc; i >= 0; i--) {
        sharedHandle.ucb->MemoryWrite32(dyldStackPtr -= sizeof(u32), guest_argv[i]);
    }
    
    // write main executable base
    sharedHandle.ucb->MemoryWrite32(dyldStackPtr -= sizeof(u32), execAddr);
    
    printf("LC32: stack ptr now 0x%x\n", dyldStackPtr);
    
    // Go!
    Dynarmic_reg_1write(13, dyldStackPtr);
    Dynarmic_emu_1start(threadHandle.jit->Regs()[15]);
}


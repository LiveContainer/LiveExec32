#import "bridge.h"
#include "LC32ObjCBridgeABI.h"

#import <dispatch/dispatch.h>
#import <mach/vm_map.h>

#include <atomic>
#include <array>
#include <memory>
#include <mutex>
#include <new>
#include <pthread.h>
#include <stdarg.h>
#include <unordered_map>
#include <vector>

// These Objective-C runtime entry points let the host manipulate ownership
// explicitly. bridge.mm is normally built with manual reference counting,
// while keeping the weak-slot declarations valid if ARC is enabled later.
extern "C" id objc_autorelease(id object);
extern "C" void objc_release(id object);
extern "C" id objc_retain(id object);
extern "C" id _objc_rootRetain(id object);
extern "C" void _objc_rootRelease(id object);
extern "C" bool _objc_rootTryRetain(id object);
extern "C" bool _objc_rootIsDeallocating(id object);
extern "C" uintptr_t _objc_rootRetainCount(id object);
#if __has_feature(objc_arc)
typedef __weak id LC32NativeWeakSlot;
#else
typedef id LC32NativeWeakSlot;
#endif
extern "C" void objc_destroyWeak(LC32NativeWeakSlot *location);
extern "C" id objc_initWeakOrNil(LC32NativeWeakSlot *location, id object);
extern "C" id objc_loadWeakRetained(LC32NativeWeakSlot *location);
extern "C" id objc_storeWeakOrNil(LC32NativeWeakSlot *location, id object);

class LC32GuestHostCallQuiescence {
public:
    LC32GuestHostCallQuiescence()
        : active(Dynarmic_guest_host_call_quiescence_begin()) {}

    ~LC32GuestHostCallQuiescence() {
        finish();
    }

    void finish() {
        if (!active) {
            return;
        }
        active = false;
        Dynarmic_guest_host_call_quiescence_end();
    }

    LC32GuestHostCallQuiescence(
        const LC32GuestHostCallQuiescence &) = delete;
    LC32GuestHostCallQuiescence &operator=(
        const LC32GuestHostCallQuiescence &) = delete;

private:
    bool active;
};

#if __has_feature(objc_arc)
static void LC32ObjCAutoreleaseWithoutARC(id object) {
    (void)objc_autorelease(object);
}
#endif

static void LC32ObjCRetainWithoutARC(id object) {
    (void)objc_retain(object);
}

@interface LC32ObjCMethodResolver : NSObject
+ (void)registerClass:(Class)cls;
@end

static void LC32PinGuestObjectToHost(id hostObject, u32 guestObject,
                                     bool retainGuestObject);
static void LC32DrainDeferredGuestPinReleases();
static u32 LC32GuestObjectForBorrowedHostResult(id hostObject);
static void LC32InstallGuestMirrorReferenceCounting(Class cls);
static void LC32GuestMirrorRelease(id self, SEL selector);
static void LC32RetireGuestMirrorWithTransferredReference(id hostObject);
static void LC32ClearGuestSelfIfEqualWhileSynchronized(
    id hostObject, u32 expectedGuestObject);
static void LC32ClearGuestSelfIfEqual(id hostObject,
                                      u32 expectedGuestObject);

static const void *LC32GuestLifetimePinKey =
    &LC32GuestLifetimePinKey;
static const void *kGuestClass = &kGuestClass;
static const void *kGuestSelf = &kGuestSelf;

/*
 * NSOperation ownership diagnostics are intentionally runtime-gated because
 * retain/release traffic is both frequent and timing-sensitive.  Keep a raw
 * address registry so a final setCompletionBlock: sent through a stale guest
 * proxy can be diagnosed without messaging (and crashing on) the freed native
 * receiver.  Enable with LC32_OPERATION_TRACE=1.
 */
struct LC32OperationTraceRecord {
    u32 guestObject;
    bool alive;
    std::array<char, 96> className;
};

static pthread_once_t LC32OperationTraceOnce = PTHREAD_ONCE_INIT;
static bool LC32OperationTraceIsEnabled;
static std::atomic<u64> LC32OperationTraceSequence{0};

static pthread_once_t LC32NetworkTraceOnce = PTHREAD_ONCE_INIT;
static bool LC32NetworkTraceIsEnabled;
static pthread_once_t LC32GuestCallbackTraceOnce = PTHREAD_ONCE_INIT;
static bool LC32GuestCallbackTraceIsEnabled;
static pthread_once_t LC32BlockArgumentTraceOnce = PTHREAD_ONCE_INIT;
static bool LC32BlockArgumentTraceIsEnabled;

static void LC32InitializeNetworkTrace() {
    const char *value = getenv("LC32_NETWORK_TRACE");
    LC32NetworkTraceIsEnabled =
        value && value[0] && strcmp(value, "0") != 0;
}

static bool LC32NetworkTraceEnabled() {
    pthread_once(&LC32NetworkTraceOnce, LC32InitializeNetworkTrace);
    return LC32NetworkTraceIsEnabled;
}

static void LC32InitializeGuestCallbackTrace() {
    const char *value = getenv("LC32_CALLBACK_TRACE");
    LC32GuestCallbackTraceIsEnabled =
        value && value[0] && strcmp(value, "0") != 0;
}

static bool LC32GuestCallbackTraceEnabled() {
    pthread_once(&LC32GuestCallbackTraceOnce,
                 LC32InitializeGuestCallbackTrace);
    return LC32GuestCallbackTraceIsEnabled;
}

static void LC32InitializeBlockArgumentTrace() {
    const char *value = getenv("LC32_BLOCK_TRACE");
    LC32BlockArgumentTraceIsEnabled =
        value && value[0] && strcmp(value, "0") != 0;
}

static bool LC32BlockArgumentTraceEnabled() {
    pthread_once(&LC32BlockArgumentTraceOnce,
                 LC32InitializeBlockArgumentTrace);
    return LC32BlockArgumentTraceIsEnabled;
}

static void LC32TraceGuestMethodCallback(id receiver, SEL selector) {
    if(!LC32GuestCallbackTraceEnabled()) return;
    NSOperationQueue *operationQueue = NSOperationQueue.currentQueue;
    const char *queueLabel = dispatch_queue_get_label(
        DISPATCH_CURRENT_QUEUE_LABEL);
    fprintf(stderr,
        "LC32 callback: %c[%s %s] registered=%d "
        "hostThread=%p main=%d dispatch=%s operationQueue=%p "
        "operationMain=%d\n",
        object_isClass(receiver) ? '+' : '-',
        receiver ? class_getName(object_getClass(receiver)) : "(null)",
        selector ? sel_getName(selector) : "(null)",
        Dynarmic_guest_thread_is_registered(),
        (void *)pthread_self(), pthread_main_np(), queueLabel ?: "",
        operationQueue, operationQueue != nil &&
            operationQueue == NSOperationQueue.mainQueue);
    fflush(stderr);
}

static void LC32TraceNativeNetworkObject(const char *direction,
                                          SEL selector,
                                          unsigned int argumentIndex,
                                          id object) {
    if(!LC32NetworkTraceEnabled() || !object) return;

    @autoreleasepool {
        @try {
            if([object isKindOfClass:NSURLRequest.class]) {
                NSURLRequest *request = (NSURLRequest *)object;
                fprintf(stderr,
                    "LC32 network %s %s arg=%u request=%s %s headers=%s\n",
                    direction, sel_getName(selector), argumentIndex,
                    request.HTTPMethod.UTF8String ?: "?",
                    request.URL.absoluteString.UTF8String ?: "?",
                    request.allHTTPHeaderFields.description.UTF8String ?: "{}");
            } else if([object isKindOfClass:NSHTTPURLResponse.class]) {
                NSHTTPURLResponse *response = (NSHTTPURLResponse *)object;
                fprintf(stderr,
                    "LC32 network %s %s arg=%u response=%ld %s headers=%s\n",
                    direction, sel_getName(selector), argumentIndex,
                    (long)response.statusCode,
                    response.URL.absoluteString.UTF8String ?: "?",
                    response.allHeaderFields.description.UTF8String ?: "{}");
            } else if([object isKindOfClass:NSError.class]) {
                NSError *error = (NSError *)object;
                fprintf(stderr,
                    "LC32 network %s %s arg=%u error=%s\n",
                    direction, sel_getName(selector), argumentIndex,
                    error.description.UTF8String ?: "?");
            }
        } @catch(NSException *exception) {
            fprintf(stderr,
                "LC32 network trace failed for %s arg=%u: %s\n",
                sel_getName(selector), argumentIndex,
                exception.description.UTF8String ?: "?");
        }
    }
}

static void LC32InitializeOperationTrace() {
    const char *value = getenv("LC32_OPERATION_TRACE");
    LC32OperationTraceIsEnabled =
        value && value[0] && strcmp(value, "0") != 0;
}

static bool LC32OperationTraceEnabled() {
    pthread_once(&LC32OperationTraceOnce, LC32InitializeOperationTrace);
    return LC32OperationTraceIsEnabled;
}

static std::mutex& LC32OperationTraceMutex() {
    static std::mutex *mutex = new std::mutex;
    return *mutex;
}

static std::unordered_map<u64, LC32OperationTraceRecord>&
LC32OperationTraceRecords() {
    static auto *records =
        new std::unordered_map<u64, LC32OperationTraceRecord>;
    return *records;
}

static void LC32OperationTraceGuestContext(u32 *pc, u32 *lr) {
    *pc = 0;
    *lr = 0;
    if(!threadHandle.jit) return;
    const auto &registers = threadHandle.jit->Regs();
    *pc = registers[Reg::PC];
    *lr = registers[Reg::LR];
}

static bool LC32HostObjectIsOperation(id object) {
    if(!object) return false;
    Class operationClass = objc_getClass("NSOperation");
    return operationClass && [object isKindOfClass:operationClass];
}

static void LC32OperationTraceRemember(id object, u32 guestObject,
                                       bool alive) {
    if(!LC32OperationTraceEnabled() || !object) return;

    const u64 address = (u64)object;
    LC32OperationTraceRecord record = {};
    record.guestObject = guestObject;
    record.alive = alive;
    const char *name = class_getName(object_getClass(object));
    if(name) {
        snprintf(record.className.data(), record.className.size(), "%s", name);
    }
    std::lock_guard<std::mutex> lock(LC32OperationTraceMutex());
    LC32OperationTraceRecords()[address] = record;
}

static bool LC32OperationTraceLookup(
        u64 address, LC32OperationTraceRecord *record) {
    if(!LC32OperationTraceEnabled()) return false;
    std::lock_guard<std::mutex> lock(LC32OperationTraceMutex());
    auto iterator = LC32OperationTraceRecords().find(address);
    if(iterator == LC32OperationTraceRecords().end()) return false;
    *record = iterator->second;
    return true;
}

static void LC32OperationTracePrint(const char *event, u64 hostObject,
                                    const LC32OperationTraceRecord &record,
                                    long nativeRetainCount,
                                    u64 detail = 0) {
    u32 pc, lr;
    LC32OperationTraceGuestContext(&pc, &lr);
    const u64 sequence = LC32OperationTraceSequence.fetch_add(
        1, std::memory_order_relaxed) + 1;
    fprintf(stderr,
        "LC32 operation trace #%llu %s host=0x%llx guest=0x%x "
        "class=%s alive=%d nativeRC=%ld detail=0x%llx pc=0x%x "
        "lr=0x%x thread=%p\n",
        sequence, event, hostObject, record.guestObject,
        record.className[0] ? record.className.data() : "?",
        record.alive, nativeRetainCount, detail, pc, lr,
        (void *)pthread_self());
}

static void LC32OperationTraceLiveObject(const char *event, id object,
                                         u32 guestObject, u64 detail = 0) {
    if(!LC32OperationTraceEnabled() ||
       !LC32HostObjectIsOperation(object)) return;

    LC32OperationTraceRemember(object, guestObject, true);
    LC32OperationTraceRecord record = {};
    if(!LC32OperationTraceLookup((u64)object, &record)) return;
    LC32OperationTracePrint(event, (u64)object, record,
        (long)CFGetRetainCount((CFTypeRef)object), detail);
}

static void LC32OperationTraceRawSelector(id receiver, SEL selector,
                                          u64 firstArgument) {
    if(!LC32OperationTraceEnabled()) return;
    const char *selectorName = sel_getName(selector);
    const bool completion = selectorName &&
        strcmp(selectorName, "setCompletionBlock:") == 0;
    const bool ownership = selectorName &&
        (!strcmp(selectorName, "retain") ||
         !strcmp(selectorName, "release") ||
         !strcmp(selectorName, "retainCount"));
    if(!completion && !ownership) return;

    LC32OperationTraceRecord record = {};
    if(!LC32OperationTraceLookup((u64)receiver, &record)) return;
    const long nativeRetainCount = record.alive
        ? (long)CFGetRetainCount((CFTypeRef)receiver)
        : -1;
    LC32OperationTracePrint(selectorName, (u64)receiver, record,
                            nativeRetainCount,
                            completion ? firstArgument : 0);
}

static void LC32OperationTraceDeallocated(u64 hostObject, u32 guestObject,
                                          const char *className) {
    if(!LC32OperationTraceEnabled()) return;

    LC32OperationTraceRecord record = {};
    record.guestObject = guestObject;
    record.alive = false;
    if(className) {
        snprintf(record.className.data(), record.className.size(), "%s",
                 className);
    }
    {
        std::lock_guard<std::mutex> lock(LC32OperationTraceMutex());
        LC32OperationTraceRecords()[hostObject] = record;
    }
    LC32OperationTracePrint("native-dealloc", hostObject, record, 0);
}

/*
 * Guest objc_loadWeakRetained holds the ARM32 runtime's weak side-table lock
 * while it asks an object with custom RR to retain itself.  Looking up the
 * native peer through a guest associated object from that callback can retain
 * the associated value and recursively acquire the same striped lock.
 *
 * Keep the authoritative host identity in native weak storage instead.  A
 * generation makes retirement conditional so a delayed pin belonging to an
 * old object can never erase a new mapping which reuses the same ARM address.
 */
enum class LC32HostWeakMappingState : uint8_t {
    Live,
    Retiring,
    Superseded,
};

enum class LC32HostMappingLifetime : uint8_t {
    Provisional,
    Pinned,
    Permanent,
};

struct LC32HostWeakMappingEntry {
    u32 guestObject;
    u64 generation;
    u64 expectedHostAddress;
    LC32HostWeakMappingState state;
    LC32HostMappingLifetime lifetime;
    u64 retiringOwnerThreadToken;
    LC32NativeWeakSlot weakHostObject;

    LC32HostWeakMappingEntry(id hostObject, u32 guest, u64 serial,
                             LC32HostMappingLifetime mappingLifetime)
        : guestObject(guest), generation(serial),
          expectedHostAddress((u64)hostObject),
          state(LC32HostWeakMappingState::Live),
          lifetime(mappingLifetime), retiringOwnerThreadToken(0),
          weakHostObject(nil) {
        /* Weak-host-incompatible objects become a live entry containing nil;
         * a guest weak load then fails safely instead of raising here. */
#if __has_feature(objc_arc)
        (void)objc_storeWeakOrNil(&weakHostObject, hostObject);
#else
        (void)objc_initWeakOrNil(&weakHostObject, hostObject);
#endif
    }

    ~LC32HostWeakMappingEntry() {
#if !__has_feature(objc_arc)
        objc_destroyWeak(&weakHostObject);
#endif
    }
};

struct LC32HostWeakRegistry {
    std::mutex mutex;
    std::unordered_map<u32,
        std::shared_ptr<LC32HostWeakMappingEntry>> entries;
    std::atomic<u64> nextGeneration{1};
    dispatch_queue_t deferredReleaseQueue;

    LC32HostWeakRegistry()
        : deferredReleaseQueue(dispatch_queue_create(
              "org.liveexec32.host-weak-release", DISPATCH_QUEUE_SERIAL)) {}
};

static LC32HostWeakRegistry& LC32HostWeakMappings() {
    /* Host weak slots and their synchronization intentionally survive process
     * teardown; Objective-C framework destruction order is not deterministic. */
    static LC32HostWeakRegistry *registry = new LC32HostWeakRegistry;
    return *registry;
}

static void LC32DeferHostWeakEntryRelease(
        std::shared_ptr<LC32HostWeakMappingEntry> entry) {
    if(!entry) return;
    /* The SVC path runs inside guest objc_loadWeakRetained while its weak
     * SideTable stripe is locked.  Keep the final native weak-slot teardown
     * off that thread even if registry retirement races this lookup. */
    dispatch_async(LC32HostWeakMappings().deferredReleaseQueue, ^{
        (void)entry->generation;
    });
}

static u64 LC32NextHostWeakGeneration() {
    LC32HostWeakRegistry &registry = LC32HostWeakMappings();
    u64 generation = registry.nextGeneration.fetch_add(
        1, std::memory_order_relaxed);
    if(generation) return generation;
    /* A wrap is practically unreachable, but zero is reserved for "none". */
    do {
        generation = registry.nextGeneration.fetch_add(
            1, std::memory_order_relaxed);
    } while(!generation);
    return generation;
}

static u64 LC32CurrentHostMappingThreadToken() {
    static std::atomic<u64> nextToken{1};
    static thread_local const u64 token = [] {
        u64 value = nextToken.fetch_add(1, std::memory_order_relaxed);
        if(value) return value;
        do {
            value = nextToken.fetch_add(1, std::memory_order_relaxed);
        } while(!value);
        return value;
    }();
    return token;
}

static u64 LC32PublishHostMapping(
        id hostObject, u32 guestObject,
        LC32HostMappingLifetime requestedLifetime) {
    if(!hostObject || !guestObject) return 0;

    const u64 generation = LC32NextHostWeakGeneration();
    std::shared_ptr<LC32HostWeakMappingEntry> entry;
    try {
        /* Initializing native weak storage may acquire libobjc's SideTable.
         * It must remain outside the registry mutex. */
        entry = std::make_shared<LC32HostWeakMappingEntry>(
            hostObject, guestObject, generation, requestedLifetime);
    } catch(const std::bad_alloc &) {
        return 0;
    }

    std::shared_ptr<LC32HostWeakMappingEntry> replaced;
    std::shared_ptr<LC32HostWeakMappingEntry> unused;
    u64 publishedGeneration = generation;
    bool rejectedStableReplacement = false;
    u64 rejectedHostAddress = 0;
    LC32HostMappingLifetime rejectedLifetime =
        LC32HostMappingLifetime::Provisional;
    {
        LC32HostWeakRegistry &registry = LC32HostWeakMappings();
        std::lock_guard<std::mutex> lock(registry.mutex);
        auto iterator = registry.entries.find(guestObject);
        if(iterator == registry.entries.end()) {
            try {
                registry.entries.emplace(guestObject, entry);
            } catch(const std::bad_alloc &) {
                publishedGeneration = 0;
                unused = std::move(entry);
            }
        } else if(iterator->second->state ==
                      LC32HostWeakMappingState::Live &&
                  iterator->second->expectedHostAddress ==
                      (u64)hostObject) {
            /* A host lifetime pin promotes the provisional publication which
             * preceded it.  Reuse the exact generation stored by that pin so
             * its delayed retirement remains conditional.  Later guest-side
             * publications of the same pair must never demote it. */
            if(requestedLifetime == LC32HostMappingLifetime::Pinned &&
                    iterator->second->lifetime ==
                        LC32HostMappingLifetime::Provisional) {
                iterator->second->lifetime =
                    LC32HostMappingLifetime::Pinned;
            } else if(requestedLifetime ==
                          LC32HostMappingLifetime::Permanent &&
                      iterator->second->lifetime ==
                          LC32HostMappingLifetime::Provisional) {
                iterator->second->lifetime =
                    LC32HostMappingLifetime::Permanent;
            }
            publishedGeneration = iterator->second->generation;
            unused = std::move(entry);
        } else if(iterator->second->state ==
                      LC32HostWeakMappingState::Live &&
                  iterator->second->lifetime !=
                      LC32HostMappingLifetime::Provisional) {
            /* Pinned and permanent pairs are immutable.  A Retiring entry is
             * deliberately excluded: a newly allocated pair may reuse both
             * raw addresses and still requires a fresh generation. */
            rejectedStableReplacement = true;
            rejectedHostAddress =
                iterator->second->expectedHostAddress;
            rejectedLifetime = iterator->second->lifetime;
            publishedGeneration = 0;
            unused = std::move(entry);
        } else {
            iterator->second->state =
                LC32HostWeakMappingState::Superseded;
            replaced = std::move(iterator->second);
            iterator->second = entry;
        }
    }

    if(rejectedStableReplacement) {
        fprintf(stderr,
            "LC32: refusing to replace %s host mapping for guest 0x%x "
            "(old host 0x%llx, new host 0x%llx)\n",
            rejectedLifetime == LC32HostMappingLifetime::Pinned
                ? "pinned" : "permanent",
            guestObject,
            (unsigned long long)rejectedHostAddress,
            (unsigned long long)(u64)hostObject);
    }
    LC32DeferHostWeakEntryRelease(std::move(unused));
    LC32DeferHostWeakEntryRelease(std::move(replaced));
    return publishedGeneration;
}

static u64 LC32RegisterHostWeakMapping(id hostObject, u32 guestObject) {
    return LC32PublishHostMapping(
        hostObject, guestObject, LC32HostMappingLifetime::Pinned);
}

extern "C" u64 LC32LookupHostMapping(u32 guestObject) {
    if(!guestObject) return 0;

    const u64 currentThreadToken = LC32CurrentHostMappingThreadToken();
    LC32HostWeakRegistry &registry = LC32HostWeakMappings();
    std::lock_guard<std::mutex> lock(registry.mutex);
    auto iterator = registry.entries.find(guestObject);
    if(iterator == registry.entries.end()) {
        return 0;
    }
    if(iterator->second->state == LC32HostWeakMappingState::Live) {
        return iterator->second->expectedHostAddress;
    }
    /* Retirement keeps the native object guarded until guest -dealloc has
     * returned, but the ARM address may be recycled on another native guest
     * thread before final cleanup. Only the thread executing the old
     * teardown may continue to resolve that Retiring generation. */
    if(iterator->second->state != LC32HostWeakMappingState::Retiring ||
            iterator->second->retiringOwnerThreadToken !=
                currentThreadToken) {
        return 0;
    }
    return iterator->second->expectedHostAddress;
}

static u32 LC32ClearHostMappingIfEqual(
        u32 guestObject, u64 expectedHostAddress) {
    if(!guestObject || !expectedHostAddress) return 0;

    std::shared_ptr<LC32HostWeakMappingEntry> removed;
    {
        LC32HostWeakRegistry &registry = LC32HostWeakMappings();
        std::lock_guard<std::mutex> lock(registry.mutex);
        auto iterator = registry.entries.find(guestObject);
        if(iterator == registry.entries.end()) {
            return 1;
        }
        if(iterator->second->expectedHostAddress != expectedHostAddress) {
            /* The old guest object may already have completed -dealloc and
             * its ARM address may now name a new pair.  A conditional clear
             * which loses that ABA race has still succeeded: preserving the
             * newer entry is exactly its contract. */
            return 1;
        }
        iterator->second->state = LC32HostWeakMappingState::Superseded;
        removed = std::move(iterator->second);
        registry.entries.erase(iterator);
    }
    LC32DeferHostWeakEntryRelease(std::move(removed));
    return 1;
}

struct LC32PendingGuestMappingTeardown {
    u32 guestObject;
    u64 generation;
    u64 expectedHostAddress;
    std::shared_ptr<LC32HostWeakMappingEntry> entry;
};

static std::mutex& LC32PendingGuestMappingTeardownMutex() {
    static std::mutex *mutex = new std::mutex;
    return *mutex;
}

static std::unordered_map<u32, LC32PendingGuestMappingTeardown>&
LC32PendingGuestMappingTeardowns() {
    static auto *teardowns =
        new std::unordered_map<u32, LC32PendingGuestMappingTeardown>;
    return *teardowns;
}

static u32 LC32CreatePendingGuestMappingTeardown(
        const std::shared_ptr<LC32HostWeakMappingEntry>& entry) {
    if(!entry) return 0;
    static u32 nextToken = 1;
    std::lock_guard<std::mutex> lock(
        LC32PendingGuestMappingTeardownMutex());
    auto &teardowns = LC32PendingGuestMappingTeardowns();
    for(;;) {
        const u32 token = nextToken++;
        if(!nextToken) nextToken = 1;
        if(!token || teardowns.count(token)) continue;
        try {
            teardowns.emplace(token, LC32PendingGuestMappingTeardown{
                entry->guestObject, entry->generation,
                entry->expectedHostAddress, entry,
            });
        } catch(const std::bad_alloc &) {
            return 0;
        }
        return token;
    }
}

static bool LC32TakePendingGuestMappingTeardown(
        u32 token, u32 guestObject,
        LC32PendingGuestMappingTeardown *result) {
    if(!token || !guestObject || !result) return false;
    std::lock_guard<std::mutex> lock(
        LC32PendingGuestMappingTeardownMutex());
    auto &teardowns = LC32PendingGuestMappingTeardowns();
    auto iterator = teardowns.find(token);
    if(iterator == teardowns.end() ||
            iterator->second.guestObject != guestObject) {
        return false;
    }
    *result = std::move(iterator->second);
    teardowns.erase(iterator);
    return true;
}

static u32 LC32BeginGuestMappingTeardown(
        u32 guestObject, u64 expectedHostAddress) {
    if(!guestObject || !expectedHostAddress) return 0;

    id hostObject = (id)(uintptr_t)expectedHostAddress;
    u32 token = 0;
    /* Publish retirement under the same host->registry lock order used by
     * host-to-guest conversion.  Keep both mapping directions intact through
     * arbitrary guest -dealloc code; Finish clears them transactionally. */
    @synchronized(hostObject) {
        {
            LC32HostWeakRegistry &registry = LC32HostWeakMappings();
            std::lock_guard<std::mutex> lock(registry.mutex);
            auto iterator = registry.entries.find(guestObject);
            if(iterator == registry.entries.end() ||
                    iterator->second->state !=
                        LC32HostWeakMappingState::Live ||
                    iterator->second->lifetime !=
                        LC32HostMappingLifetime::Provisional ||
                    iterator->second->expectedHostAddress !=
                        expectedHostAddress) {
                return 0;
            }
            token = LC32CreatePendingGuestMappingTeardown(
                iterator->second);
            if(!token) return 0;
            iterator->second->state =
                LC32HostWeakMappingState::Retiring;
            iterator->second->retiringOwnerThreadToken =
                LC32CurrentHostMappingThreadToken();
        }
    }
    return token;
}

static u32 LC32FinishGuestMappingTeardown(
        u32 guestObject, u32 token) {
    LC32PendingGuestMappingTeardown pending = {};
    if(!LC32TakePendingGuestMappingTeardown(
            token, guestObject, &pending)) return 0;

    id hostObject = (id)(uintptr_t)pending.expectedHostAddress;
    std::shared_ptr<LC32HostWeakMappingEntry> removedCurrent;
    bool clearOldReverseMapping = false;
    bool invalidCurrentGeneration = false;
    @synchronized(hostObject) {
        {
            LC32HostWeakRegistry &registry = LC32HostWeakMappings();
            std::lock_guard<std::mutex> lock(registry.mutex);
            auto iterator = registry.entries.find(guestObject);
            if(iterator == registry.entries.end()) {
                clearOldReverseMapping = true;
            } else if(iterator->second->generation == pending.generation) {
                if(iterator->second->state !=
                        LC32HostWeakMappingState::Retiring ||
                        iterator->second->expectedHostAddress !=
                            pending.expectedHostAddress) {
                    invalidCurrentGeneration = true;
                } else {
                    iterator->second->state =
                        LC32HostWeakMappingState::Superseded;
                    removedCurrent = std::move(iterator->second);
                    registry.entries.erase(iterator);
                    clearOldReverseMapping = true;
                }
            } else {
                /* Same-host reuse owns the same numeric reverse pointer and
                 * must preserve it. A different host leaves the old reverse
                 * mapping stale and safe to clear under this monitor. */
                clearOldReverseMapping =
                    iterator->second->expectedHostAddress !=
                        pending.expectedHostAddress;
            }
            /* Keep the forward-map decision and reverse-map clear atomic
             * with respect to publishers. They use this same host->registry
             * lock order, so a newer same-host generation cannot appear in
             * the gap and have its reverse mapping cleared by old teardown. */
            if(!invalidCurrentGeneration && clearOldReverseMapping) {
                LC32ClearGuestSelfIfEqualWhileSynchronized(
                    hostObject, guestObject);
            }
        }
    }
    if(invalidCurrentGeneration) {
        LC32DeferHostWeakEntryRelease(std::move(pending.entry));
        return 0;
    }
    LC32DeferHostWeakEntryRelease(std::move(removedCurrent));
    LC32DeferHostWeakEntryRelease(std::move(pending.entry));
    return 1;
}

extern "C" u32 LC32UpdateHostMapping(
        u32 guestObject, LC32HostMappingOperation operation,
        u64 hostObject) {
    static_assert(sizeof(LC32HostMappingOperation) == sizeof(u32));
    switch(operation) {
        case LC32HostMappingPublishProvisional:
            return LC32PublishHostMapping(
                (id)(uintptr_t)hostObject, guestObject,
                LC32HostMappingLifetime::Provisional) != 0;
        case LC32HostMappingPublishPermanent:
            return LC32PublishHostMapping(
                (id)(uintptr_t)hostObject, guestObject,
                LC32HostMappingLifetime::Permanent) != 0;
        case LC32HostMappingClearIfEqual:
            return LC32ClearHostMappingIfEqual(
                guestObject, hostObject);
        case LC32HostMappingBeginGuestTeardown:
            return LC32BeginGuestMappingTeardown(
                guestObject, hostObject);
        case LC32HostMappingFinishGuestTeardown:
            return LC32FinishGuestMappingTeardown(
                guestObject, static_cast<u32>(hostObject));
    }
    return 0;
}

static void LC32MarkHostWeakMappingRetiring(
        u32 guestObject, u64 generation) {
    if(!guestObject || !generation) return;
    LC32HostWeakRegistry &registry = LC32HostWeakMappings();
    std::lock_guard<std::mutex> lock(registry.mutex);
    auto iterator = registry.entries.find(guestObject);
    if(iterator != registry.entries.end() &&
       iterator->second->generation == generation) {
        iterator->second->state = LC32HostWeakMappingState::Retiring;
        iterator->second->retiringOwnerThreadToken =
            LC32CurrentHostMappingThreadToken();
    }
}

static void LC32RefreshHostWeakMappingRetiringOwner(
        u32 guestObject, u64 generation) {
    if(!guestObject || !generation) return;
    LC32HostWeakRegistry &registry = LC32HostWeakMappings();
    std::lock_guard<std::mutex> lock(registry.mutex);
    auto iterator = registry.entries.find(guestObject);
    if(iterator != registry.entries.end() &&
       iterator->second->generation == generation &&
       iterator->second->state == LC32HostWeakMappingState::Retiring) {
        iterator->second->retiringOwnerThreadToken =
            LC32CurrentHostMappingThreadToken();
    }
}

static void LC32RestoreHostWeakMappingLive(
        u32 guestObject, u64 generation) {
    if(!guestObject || !generation) return;
    LC32HostWeakRegistry &registry = LC32HostWeakMappings();
    std::lock_guard<std::mutex> lock(registry.mutex);
    auto iterator = registry.entries.find(guestObject);
    if(iterator != registry.entries.end() &&
       iterator->second->generation == generation &&
       iterator->second->state == LC32HostWeakMappingState::Retiring) {
        iterator->second->state = LC32HostWeakMappingState::Live;
        iterator->second->retiringOwnerThreadToken = 0;
    }
}

static void LC32FinalizeHostWeakMappingRetirement(
        u32 guestObject, u64 generation) {
    if(!guestObject || !generation) return;
    std::shared_ptr<LC32HostWeakMappingEntry> retired;
    {
        LC32HostWeakRegistry &registry = LC32HostWeakMappings();
        std::lock_guard<std::mutex> lock(registry.mutex);
        auto iterator = registry.entries.find(guestObject);
        if(iterator == registry.entries.end() ||
           iterator->second->generation != generation) {
            return;
        }
        retired = std::move(iterator->second);
        registry.entries.erase(iterator);
    }
    /* Destroying the native weak slot may acquire its SideTable stripe.  The
     * shared_ptr deliberately leaves the registry lock first and is then
     * destroyed on the host release queue. */
    LC32DeferHostWeakEntryRelease(std::move(retired));
}

static void LC32DeferOwnedHostRelease(void *ownedHostObject) {
    if(!ownedHostObject) return;
    dispatch_async(LC32HostWeakMappings().deferredReleaseQueue, ^{
        objc_release((__bridge id)ownedHostObject);
    });
}

struct LC32PendingHostWeakRetain {
    void *ownedHostObject;
    u32 guestObject;
    u64 weakRegistryGeneration;
};

static std::mutex& LC32PendingHostWeakRetainMutex() {
    static std::mutex *mutex = new std::mutex;
    return *mutex;
}

static std::unordered_map<u32, LC32PendingHostWeakRetain>&
LC32PendingHostWeakRetains() {
    static auto *retains =
        new std::unordered_map<u32, LC32PendingHostWeakRetain>;
    return *retains;
}

static u32 LC32CreatePendingHostWeakRetain(
        void *ownedHostObject, u32 guestObject, u64 generation) {
    if(!ownedHostObject || !guestObject || !generation) return 0;

    static u32 nextToken = LC32HostWeakRetainFirstToken;
    std::lock_guard<std::mutex> lock(LC32PendingHostWeakRetainMutex());
    auto &retains = LC32PendingHostWeakRetains();
    for(;;) {
        u32 token = nextToken++;
        if(nextToken < LC32HostWeakRetainFirstToken) {
            nextToken = LC32HostWeakRetainFirstToken;
        }
        if(token < LC32HostWeakRetainFirstToken || retains.count(token)) {
            continue;
        }
        try {
            retains.emplace(token, LC32PendingHostWeakRetain{
                ownedHostObject, guestObject, generation,
            });
        } catch(const std::bad_alloc &) {
            return 0;
        }
        return token;
    }
}

extern "C" u32 LC32FinishHostWeakRetain(
        u32 token, u32 guestObject, u32 commit) {
    if(token < LC32HostWeakRetainFirstToken || !guestObject || commit > 1) {
        return 0;
    }

    LC32PendingHostWeakRetain pending = {};
    {
        std::lock_guard<std::mutex> lock(
            LC32PendingHostWeakRetainMutex());
        auto &retains = LC32PendingHostWeakRetains();
        auto iterator = retains.find(token);
        if(iterator == retains.end() ||
           iterator->second.guestObject != guestObject) {
            return 0;
        }
        pending = iterator->second;
        retains.erase(iterator);
    }

    if(!commit) {
        /* Never release inline: SVC 1021 is called from the guest runtime's
         * retainWeakReference hook while its SideTable stripe is locked. */
        LC32DeferOwnedHostRelease(pending.ownedHostObject);
    }
    return 1;
}

extern "C" LC32HostWeakRetainResult
LC32TryRetainHostWeakReference(u32 guestObject) {
    std::shared_ptr<LC32HostWeakMappingEntry> entry;
    bool mappingWasLive = false;
    bool mappingWasPermanent = false;
    {
        LC32HostWeakRegistry &registry = LC32HostWeakMappings();
        std::lock_guard<std::mutex> lock(registry.mutex);
        auto iterator = registry.entries.find(guestObject);
        if(iterator == registry.entries.end()) {
            return LC32HostWeakRetainNoMapping;
        }
        entry = iterator->second;
        mappingWasLive =
            entry->state == LC32HostWeakMappingState::Live;
        mappingWasPermanent = mappingWasLive &&
            entry->lifetime == LC32HostMappingLifetime::Permanent;
    }
    /* A class or process-lifetime constant needs no paired native +1.  Let
     * guest libobjc perform its ordinary local weak try-retain; in particular,
     * a native tagged singleton may not support a weak slot at all. */
    if(mappingWasPermanent) {
        LC32DeferHostWeakEntryRelease(std::move(entry));
        return LC32HostWeakRetainNoMapping;
    }
    if(!mappingWasLive) {
        LC32DeferHostWeakEntryRelease(std::move(entry));
        return LC32HostWeakRetainMappedDead;
    }

    id retainedHostObject = objc_loadWeakRetained(&entry->weakHostObject);
    if(!retainedHostObject) {
        LC32DeferHostWeakEntryRelease(std::move(entry));
        return LC32HostWeakRetainMappedDead;
    }

    bool mappingIsCurrent = false;
    {
        LC32HostWeakRegistry &registry = LC32HostWeakMappings();
        std::lock_guard<std::mutex> lock(registry.mutex);
        auto iterator = registry.entries.find(guestObject);
        mappingIsCurrent = iterator != registry.entries.end() &&
            iterator->second.get() == entry.get() &&
            iterator->second->generation == entry->generation &&
            iterator->second->state == LC32HostWeakMappingState::Live;
    }

#if __has_feature(objc_arc)
    /* Move the load's +1 out of ARC.  On success it belongs to the matching
     * guest try-retain.  A superseded load must be released away from this
     * guest thread: inline deallocation could run the lifetime pin and reenter
     * the guest SideTable stripe which objc_loadWeakRetained still holds. */
    void *ownedHostObject = (__bridge_retained void *)retainedHostObject;
    retainedHostObject = nil;
#else
    void *ownedHostObject = retainedHostObject;
#endif
    if(mappingIsCurrent) {
        const u64 generation = entry->generation;
        LC32DeferHostWeakEntryRelease(std::move(entry));
        const u32 token = LC32CreatePendingHostWeakRetain(
            ownedHostObject, guestObject, generation);
        if(token) return token;
        LC32DeferOwnedHostRelease(ownedHostObject);
        return LC32HostWeakRetainMappedDead;
    }

    LC32DeferOwnedHostRelease(ownedHostObject);
    LC32DeferHostWeakEntryRelease(std::move(entry));
    return LC32HostWeakRetainMappedDead;
}

static int LC32UniqueSelectorArgumentIndexNamed(SEL selector,
                                                 const char *expectedName) {
    const char *component = sel_getName(selector);
    const size_t expectedLength = strlen(expectedName);
    int matchingIndex = -1;
    unsigned int argumentIndex = 0;
    while(component) {
        const char *colon = strchr(component, ':');
        if(!colon) break;
        if((size_t)(colon - component) == expectedLength &&
           memcmp(component, expectedName, expectedLength) == 0) {
            if(matchingIndex >= 0) return -1;
            matchingIndex = (int)argumentIndex;
        }
        component = colon + 1;
        argumentIndex++;
    }
    return matchingIndex;
}

template<typename T>
static bool LC32ReadGuestInvocationValue(u32 guestStorage, T &value) {
    return guestStorage && Dynarmic_mem_1read(
        guestStorage, sizeof(value), reinterpret_cast<char *>(&value)) == 0;
}

template<typename T>
static void LC32StoreHostInvocationValue(
        std::array<u8, 16> &storage, T value) {
    static_assert(sizeof(value) <= 16, "invocation value exceeds staging");
    memcpy(storage.data(), &value, sizeof(value));
}

/*
 * -[NSInvocation setArgument:atIndex:] copies bytes using native type sizes.
 * The supplied pointer, however, names raw ARM32 storage. Rebuild the value
 * into host-owned aligned storage instead of exposing a guest address or
 * letting Foundation read eight-byte pointers from four-byte guest values.
 */
static bool LC32PrepareHostInvocationArgument(
        NSInvocation *invocation, u32 guestStorage, int32_t argumentIndex,
        std::array<u8, 16> &hostStorage) {
    if(!invocation || !guestStorage || argumentIndex < 0) return false;

    NSMethodSignature *signature = invocation.methodSignature;
    if(!signature || (NSUInteger)argumentIndex >= signature.numberOfArguments)
        return false;

    const char *type = [signature getArgumentTypeAtIndex:
        (NSUInteger)argumentIndex];
    while(type && *type && strchr("rnNoORVA", *type)) type++;
    if(!type || !*type) return false;

    NSUInteger nativeSize = 0;
    NSUInteger nativeAlignment = 0;
    NSGetSizeAndAlignment(type, &nativeSize, &nativeAlignment);
    if(!nativeSize || nativeSize > hostStorage.size()) return false;
    hostStorage.fill(0);

    switch(*type) {
        case '@':
        case '#': {
            u32 guestObject = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, guestObject))
                return false;
            const u64 hostObject = guestObject
                ? LC32GuestToHostReturnType(
                    const_cast<char *>(type), guestObject)
                : 0;
            LC32StoreHostInvocationValue(hostStorage, hostObject);
            return nativeSize == sizeof(hostObject);
        }
        case ':': {
            u32 guestSelector = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, guestSelector))
                return false;
            const u64 hostSelector = guestSelector
                ? LC32GetHostSelector(guestSelector)
                : 0;
            LC32StoreHostInvocationValue(hostStorage, hostSelector);
            return nativeSize == sizeof(hostSelector);
        }
        case 'B':
        case 'C': {
            uint8_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'c': {
            int8_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'S': {
            uint16_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 's': {
            int16_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'I': {
            uint32_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'i': {
            int32_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'L': {
            uint32_t guestValue = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, guestValue))
                return false;
            const unsigned long hostValue = guestValue;
            LC32StoreHostInvocationValue(hostStorage, hostValue);
            return nativeSize == sizeof(hostValue);
        }
        case 'l': {
            int32_t guestValue = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, guestValue))
                return false;
            const long hostValue = guestValue;
            LC32StoreHostInvocationValue(hostStorage, hostValue);
            return nativeSize == sizeof(hostValue);
        }
        case 'Q': {
            uint64_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'q': {
            int64_t value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'f': {
            float value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        case 'd': {
            double value = 0;
            if(!LC32ReadGuestInvocationValue(guestStorage, value))
                return false;
            LC32StoreHostInvocationValue(hostStorage, value);
            return nativeSize == sizeof(value);
        }
        default:
            return false;
    }
}

#pragma mark Guest -> Host functions

u32 LC32HostToGuestCopyClassName(u32 guest_output, size_t length, u64 host_object) {
    const char *input = class_getName([(id)host_object class]);
    length = MIN(strlen(input), length);
    // write null terminator aswell
    Dynarmic_mem_1write(guest_output, length+1, (char *)input);
    return length;
}

u32 LC32CopyHostCString(u64 host_cstring, u32 guest_output,
                        size_t capacity) {
    if(!host_cstring) return 0;
    /*
     * This SVC receives a native pointer from guest state.  Do not dereference
     * it with strlen: a stale or malformed value would turn a guest failure
     * into a host EXC_BAD_ACCESS, and a missing terminator would scan without a
     * bound.  Reading our own task through Mach gives invalid addresses a
     * recoverable error and keeps Objective-C type encodings reasonably
     * bounded.
     */
    constexpr size_t maximumByteCount = 4096;
    std::array<char, maximumByteCount> bytes = {};
    size_t byteCount = 0;
    while(byteCount < bytes.size()) {
        if(host_cstring > UINT64_MAX - byteCount) return 0;
        const vm_address_t address = (vm_address_t)(host_cstring + byteCount);
        const size_t pageOffset = address & (vm_page_size - 1);
        const size_t pageRemaining = vm_page_size - pageOffset;
        const size_t requested = MIN(
            pageRemaining, bytes.size() - byteCount);
        vm_size_t copied = 0;
        const kern_return_t result = vm_read_overwrite(
            mach_task_self(), address, requested,
            reinterpret_cast<vm_address_t>(bytes.data() + byteCount),
            &copied);
        if(result != KERN_SUCCESS || copied == 0 || copied > requested) {
            return 0;
        }
        const void *terminator = memchr(
            bytes.data() + byteCount, '\0', (size_t)copied);
        if(terminator) {
            byteCount = static_cast<const char *>(terminator) -
                bytes.data() + 1;
            break;
        }
        byteCount += (size_t)copied;
        if(copied != requested) return 0;
    }
    if(byteCount == bytes.size() && bytes.back() != '\0') return 0;
    if(guest_output && capacity) {
        const size_t copyCount = MIN(byteCount, capacity);
        if(Dynarmic_mem_1write(
                guest_output, copyCount, bytes.data()) != 0) {
            return 0;
        }
        if(copyCount < byteCount) {
            const char terminator = '\0';
            if(Dynarmic_mem_1write(guest_output + copyCount - 1, 1,
                                   (char *)&terminator) != 0) {
                return 0;
            }
        }
    }
    return (u32)byteCount;
}

u32 LC32CopyHostStringUTF8(u64 host_object, u32 guest_output,
                           size_t capacity) {
    const char *bytes = [(NSString *)(id)host_object UTF8String];
    if(!bytes) return 0;

    const size_t byteCount = strlen(bytes) + 1;
    if(byteCount > UINT32_MAX) return 0;
    if(guest_output && capacity) {
        const size_t copyCount = MIN(byteCount, capacity);
        if(Dynarmic_mem_1write(guest_output, copyCount, (char *)bytes) != 0) {
            return 0;
        }
        if(copyCount < byteCount) {
            const char terminator = '\0';
            if(Dynarmic_mem_1write(guest_output + copyCount - 1, 1,
                                   (char *)&terminator) != 0) {
                return 0;
            }
        }
    }
    return (u32)byteCount;
}

u32 LC32CopyHostStringBytes(u64 host_object, u32 encoding,
                            u32 guest_output, u32 capacity) {
    NSString *string = (NSString *)(id)host_object;
    const NSStringEncoding nativeEncoding = (NSStringEncoding)encoding;
    const NSUInteger payloadCount =
        [string lengthOfBytesUsingEncoding:nativeEncoding];
    if(payloadCount >= UINT32_MAX) return 0;

    const u32 byteCount = (u32)payloadCount + 1;
    char *bytes = (char *)malloc(byteCount);
    if(!bytes) return 0;
    if(![string getCString:bytes maxLength:byteCount
                  encoding:nativeEncoding]) {
        free(bytes);
        return 0;
    }

    if(guest_output && capacity >= byteCount &&
            Dynarmic_mem_1write(guest_output, byteCount, bytes) != 0) {
        free(bytes);
        return 0;
    }
    free(bytes);
    return byteCount;
}

u64 LC32HostStringRangeOfString(
        const LC32FoundationStringRangeRequest *request) {
    const u64 hostString = (u64)request->hostStringLow |
        ((u64)request->hostStringHigh << 32);
    const u64 hostNeedle = (u64)request->hostNeedleLow |
        ((u64)request->hostNeedleHigh << 32);
    const u64 hostLocale = (u64)request->hostLocaleLow |
        ((u64)request->hostLocaleHigh << 32);
    NSString *source = (NSString *)(id)hostString;
    NSString *needle = (NSString *)(id)hostNeedle;
    NSRange range;
    switch(request->variant) {
        case LC32FoundationStringRangePlain:
            range = [source rangeOfString:needle];
            break;
        case LC32FoundationStringRangeWithOptions:
            range = [source rangeOfString:needle
                                  options:(NSStringCompareOptions)
                                              request->options];
            break;
        case LC32FoundationStringRangeWithRange:
            range = [source rangeOfString:needle
                                  options:(NSStringCompareOptions)
                                              request->options
                                    range:NSMakeRange(request->rangeLocation,
                                                      request->rangeLength)];
            break;
        case LC32FoundationStringRangeWithLocale:
            range = [source rangeOfString:needle
                                  options:(NSStringCompareOptions)
                                              request->options
                                    range:NSMakeRange(request->rangeLocation,
                                                      request->rangeLength)
                                   locale:(NSLocale *)(id)hostLocale];
            break;
        default:
            return (u64)INT32_MAX;
    }

    /* NSNotFound is NSIntegerMax in each process, so it must be translated
     * rather than merely truncating the ARM64 value to its low word. */
    const u32 location = range.location == NSNotFound
        ? (u32)INT32_MAX : (u32)range.location;
    const u32 length = (u32)range.length;
    return (u64)location | ((u64)length << 32);
}

static bool LC32HostObjectIsDispatchData(id object) {
    for(Class cls = object_getClass(object); cls;
            cls = class_getSuperclass(cls)) {
        const char *name = class_getName(cls);
        if(name && (!strcmp(name, "OS_dispatch_data") ||
                    !strcmp(name, "OS_dispatch_data_empty"))) {
            return true;
        }
    }
    return false;
}

u32 LC32CopyHostDataBytes(u64 host_object, u32 guest_output, u32 length,
                          u32 offset) {
    id object = (id)host_object;
    const void *bytes = nullptr;
    size_t dataLength = 0;
    dispatch_data_t mappedData = nullptr;

    if(LC32HostObjectIsDispatchData(object)) {
        dispatch_data_t data = (dispatch_data_t)object;
        dataLength = dispatch_data_get_size(data);
        if(offset > dataLength || length > dataLength - offset) {
            return UINT32_MAX;
        }
        if(!length) return 0;

        size_t mappedLength = 0;
        mappedData = dispatch_data_create_map(data, &bytes, &mappedLength);
        if(!mappedData || mappedLength < dataLength) {
            return UINT32_MAX;
        }
    } else {
        NSData *data = (NSData *)object;
        dataLength = data.length;
        if(offset > dataLength || length > dataLength - offset) {
            return UINT32_MAX;
        }
        if(!length) return 0;
        bytes = data.bytes;
    }

    if(!bytes || !guest_output || Dynarmic_mem_1write(
            guest_output, length,
            (char *)bytes + offset) != 0) {
        return UINT32_MAX;
    }
    return length;
}

u64 LC32Dlsym(u32 guest_name, bool isFunction) {
    DynarmicHostString host_name(guest_name);
    
    u64 r = (u64)dlsym(RTLD_DEFAULT, host_name.hostPtr);
    if(r && !isFunction) r = *(u64*)r;
    printf("LC32: dlsym %s = 0x%llx\n", host_name.hostPtr, r);
    return r;
}

inline id LC32GetHostConstString(u32 guest_self) {
    // Construct a __NSCFConstantString { isa, flags, buffer, length }
    u64 *constStr = (u64 *)malloc(sizeof(u64[4]));
    constStr[0] = (u64)__CFConstantStringClassReference;
    constStr[1] = (u64)Dynarmic_current_user_callbacks()->MemoryRead32(guest_self + sizeof(u32[1]));
    u64 length = (u64)Dynarmic_current_user_callbacks()->MemoryRead32(guest_self + sizeof(u32[3]));
    DynarmicHostString host_str(Dynarmic_current_user_callbacks()->MemoryRead32(guest_self + sizeof(u32[2])), length);
    /*
     * A cross-page copy is detached for this immortal native constant.  The
     * bit-63 ownership marker is meaningful only while returning the pointer
     * to guest code for a later SVC 1004; it is never part of a host address.
     */
    constStr[2] = (u64)host_str.hostPtrForGuest() &
        ~DynarmicHostString_NEED_FREE;
    constStr[3] = length;
    return (id)constStr;
}

u64 LC32GetHostObject(u32 guest_self, u32 guest_className, bool returnClass) {
    DynarmicHostString host_className(guest_className);
    Class cls = objc_getClass(host_className.hostPtr);
    if(returnClass) {
        [(id)cls setGuest_self:guest_self];
        return (u64)cls;
    }

    const bool isGuestClass = [(id)cls isGuestClass];
    const bool isConstantStringClass =
        object_getClass(cls) ==
            object_getClass((Class)__CFConstantStringClassReference);
    id obj;
    if(isConstantStringClass) {
        obj = LC32GetHostConstString(guest_self);
    } else if(isGuestClass) {
        /*
         * The guest has already allocated this object; we only need a native
         * mirror with the same dynamic class.  Sending +alloc here can enter
         * a guest singleton's overridden +allocWithZone:, which asks for the
         * same host mirror again and recurses until the host stack overflows.
         */
        obj = class_createInstance(cls, 0);
    } else {
        obj = [cls alloc];
    }
    [obj setGuest_self:guest_self];
    LC32OperationTraceLiveObject(
        "guest-created-host-peer", obj, guest_self);
    if(isGuestClass) {
        // Dynamic guest classes have unique native allocations but no native
        // initializer shim where the final mirror can be pinned.
        LC32PinGuestObjectToHost(obj, guest_self, true);
    }
    return (u64)obj;
}

u64 LC32GetHostSelector(u32 guest_selector) {
    DynarmicHostString host_selector(guest_selector);
    return (u64)sel_registerName(host_selector.hostPtr);
}

static bool LC32NativeNSRangeType(const char *type) {
    while(type && *type && strchr("rnNoORVA", *type)) type++;
    if(!type ||
       (strncmp(type, "{_NSRange=", sizeof("{_NSRange=") - 1) &&
        strncmp(type, "{NSRange=", sizeof("{NSRange=") - 1))) {
        return false;
    }
    const char *fields = strchr(type, '=');
    return fields && fields[1] == 'Q' && fields[2] == 'Q' &&
        fields[3] == '}' && fields[4] == '\0';
}

static bool LC32NativeNSDecimalType(const char *type) {
    while(type && *type && strchr("rnNoORVA", *type)) type++;
    return type &&
        strcmp(type, "{?=b8b4b1b1b18[8S]}") == 0;
}

static bool LC32SelectorUsesHostStackVarargs(SEL selector) {
    if(!selector) return false;
    const char *name = sel_getName(selector);
    if(!name) return false;

    /*
     * Darwin's ARM64 ABI puts unnamed variadic arguments on the stack even
     * when integer argument registers remain unused.  Objective-C method
     * encodings do not record the trailing ellipsis, so keep the small set of
     * framework entry points which still cross this bridge explicitly.  The
     * Foundation collection/string variants are implemented in guest code
     * and therefore do not normally reach here, but recognizing the
     * collection selectors makes the fallback path safe as well.
     */
    return !strcmp(name,
               "initWithTitle:message:delegate:cancelButtonTitle:"
               "otherButtonTitles:") ||
        !strcmp(name,
               "initWithTitle:delegate:cancelButtonTitle:"
               "destructiveButtonTitle:otherButtonTitles:") ||
        !strcmp(name, "arrayWithObjects:") ||
        !strcmp(name, "initWithObjects:") ||
        !strcmp(name, "setWithObjects:") ||
        !strcmp(name, "orderedSetWithObjects:") ||
        !strcmp(name, "dictionaryWithObjectsAndKeys:") ||
        !strcmp(name, "initWithObjectsAndKeys:") ||
        !strcmp(name, "appearanceWhenContainedIn:") ||
        !strcmp(name, "appearanceForTraitCollection:whenContainedIn:");
}

// guest to host call of objc_msgSend*
u64 LC32InvokeHostSelector(u64 host_self, u64 host_cmd, u64 va_args) {
    // ARMv7 stores parameters in r0-r3 and stack pointer. r0-r3 is already reserved for self and cmd, so we read the rest from stack pointer

    u32 structPtr = 0, structLen;
    const bool returnGuestObject =
        (host_cmd & SEL_RETURN_GUEST_OBJECT) != 0;
    if(returnGuestObject && (host_cmd & SEL_RETURN_STRUCT)) {
        fprintf(stderr,
            "LC32: selector cannot request both struct and guest-object "
            "returns\n");
        return 0;
    }
    if(host_cmd & SEL_RETURN_STRUCT) {
        host_cmd &= ~SEL_RETURN_STRUCT;
        structPtr = Dynarmic_current_user_callbacks()->MemoryRead32(va_args);
        structLen = Dynarmic_current_user_callbacks()->MemoryRead32(va_args += sizeof(u32));
        va_args += sizeof(u32);
    }
    host_cmd &= ~SEL_RETURN_GUEST_OBJECT;

    // FIXME: how to read number of args for variadic methods and translate its values?
    u64 args[9] = {
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64)),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64)),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64)),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64)),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64)),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64)),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64)),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64))
    };

    /*
     * A guest pointer cannot be handed to an ARM64 Objective-C method. Shim
     * sources tag pointers to 64-bit guest temporaries; substitute native
     * stack storage for objc_msgSend and copy the result back afterwards.
     * Looking at the method encoding prevents a negative scalar or floating
     * bit pattern from ever being mistaken for an indirect argument.
     */
    u32 indirectGuestStorage[9] = {};
    u64 indirectHostStorage[9] = {};
    u32 sizedIndirectGuestStorage[9] = {};
    u32 sizedIndirectSize[9] = {};
    alignas(16) std::array<u8,
        LC32_HOST_SIZED_INDIRECT_MAX_SIZE> sizedIndirectHostStorage[9] = {};
    enum class LC32FloatingIndirectType : u8 {
        None,
        Float,
        Double,
    };
    LC32FloatingIndirectType floatingIndirectType[9] = {};
    float floatingIndirectFloatStorage[9] = {};
    double floatingIndirectDoubleStorage[9] = {};
    alignas(16) std::array<u8, 64> aggregateHostStorage[9] = {};
    size_t aggregateHostSize[9] = {};
    alignas(16) std::array<u8, 16> invocationHostStorage[9] = {};
    std::unique_ptr<u64[]> objectArrayHostStorage[9];
    id receiver = (id)host_self;
    SEL selector = (SEL)host_cmd;
    const char *selectorName = selector ? sel_getName(selector) : nullptr;
    if(selectorName &&
       (!strcmp(selectorName, "setStatusBarOrientation:") ||
        !strcmp(selectorName, "setStatusBarOrientation:animated:"))) {
        /* This selector is ignored by modern UIApplication. Preserve the
         * guest-originated orientation intent for the UIWindowScene adapter;
         * the adapter defers work until this guest-to-host call unwinds. */
        LC32UIKitHandleLegacyStatusBarOrientation((u32)args[0]);
    }
    /*
     * Do this before object_getClass(receiver): the diagnostic is specifically
     * meant to survive a stale setCompletionBlock: receiver.  Lookup touches
     * only our raw-address registry when the operation is already dead.
    */
    LC32OperationTraceRawSelector(receiver, selector, args[0]);
    Class dispatchClass = object_getClass(receiver);
    const bool invokeSuper = [(id)dispatchClass isGuestClass];
    if(invokeSuper && selector == @selector(release)) {
        Method releaseMethod = class_getInstanceMethod(
            dispatchClass, selector);
        if(releaseMethod && method_getImplementation(releaseMethod) ==
                (IMP)&LC32GuestMirrorRelease) {
            /* Ordinary guest-to-host sends deliberately start at the first
             * native superclass, avoiding recursion into guest methods. The
             * synthesized mirror's release override is host-only, however,
             * and must coordinate its final native +1 with the guest lifetime
             * pin while the mirror is still alive. */
            LC32GuestMirrorRelease(receiver, selector);
            return 0;
        }
    }
    if(invokeSuper) {
        do {
            dispatchClass = class_getSuperclass(dispatchClass);
        } while(dispatchClass && [(id)dispatchClass isGuestClass]);
    }
    Method method = dispatchClass
        ? class_getInstanceMethod(dispatchClass, selector)
        : nullptr;
    if(!method && invokeSuper) {
        /*
         * A guest-backed mirror forwarded this message to the host, but the
         * host class chain has no implementation for it.  The guest framework
         * shims (e.g. the iOS-10 UITableView) carry delegate-callback methods
         * such as scrollViewDidEndDecelerating: which the newer host UIKit
         * refactored away, so the mirror legitimately responds to them while
         * the host dispatch finds nothing.  Real iOS would run the class's
         * own inherited implementation; the correct emulation is a no-op, not
         * raising "unrecognized selector" through the host forwarder.
         */
        printf("LC32: host dispatch for %s on guest-mirror %s has no "
               "implementation; ignoring\n",
               sel_getName(selector),
               receiver ? class_getName(object_getClass(receiver)) : "<nil>");
        return 0;
    }
    if(method) {
        const unsigned int argumentCount =
            MIN(method_getNumberOfArguments(method) - 2, 9u);
        for(unsigned int index = 0; index < argumentCount; index++) {
            char *argumentType =
                method_copyArgumentType(method, index + 2);
            if(!argumentType) continue;
            const char *unqualifiedType = argumentType;
            while(*unqualifiedType &&
                    strchr("rnNoORVA", *unqualifiedType)) {
                unqualifiedType++;
            }
            if(unqualifiedType[0] == '@' &&
               unqualifiedType[1] != '?') {
                LC32TraceNativeNetworkObject(
                    "guest->host", selector, index, (id)args[index]);
            }
            if(unqualifiedType[0] == '@' &&
                    LC32BlockArgumentTraceEnabled()) {
                id nativeBlock = (id)args[index];
                const char *argumentClass = nativeBlock
                    ? class_getName(object_getClass(nativeBlock))
                    : nullptr;
                const bool isNativeBlock =
                    unqualifiedType[1] == '?' ||
                    (argumentClass && strstr(argumentClass, "Block"));
                if(isNativeBlock) {
                    fprintf(stderr,
                        "LC32 block argument: -[%s %s] index=%u "
                        "declared=%s native=%p class=%s guest=0x%08x\n",
                        receiver
                            ? class_getName(object_getClass(receiver))
                            : "(null)",
                        sel_getName(selector), index, unqualifiedType,
                        nativeBlock, argumentClass ?: "(null)",
                        nativeBlock ? [nativeBlock guest_selfOrNull] : 0);
                    fflush(stderr);
                }
            }
            /*
             * LC32GuestToHostCString marks heap-backed cross-page strings in
             * bit 63 so the guest can release them after this synchronous
             * call. That ownership bit is not part of the native address.
             */
            if(*unqualifiedType == '*' &&
               (args[index] & DynarmicHostString_NEED_FREE)) {
                args[index] &= ~DynarmicHostString_NEED_FREE;
            }
            const u64 argumentTag =
                args[index] & LC32_GUEST_ARGUMENT_TAG_MASK;
            const char *unqualifiedPointeeType = nullptr;
            if(*unqualifiedType == '^') {
                unqualifiedPointeeType = unqualifiedType + 1;
                while(*unqualifiedPointeeType &&
                        strchr("rnNoORVA", *unqualifiedPointeeType)) {
                    unqualifiedPointeeType++;
                }
            }
            const bool isTaggedPointer =
                *unqualifiedType == '^' &&
                argumentTag == LC32_GUEST_INDIRECT_ARGUMENT_TAG &&
                (u32)args[index] != 0;
            const bool isTaggedFloatingPointer =
                unqualifiedPointeeType &&
                (*unqualifiedPointeeType == 'f' ||
                 *unqualifiedPointeeType == 'd') &&
                argumentTag ==
                    LC32_GUEST_FLOATING_INDIRECT_ARGUMENT_TAG &&
                (u32)args[index] != 0;
            const bool isTaggedSizedPointer =
                *unqualifiedType == '^' &&
                argumentTag ==
                    LC32_GUEST_SIZED_INDIRECT_ARGUMENT_TAG &&
                (u32)args[index] != 0;
            const bool isTaggedObjectArray =
                unqualifiedType[0] == '^' &&
                unqualifiedType[1] == '@' &&
                argumentTag == LC32_GUEST_OBJECT_ARRAY_ARGUMENT_TAG &&
                (u32)args[index] != 0;
            const bool isTaggedAggregate =
                unqualifiedType[0] == '{' &&
                argumentTag == LC32_GUEST_AGGREGATE_ARGUMENT_TAG &&
                (u32)args[index] != 0;
            const bool isTaggedInvocationArgument =
                unqualifiedType[0] == '^' &&
                argumentTag == LC32_GUEST_INVOCATION_ARGUMENT_TAG &&
                (u32)args[index] != 0;
            if(argumentTag == LC32_GUEST_INVOCATION_ARGUMENT_TAG) {
                const bool validInvocationArgument =
                    isTaggedInvocationArgument && index == 0 &&
                    selector == @selector(setArgument:atIndex:) &&
                    [receiver isKindOfClass:NSInvocation.class];
                const int32_t invocationIndex = (int32_t)(u32)args[1];
                if(!validInvocationArgument ||
                   !LC32PrepareHostInvocationArgument(
                       (NSInvocation *)receiver, (u32)args[index],
                       invocationIndex, invocationHostStorage[index])) {
                    printf("LC32: invalid NSInvocation argument %d for %s\n",
                           invocationIndex, sel_getName(selector));
                    free(argumentType);
                    return 0;
                }
                args[index] =
                    (u64)invocationHostStorage[index].data();
                free(argumentType);
                continue;
            }
            if(argumentTag == LC32_GUEST_OBJECT_ARRAY_ARGUMENT_TAG &&
               !isTaggedObjectArray) {
                printf("LC32: refusing object-array argument %u for "
                       "non-object-pointer selector %s\n", index,
                       sel_getName(selector));
                free(argumentType);
                return 0;
            }
            if(argumentTag == LC32_GUEST_INDIRECT_ARGUMENT_TAG &&
               !isTaggedPointer) {
                printf("LC32: refusing indirect argument %u for "
                       "non-pointer selector %s\n", index,
                       sel_getName(selector));
                free(argumentType);
                return 0;
            }
            if(argumentTag ==
                    LC32_GUEST_FLOATING_INDIRECT_ARGUMENT_TAG &&
               !isTaggedFloatingPointer) {
                printf("LC32: refusing floating-indirect argument %u for "
                       "non-floating-pointer selector %s\n", index,
                       sel_getName(selector));
                free(argumentType);
                return 0;
            }
            if(argumentTag ==
                    LC32_GUEST_SIZED_INDIRECT_ARGUMENT_TAG &&
               !isTaggedSizedPointer) {
                printf("LC32: refusing sized-indirect argument %u for "
                       "non-pointer selector %s\n", index,
                       sel_getName(selector));
                free(argumentType);
                return 0;
            }
            if(argumentTag == LC32_GUEST_AGGREGATE_ARGUMENT_TAG &&
               !isTaggedAggregate) {
                printf("LC32: refusing aggregate argument %u for "
                       "non-aggregate selector %s\n", index,
                       sel_getName(selector));
                free(argumentType);
                return 0;
            }
            if(isTaggedObjectArray) {
                const u32 guestStorage = (u32)args[index];
                LC32HostObjectArrayDescriptor descriptor = {};
                const int selectorCountArgumentIndex =
                    LC32UniqueSelectorArgumentIndexNamed(selector, "count");
                if(Dynarmic_mem_1read(guestStorage, sizeof(descriptor),
                        reinterpret_cast<char *>(&descriptor)) != 0 ||
                   descriptor.magic != LC32_HOST_OBJECT_ARRAY_MAGIC ||
                   descriptor.reserved != 0 ||
                   descriptor.count > LC32_HOST_OBJECT_ARRAY_MAX_COUNT ||
                   selectorCountArgumentIndex < 0 ||
                   descriptor.countArgumentIndex !=
                       (u32)selectorCountArgumentIndex ||
                   descriptor.countArgumentIndex >= argumentCount ||
                   descriptor.countArgumentIndex == index) {
                    printf("LC32: invalid object-array descriptor for "
                           "argument %u of %s\n", index,
                           sel_getName(selector));
                    free(argumentType);
                    return 0;
                }

                char *countType = method_copyArgumentType(
                    method, descriptor.countArgumentIndex + 2);
                const char *unqualifiedCountType = countType;
                while(unqualifiedCountType && *unqualifiedCountType &&
                        strchr("rnNoORVA", *unqualifiedCountType)) {
                    unqualifiedCountType++;
                }
                const bool validCountType = unqualifiedCountType &&
                    strchr("CILQS", *unqualifiedCountType) != nullptr;
                free(countType);
                if(!validCountType ||
                   args[descriptor.countArgumentIndex] != descriptor.count) {
                    printf("LC32: mismatched object-array count for "
                           "argument %u of %s\n", index,
                           sel_getName(selector));
                    free(argumentType);
                    return 0;
                }

                const u64 objectBytes =
                    (u64)descriptor.count * sizeof(u64);
                const u64 objectAddress =
                    (u64)guestStorage + sizeof(descriptor);
                if(objectAddress + objectBytes > UINT64_C(0x100000000)) {
                    printf("LC32: overflowing object-array descriptor for "
                           "argument %u of %s\n", index,
                           sel_getName(selector));
                    free(argumentType);
                    return 0;
                }

                if(descriptor.count) {
                    objectArrayHostStorage[index].reset(
                        new(std::nothrow) u64[descriptor.count]);
                    if(!objectArrayHostStorage[index]) {
                        printf("LC32: cannot allocate object-array argument "
                               "%u of %s\n", index,
                               sel_getName(selector));
                        free(argumentType);
                        return 0;
                    }
                }
                if(objectBytes && Dynarmic_mem_1read(
                        (u32)objectAddress, (size_t)objectBytes,
                        reinterpret_cast<char *>(
                            objectArrayHostStorage[index].get())) != 0) {
                    printf("LC32: unreadable object-array descriptor for "
                           "argument %u of %s\n", index,
                           sel_getName(selector));
                    free(argumentType);
                    return 0;
                }
                args[index] = descriptor.count
                    ? (u64)objectArrayHostStorage[index].get()
                    : 0;
                free(argumentType);
                continue;
            }
            if(isTaggedAggregate) {
                NSUInteger nativeSize = 0;
                NSUInteger nativeAlignment = 0;
                if(LC32NativeNSDecimalType(unqualifiedType)) {
                    static_assert(sizeof(NSDecimal) == 20,
                        "unexpected native NSDecimal layout");
                    static_assert(alignof(NSDecimal) == 4,
                        "unexpected native NSDecimal alignment");
                    nativeSize = sizeof(NSDecimal);
                    nativeAlignment = alignof(NSDecimal);
                } else {
                    NSGetSizeAndAlignment(unqualifiedType, &nativeSize,
                                          &nativeAlignment);
                }
                if(!nativeSize || nativeSize >
                        aggregateHostStorage[index].size() ||
                   Dynarmic_mem_1read((u32)args[index], nativeSize,
                       reinterpret_cast<char *>(
                           aggregateHostStorage[index].data())) != 0) {
                    printf("LC32: invalid aggregate argument %u of %s "
                           "(size=%lu alignment=%lu)\n", index,
                           sel_getName(selector), (unsigned long)nativeSize,
                           (unsigned long)nativeAlignment);
                    free(argumentType);
                    return 0;
                }
                aggregateHostSize[index] = nativeSize;
                free(argumentType);
                continue;
            }
            if(isTaggedSizedPointer) {
                LC32HostSizedIndirectDescriptor descriptor = {};
                const u32 descriptorAddress = (u32)args[index];
                const bool validDescriptor =
                    Dynarmic_mem_1read(descriptorAddress,
                        sizeof(descriptor), reinterpret_cast<char *>(
                            &descriptor)) == 0 &&
                    descriptor.magic == LC32_HOST_SIZED_INDIRECT_MAGIC &&
                    descriptor.reserved == 0 && descriptor.storage != 0 &&
                    descriptor.size != 0 &&
                    descriptor.size <=
                        LC32_HOST_SIZED_INDIRECT_MAX_SIZE &&
                    (u64)descriptor.storage + descriptor.size <=
                        UINT64_C(0x100000000) &&
                    Dynarmic_mem_1read(descriptor.storage, descriptor.size,
                        reinterpret_cast<char *>(
                            sizedIndirectHostStorage[index].data())) == 0;
                if(!validDescriptor) {
                    printf("LC32: invalid sized-indirect argument %u of %s\n",
                           index, sel_getName(selector));
                    free(argumentType);
                    return 0;
                }
                sizedIndirectGuestStorage[index] = descriptor.storage;
                sizedIndirectSize[index] = descriptor.size;
                args[index] = (u64)sizedIndirectHostStorage[index].data();
                free(argumentType);
                continue;
            }
            if(isTaggedFloatingPointer) {
                const u32 guestStorage = (u32)args[index];
                double canonicalValue = 0.0;
                args[index] = 0;
                if(Dynarmic_mem_1read(
                        guestStorage, sizeof(canonicalValue),
                        reinterpret_cast<char *>(&canonicalValue)) != 0) {
                    free(argumentType);
                    continue;
                }
                indirectGuestStorage[index] = guestStorage;
                if(*unqualifiedPointeeType == 'f') {
                    floatingIndirectType[index] =
                        LC32FloatingIndirectType::Float;
                    floatingIndirectFloatStorage[index] =
                        (float)canonicalValue;
                    args[index] =
                        (u64)&floatingIndirectFloatStorage[index];
                } else {
                    floatingIndirectType[index] =
                        LC32FloatingIndirectType::Double;
                    floatingIndirectDoubleStorage[index] = canonicalValue;
                    args[index] =
                        (u64)&floatingIndirectDoubleStorage[index];
                }
                free(argumentType);
                continue;
            }
            free(argumentType);
            if(!isTaggedPointer) continue;

            const u32 guestStorage = (u32)args[index];
            args[index] = 0;
            if(!guestStorage || Dynarmic_mem_1read(
                    guestStorage, sizeof(indirectHostStorage[index]),
                    reinterpret_cast<char *>(
                        &indirectHostStorage[index])) != 0) {
                continue;
            }
            indirectGuestStorage[index] = guestStorage;
            args[index] = (u64)&indirectHostStorage[index];
        }
    } else {
        for(size_t index = 0; index < 9; index++) {
            const u64 argumentTag =
                args[index] & LC32_GUEST_ARGUMENT_TAG_MASK;
            if((argumentTag != LC32_GUEST_INDIRECT_ARGUMENT_TAG &&
                argumentTag !=
                    LC32_GUEST_FLOATING_INDIRECT_ARGUMENT_TAG &&
                argumentTag !=
                    LC32_GUEST_SIZED_INDIRECT_ARGUMENT_TAG &&
                argumentTag != LC32_GUEST_OBJECT_ARRAY_ARGUMENT_TAG &&
                argumentTag != LC32_GUEST_AGGREGATE_ARGUMENT_TAG &&
                argumentTag != LC32_GUEST_INVOCATION_ARGUMENT_TAG) ||
               !(u32)args[index]) {
                continue;
            }
            printf("LC32: cannot marshal pointer argument %zu for "
                   "unresolved selector %s\n", index,
                   sel_getName(selector));
            return 0;
        }
    }

    auto finishIndirectArguments = [&](u64 result) -> u64 {
        for(size_t index = 0; index < 9; index++) {
            if(sizedIndirectGuestStorage[index]) {
                (void)Dynarmic_mem_1write(
                    sizedIndirectGuestStorage[index],
                    sizedIndirectSize[index],
                    reinterpret_cast<char *>(
                        sizedIndirectHostStorage[index].data()));
                continue;
            }
            if(!indirectGuestStorage[index]) continue;
            if(floatingIndirectType[index] ==
                    LC32FloatingIndirectType::Float) {
                floatingIndirectDoubleStorage[index] =
                    (double)floatingIndirectFloatStorage[index];
                (void)Dynarmic_mem_1write(
                    indirectGuestStorage[index],
                    sizeof(floatingIndirectDoubleStorage[index]),
                    reinterpret_cast<char *>(
                        &floatingIndirectDoubleStorage[index]));
                continue;
            }
            if(floatingIndirectType[index] ==
                    LC32FloatingIndirectType::Double) {
                (void)Dynarmic_mem_1write(
                    indirectGuestStorage[index],
                    sizeof(floatingIndirectDoubleStorage[index]),
                    reinterpret_cast<char *>(
                        &floatingIndirectDoubleStorage[index]));
                continue;
            }
            (void)Dynarmic_mem_1write(
                indirectGuestStorage[index],
                sizeof(indirectHostStorage[index]),
                reinterpret_cast<char *>(
                    &indirectHostStorage[index]));
        }
        return result;
    };

    /*
     * AAPCS64 allocates scalar floating-point arguments and integer/pointer
     * arguments from independent register banks. The guest shim transports
     * each logical scalar in one 64-bit stack slot, so compact those slots by
     * host type before entering objc_msgSend. In particular, a leading
     * double belongs in d0 and must not also consume x2.
     *
     * Generated float arguments are promoted to double by the variadic guest
     * call. Convert them back to float and place their bits in the low half
     * of the corresponding v register. Known UIKit/CoreGraphics aggregates
     * are transported as one tagged slot. Two- and four-double HFAs occupy
     * d-registers; the six-double CGAffineTransform is passed indirectly.
     */
    u64 integerArguments[9] = {};
    u64 floatingArguments[8] = {};
    bool useTypedScalarArguments = method != nullptr;
    if(method) {
        const unsigned int argumentCount =
            method_getNumberOfArguments(method) - 2;
        size_t integerArgumentCount = 0;
        size_t floatingArgumentCount = 0;
        if(argumentCount > 9) useTypedScalarArguments = false;

        for(unsigned int index = 0;
                useTypedScalarArguments && index < argumentCount; index++) {
            char *argumentType =
                method_copyArgumentType(method, index + 2);
            const char *unqualifiedType = argumentType;
            while(unqualifiedType && *unqualifiedType &&
                    strchr("rnNoORVA", *unqualifiedType)) {
                unqualifiedType++;
            }

            switch(unqualifiedType ? *unqualifiedType : '\0') {
                case 'f': {
                    if(floatingArgumentCount >= 8) {
                        useTypedScalarArguments = false;
                        break;
                    }
                    double promotedValue;
                    memcpy(&promotedValue, &args[index],
                           sizeof(promotedValue));
                    const float hostValue = (float)promotedValue;
                    u32 hostBits;
                    memcpy(&hostBits, &hostValue, sizeof(hostBits));
                    floatingArguments[floatingArgumentCount++] = hostBits;
                    break;
                }
                case 'd':
                    if(floatingArgumentCount >= 8) {
                        useTypedScalarArguments = false;
                        break;
                    }
                    floatingArguments[floatingArgumentCount++] = args[index];
                    break;
                case '{': {
                    const size_t nativeSize = aggregateHostSize[index];
                    if(!nativeSize) {
                        useTypedScalarArguments = false;
                        break;
                    }
                    if(LC32NativeNSRangeType(unqualifiedType)) {
                        if(nativeSize != sizeof(NSRange)) {
                            useTypedScalarArguments = false;
                            break;
                        }
                        /*
                         * AAPCS64 does not split a composite between x7 and
                         * the stack.  Leave the last register unused when
                         * only one of the two NSUInteger slots still fits.
                         */
                        if(integerArgumentCount == 5)
                            integerArgumentCount = 6;
                        if(integerArgumentCount + 2 > 9) {
                            useTypedScalarArguments = false;
                            break;
                        }
                        NSRange range;
                        memcpy(&range,
                               aggregateHostStorage[index].data(),
                               sizeof(range));
                        integerArguments[integerArgumentCount++] =
                            (u64)range.location;
                        integerArguments[integerArgumentCount++] =
                            (u64)range.length;
                        break;
                    }
                    if(nativeSize == sizeof(double) * 2 ||
                       nativeSize == sizeof(double) * 4) {
                        const size_t elementCount =
                            nativeSize / sizeof(double);
                        if(floatingArgumentCount + elementCount > 8) {
                            /* AAPCS64 spills the whole HFA when it does not
                             * fit. The fixed trampoline has no typed FP stack
                             * path yet, so reject instead of corrupting it. */
                            useTypedScalarArguments = false;
                            break;
                        }
                        for(size_t element = 0; element < elementCount;
                                element++) {
                            memcpy(&floatingArguments[
                                       floatingArgumentCount++],
                                   aggregateHostStorage[index].data() +
                                       element * sizeof(double),
                                   sizeof(double));
                        }
                        break;
                    }
                    if(nativeSize > 16) {
                        integerArguments[integerArgumentCount++] =
                            (u64)aggregateHostStorage[index].data();
                        break;
                    }
                    useTypedScalarArguments = false;
                    break;
                }
                case '@':
                case '#':
                case ':':
                case '*':
                case '^':
                case '?':
                case 'B':
                case 'C':
                case 'I':
                case 'L':
                case 'Q':
                case 'S':
                case 'b':
                case 'c':
                case 'i':
                case 'l':
                case 'q':
                case 's':
                    integerArguments[integerArgumentCount++] = args[index];
                    break;
                default:
                    useTypedScalarArguments = false;
                    break;
            }
            free(argumentType);
        }
        if(useTypedScalarArguments) {
            /*
             * Objective-C metadata describes only the fixed portion of a
             * variadic method. Preserve the shim's remaining raw slots (and
             * its explicit zero terminator) after the typed fixed arguments.
             * On Darwin ARM64, unnamed variadic arguments start on the stack,
             * not in unused x registers.  The fixed trampoline below places
             * integerArguments[0...5] in x2...x7 and begins its stack payload
             * at integerArguments[6], so leave the unused register slots
             * empty for the variadic selectors known to cross this bridge.
             */
            if(LC32SelectorUsesHostStackVarargs(selector) &&
               integerArgumentCount < 6) {
                integerArgumentCount = 6;
            }
            for(size_t index = argumentCount;
                    index < 9 && integerArgumentCount < 9; index++) {
                integerArguments[integerArgumentCount++] = args[index];
            }
        }
    }
    if(!useTypedScalarArguments) {
        memcpy(integerArguments, args, sizeof(integerArguments));
        memcpy(floatingArguments, args, sizeof(floatingArguments));
    }

    typedef u64(*objc_msgSendFunc)(u64 x0, u64 x1, u64 x2, u64 x3, u64 x4, u64 x5, u64 x6, u64 x7, ...);
    typedef float(*objc_msgSendFloatFunc)(u64 x0, u64 x1, u64 x2, u64 x3, u64 x4, u64 x5, u64 x6, u64 x7, ...);
    typedef double(*objc_msgSendDoubleFunc)(u64 x0, u64 x1, u64 x2, u64 x3, u64 x4, u64 x5, u64 x6, u64 x7, ...);
    struct LC32_TwoDoubles {
        double d0, d1;
    };
    struct LC32_TwoU64 {
        u64 x0, x1;
    };
    struct LC32_FourDoubles {
        double d0, d1, d2, d3;
    };
    typedef LC32_TwoDoubles(*objc_msgSendTwoDoublesFunc)(u64 x0, u64 x1, u64 x2, u64 x3, u64 x4, u64 x5, u64 x6, u64 x7, ...);
    typedef LC32_TwoU64(*objc_msgSendTwoU64Func)(u64 x0, u64 x1, u64 x2, u64 x3, u64 x4, u64 x5, u64 x6, u64 x7, ...);
    typedef LC32_FourDoubles(*objc_msgSendFourDoublesFunc)(u64 x0, u64 x1, u64 x2, u64 x3, u64 x4, u64 x5, u64 x6, u64 x7, ...);
    typedef LC32_SixDoubles(*objc_msgSendSixDoublesFunc)(u64 x0, u64 x1, u64 x2, u64 x3, u64 x4, u64 x5, u64 x6, u64 x7, ...);

    enum class HostReturnKind {
        Integer,
        Float,
        Double,
    } returnKind = HostReturnKind::Integer;
    bool returnsBlock = false;
    bool returnsNSRange = false;
    if(method) {
        char *returnType = method_copyReturnType(method);
        if(returnType) {
            const char *unqualifiedType = returnType;
            while(*unqualifiedType &&
                    strchr("rnNoORVA", *unqualifiedType)) {
                unqualifiedType++;
            }
            if(*unqualifiedType == 'f') {
                returnKind = HostReturnKind::Float;
            } else if(*unqualifiedType == 'd') {
                returnKind = HostReturnKind::Double;
            }
            returnsBlock = unqualifiedType[0] == '@' &&
                unqualifiedType[1] == '?';
            returnsNSRange = LC32NativeNSRangeType(unqualifiedType);
            free(returnType);
        }
    }

    auto floatingArgument = [&](size_t index) {
        double value;
        memcpy(&value, &floatingArguments[index], sizeof(value));
        return value;
    };

    auto invokeScalar = [&](void *function, u64 target) -> u64 {
        LC32SetDoubleRegisters(
            floatingArgument(0), floatingArgument(1),
            floatingArgument(2), floatingArgument(3),
            floatingArgument(4), floatingArgument(5),
            floatingArgument(6), floatingArgument(7));
        LC32GuestHostCallQuiescence quiescence;
        double floatingResult;
        switch(returnKind) {
            case HostReturnKind::Float:
                floatingResult = ((objc_msgSendFloatFunc)function)(target,
                    host_cmd, integerArguments[0], integerArguments[1],
                    integerArguments[2], integerArguments[3],
                    integerArguments[4], integerArguments[5],
                    integerArguments[6], integerArguments[7],
                    integerArguments[8]);
                break;
            case HostReturnKind::Double:
                floatingResult = ((objc_msgSendDoubleFunc)function)(target,
                    host_cmd, integerArguments[0], integerArguments[1],
                    integerArguments[2], integerArguments[3],
                    integerArguments[4], integerArguments[5],
                    integerArguments[6], integerArguments[7],
                    integerArguments[8]);
                break;
            case HostReturnKind::Integer: {
                const u64 result =
                    ((objc_msgSendFunc)function)(target, host_cmd,
                    integerArguments[0], integerArguments[1],
                    integerArguments[2], integerArguments[3],
                    integerArguments[4], integerArguments[5],
                    integerArguments[6], integerArguments[7],
                    integerArguments[8]);
                quiescence.finish();
                return result;
            }
        }
        quiescence.finish();
        u64 resultBits;
        memcpy(&resultBits, &floatingResult, sizeof(resultBits));
        return resultBits;
    };

    auto invokeStruct = [&](void *function, u64 target) {
        LC32SetDoubleRegisters(
            floatingArgument(0), floatingArgument(1),
            floatingArgument(2), floatingArgument(3),
            floatingArgument(4), floatingArgument(5),
            floatingArgument(6), floatingArgument(7));
        if(returnsNSRange) {
            if(structLen != sizeof(LC32_TwoU64)) {
                printf("LC32: invalid NSRange return size %u for selector %s\n",
                       structLen, sel_getName(selector));
                return;
            }
            LC32GuestHostCallQuiescence quiescence;
            const LC32_TwoU64 result =
                ((objc_msgSendTwoU64Func)function)(target,
                    host_cmd, integerArguments[0], integerArguments[1],
                    integerArguments[2], integerArguments[3],
                    integerArguments[4], integerArguments[5],
                    integerArguments[6], integerArguments[7],
                    integerArguments[8]);
            quiescence.finish();
            (void)Dynarmic_mem_1write(structPtr, sizeof(result),
                (char *)&result);
            return;
        }
        switch(structLen) {
            case sizeof(LC32_TwoDoubles): {
                LC32GuestHostCallQuiescence quiescence;
                const LC32_TwoDoubles result =
                    ((objc_msgSendTwoDoublesFunc)function)(target,
                        host_cmd, integerArguments[0], integerArguments[1],
                        integerArguments[2], integerArguments[3],
                        integerArguments[4], integerArguments[5],
                        integerArguments[6], integerArguments[7],
                        integerArguments[8]);
                quiescence.finish();
                (void)Dynarmic_mem_1write(structPtr, sizeof(result),
                    (char *)&result);
                break;
            }
            case sizeof(LC32_FourDoubles): {
                LC32GuestHostCallQuiescence quiescence;
                const LC32_FourDoubles result =
                    ((objc_msgSendFourDoublesFunc)function)(target,
                        host_cmd, integerArguments[0], integerArguments[1],
                        integerArguments[2], integerArguments[3],
                        integerArguments[4], integerArguments[5],
                        integerArguments[6], integerArguments[7],
                        integerArguments[8]);
                quiescence.finish();
                (void)Dynarmic_mem_1write(structPtr, sizeof(result),
                    (char *)&result);
                break;
            }
            case sizeof(LC32_SixDoubles): {
                LC32GuestHostCallQuiescence quiescence;
                const LC32_SixDoubles result =
                    ((objc_msgSendSixDoublesFunc)function)(target,
                        host_cmd, integerArguments[0], integerArguments[1],
                        integerArguments[2], integerArguments[3],
                        integerArguments[4], integerArguments[5],
                        integerArguments[6], integerArguments[7],
                        integerArguments[8]);
                quiescence.finish();
                (void)Dynarmic_mem_1write(structPtr, sizeof(result),
                    (char *)&result);
                break;
            }
            default:
                printf("LC32: unsupported host struct return size %u "
                       "for selector %s\n", structLen,
                       sel_getName(selector));
                break;
        }
    };

    auto finishScalarResult = [&](u64 result) -> u64 {
        result = finishIndirectArguments(result);
        if(!returnGuestObject || !result) return result;

        /*
         * Convert the native +0 result while it is still protected by the
         * caller's autorelease-return convention.  -guest_self pins the
         * proxy to the native object's lifetime; any later guest retain adds
         * its own paired native ownership through the retain shim.
         */
        id objectResult = (id)result;
        if(returnsBlock) {
            /*
             * A mapped native block already owns a copied guest block. Its
             * caller uses _Block_copy/_Block_release, not NSObject's logical
             * retain/release pair, so return that mapping unchanged.
             */
            const u32 guestBlock = [objectResult guest_selfOrNull];
            if(!guestBlock) {
                fprintf(stderr,
                    "LC32: cannot bridge host-created block result from %s\n",
                    sel_getName(selector));
            }
            return guestBlock;
        }
        return LC32GuestObjectForBorrowedHostResult(objectResult);
    };

    // If we're calling from guest within a guest subclass, call super
    if(invokeSuper) {
        struct objc_super superInfo = {
            (id)host_self,
            dispatchClass
        };
        if(structPtr) {
            invokeStruct((void *)objc_msgSendSuper, (u64)&superInfo);
            return finishIndirectArguments(0);
        } else {
            return finishScalarResult(
                invokeScalar((void *)objc_msgSendSuper,
                             (u64)&superInfo));
        }
    } else {
        if(structPtr) {
            invokeStruct((void *)objc_msgSend, host_self);
            return finishIndirectArguments(0);
        } else {
            return finishScalarResult(
                invokeScalar((void *)objc_msgSend, host_self));
        }
    }
}

void LC32SetInvokeGuestFuncPtr(u32 dlsymFunc, u32 invokeFunc) {
    sharedHandle.guest_dlsym = dlsymFunc;
    sharedHandle.guest_LC32InvokeGuestC = invokeFunc;
}

#pragma mark Host -> Guest functions

static u32 LC32CachedGuestSymbol(std::atomic<u32> &cache,
                                 const char *name) {
    u32 value = cache.load(std::memory_order_acquire);
    if(value) return value;
    const u32 resolved = guest_dlsym(name);
    if(!resolved) return 0;
    if(cache.compare_exchange_strong(value, resolved,
            std::memory_order_release, std::memory_order_acquire))
        return resolved;
    return value;
}

static u32 LC32CachedGuestSelector(std::atomic<u32> &cache,
                                   const char *name) {
    u32 value = cache.load(std::memory_order_acquire);
    if(value) return value;
    const u32 resolved = guest_sel_registerName(name);
    if(!resolved) return 0;
    if(cache.compare_exchange_strong(value, resolved,
            std::memory_order_release, std::memory_order_acquire))
        return resolved;
    return value;
}

u64 LC32InvokeGuestC(u32 pc, bool ret64, int argc, u32 *args) {
    if(threadHandle.jit == nullptr || threadHandle.cb == nullptr) {
        fprintf(stderr,
            "LC32: refusing guest callback on an unregistered host thread "
            "(pc=0x%x)\n", pc);
        return 0;
    }
    std::array<std::uint32_t, 16> &regs = threadHandle.jit->Regs();
    struct context32 ctx;
    Dynarmic_context_1save(&ctx);

    // TODO: optimize this
    // first 4 arguments go to r0-r3
    for(int i = 0; i < MIN(argc, 4); i++) {
        regs[i] = args[i];
    }
    // Subsequent arguments go to the stack. Keep the AAPCS32 public-call
    // boundary eight-byte aligned while leaving args[4] at [sp].
    const int stackArgumentCount = argc > 4 ? argc - 4 : 0;
    if(stackArgumentCount & 1) {
        regs[Reg::SP] -= sizeof(u32);
        Dynarmic_current_user_callbacks()->MemoryWrite32(regs[Reg::SP], 0);
    }
    for(int i = argc-1; i >= 4; i--) {
        Dynarmic_current_user_callbacks()->MemoryWrite32(regs[Reg::SP] -= sizeof(u32), args[i]);
    }
    regs[12] = pc;
    Dynarmic::HaltReason reason =
        Dynarmic_emu_1start(sharedHandle.guest_LC32InvokeGuestC);
    bool callbackSteppedOut = false;
    bool debuggerSessionEnded = false;
    bool debuggerTargetExited = false;
    if(!Dynarmic::Has(reason, LC32HaltReasonRetFromGuest) &&
            !Dynarmic::Has(reason, LC32HaltReasonExit) &&
            LC32DebuggerActive() &&
            Dynarmic_debugger_begin_main_callback_stop(reason)) {
        /*
         * The outer gdbstub target callback is below UIApplicationMain on
         * this same host stack, so it cannot publish this stop itself.  Pump
         * the existing reader/packet queue re-entrantly while preserving the
         * callback register file and native call stack.
         */
        const gdbstub_run_reason_t nestedReason =
            gdbstub_run_nested_stop(
                &sharedHandle.gdbstub,
                (void *)&sharedHandle);
        callbackSteppedOut =
            nestedReason ==
                GDBSTUB_RUN_REASON_CALLBACK_STEPPED_OUT;
        if(nestedReason ==
                GDBSTUB_RUN_REASON_CALLBACK_RETURNED ||
                callbackSteppedOut) {
            reason = LC32HaltReasonRetFromGuest;
        } else if(nestedReason ==
                GDBSTUB_RUN_REASON_TARGET_EXITED) {
            reason = LC32HaltReasonExit;
            debuggerTargetExited = true;
        } else {
            /*
             * D, EOF, and protocol failure all abandon this stopped session.
             * Restore physical BKPTs before releasing all-stop, then finish
             * the preserved callback through its real guest return boundary.
             */
            if(!Dynarmic_debugger_remove_all_breakpoints()) {
                fprintf(stderr,
                    "LC32: cannot leave nested debugger stop: "
                    "one or more guest breakpoints could not be restored\n");
                fflush(stderr);
                abort();
            }
            Dynarmic_emu_1set_1debugger_1enabled(false);
            reason = Dynarmic_emu_1resume();
            if(!Dynarmic::Has(
                    reason, LC32HaltReasonRetFromGuest) &&
                    !Dynarmic::Has(
                        reason, LC32HaltReasonExit)) {
                fprintf(stderr,
                    "LC32: detached guest callback could not unwind: "
                    "entry=0x%08x reason=0x%08x pc=0x%08x\n",
                    pc, static_cast<unsigned>(reason),
                    regs[Reg::PC]);
                fflush(stderr);
                abort();
            }
            debuggerSessionEnded = true;
        }
        Dynarmic_debugger_end_main_callback_stop();
    }
    if(!Dynarmic::Has(reason, LC32HaltReasonRetFromGuest) &&
            !Dynarmic::Has(reason, LC32HaltReasonExit)) {
        fprintf(stderr,
            "LC32: guest callback stopped unexpectedly: entry=0x%08x "
            "reason=0x%08x pc=0x%08x lr=0x%08x sp=0x%08x "
            "cpsr=0x%08x\n",
            pc, static_cast<unsigned>(reason),
            regs[Reg::PC], regs[Reg::LR], regs[Reg::SP],
            threadHandle.jit->Cpsr());
        fflush(stderr);
    }
    /* An inferior exit has no callback return value.  Restore the saved
     * register owner only to unwind the native bridge stack; never sample
     * the partially terminated callback's r0/r1 as a fabricated result. */
    u64 result = 0;
    if(!debuggerTargetExited) {
        result = (u64)regs[0];
        if(ret64) result |= (u64)regs[1] << 32;
    }

    Dynarmic_context_1restore(&ctx);
    if(callbackSteppedOut && LC32DebuggerActive()) {
        /* The single-step crossed the callback's private return sentinel.
         * Stop only after exposing the restored outer guest context; the
         * suspended outer protocol frame will publish that stop reply. */
        Dynarmic_debugger_request_main_callback_step_out();
    }
    if(debuggerSessionEnded || debuggerTargetExited) {
        /* Wake the enclosing host run loop and plant a private outer-JIT
         * boundary so the original protocol frame can consume the nested
         * terminal marker without creating another socket reader. */
        Dynarmic_debugger_request_main_session_unwind();
    }
    return result;
}

u32 LC32HostToGuestArgument(char *type, u64 value) {
    while(*type && strchr("rnNoORVA", *type)) type++;
    switch(*type) {
        case 'B': // bool
        case 'I':
        case 'Q':
        case 'c':
        case 'i':
        case 'q':
            return (u32)value;
        case 'd':
            return (float)(CGFloat)value;
        case '@': // id
        case '#': // Class
            return [(id)value guest_self];
        case ':': { // SEL
            SEL selector = (SEL)value;
            return selector
                ? guest_sel_registerName(sel_getName(selector))
                : 0;
        }
        case '^':
            /*
             * Legacy Cocoa callbacks use void * as an opaque context token.
             * Guest shims pass those tokens to the host zero-extended, so
             * values which still fit in 32 bits can safely make the return
             * trip without exposing or dereferencing host memory. Reject a
             * real ARM64 pointer instead of silently truncating it.
             */
            if(type[1] == 'v' && value == (u64)(u32)value) {
                return (u32)value;
            }
            /*
             * NSZone is an obsolete allocator hint.  A native zone pointer
             * cannot be exposed to the 32-bit address space, and Cocoa
             * treats a null zone as the default zone.  This is used by
             * copyWithZone: while native collections copy guest-backed
             * objects.
             */
            if(!strncmp(type, "^{_NSZone=",
                        sizeof("^{_NSZone=") - 1) ||
               !strncmp(type, "^{NSZone=",
                        sizeof("^{NSZone=") - 1)) {
                return 0;
            }
            [[fallthrough]];
        default:
            printf("LC32HostToGuestArgument: unhandled type %s\n", type);
            abort();
    }
}

static float LC32GuestFloatReturn(u64 value) {
    const u32 bits = (u32)value;
    float result;
    memcpy(&result, &bits, sizeof(result));
    return result;
}

static double LC32GuestDoubleReturn(u64 value) {
    double result;
    memcpy(&result, &value, sizeof(result));
    return result;
}

u64 LC32GuestToHostReturnType(char *type, u64 value) {
    while(*type && strchr("rnNoORVA", *type)) type++;
    switch(*type) {
        case 'B': // bool
        case 'C':
        case 'I':
        case 'L':
        case 'S':
        case 'b':
        case 'c':
        case 'i':
        case 'l':
        case 's':
            return (u64)(u32)value;
        case 'Q':
        case 'q':
            return value;
        case 'v':
            return 0;
        case 'f': {
            const double hostValue = LC32GuestFloatReturn(value);
            u64 result;
            memcpy(&result, &hostValue, sizeof(result));
            return result;
        }
        case 'd': {
            const double hostValue = LC32GuestDoubleReturn(value);
            u64 result;
            memcpy(&result, &hostValue, sizeof(result));
            return result;
        }
        case '@': // id
        case '#': {// Class
            // don't call LC32GetHostObject here! the guest stores host pointer
            static std::atomic<u32> guestPtr{0};
            const u32 selector = LC32CachedGuestSelector(
                guestPtr, "host_self");
            u32 args[] = {(u32)value, selector};
            return guest_objc_msgSend(sizeof(args)/sizeof(*args), args);
        }
        default:
            printf("LC32GuestToHostReturnType: unhandled type %s\n", type);
            abort();
    }
}

static u64 LC32InvokeGuestSelectorWordsRaw(id self, SEL _cmd,
                                           const u32 *argumentWords,
                                           size_t argumentWordCount) {
    assert(argumentWordCount <= 18);

    u32 guest_args[20];
    size_t guest_argc = 0;
    guest_args[guest_argc++] = (u32)(u64)[self guest_self];
    guest_args[guest_argc++] = guest_sel_registerName(sel_getName(_cmd));
    for(size_t index = 0; index < argumentWordCount; index++) {
        guest_args[guest_argc++] = argumentWords[index];
    }

    return guest_objc_msgSend((int)guest_argc, guest_args);
}

static u64 LC32InvokeGuestSelectorWords(id self, SEL _cmd,
                                        const u32 *argumentWords,
                                        size_t argumentWordCount) {
    const u64 guest_result = LC32InvokeGuestSelectorWordsRaw(
        self, _cmd, argumentWords, argumentWordCount);
    Method method = object_isClass(self)
        ? class_getClassMethod(self, _cmd)
        : class_getInstanceMethod((Class)[self class], _cmd);
    char *returnType = method_copyReturnType(method);
    const u64 host_result = LC32GuestToHostReturnType(returnType, guest_result);
    free(returnType);
    return host_result;
}

static u32 LC32GuestMalloc(u32 size) {
    static std::atomic<u32> cache{0};
    const u32 guestMalloc = LC32CachedGuestSymbol(cache, "malloc");
    if(!guestMalloc) return 0;
    u32 args[] = {size};
    return (u32)LC32InvokeGuestC(
        guestMalloc, false, sizeof(args) / sizeof(*args), args);
}

/*
 * NSFastEnumerationState is eight pointer-sized words on both platforms, but
 * those words are 32 bits in the ARM guest and 64 bits in the host.  A native
 * collection can therefore call a dynamically mirrored guest implementation
 * only after both the state and its object buffer have been staged in guest
 * memory.
 *
 * Keep the exact guest state in the host state's opaque extra[] storage.  A
 * fresh guest allocation is used for each synchronous batch, avoiding a guest
 * allocation leak when a native caller leaves a for-in loop early.  Batches
 * are deliberately limited to one object: the guest mutation word can then
 * be checked between every object even though its address is not meaningful
 * to the host runtime.
 */
struct LC32GuestFastEnumerationState32 {
    u32 state;
    u32 itemsPtr;
    u32 mutationsPtr;
    u32 extra[5];
};

struct LC32StoredFastEnumerationState {
    LC32GuestFastEnumerationState32 guest;
    u32 previousGuestBuffer;
    u32 mutationValue;
};

static_assert(sizeof(LC32GuestFastEnumerationState32) == 32);
static_assert(sizeof(LC32StoredFastEnumerationState) ==
              sizeof(((NSFastEnumerationState *)nullptr)->extra));

static NSUInteger LC32InvokeGuestSelectorFastEnumeration(
        id self, SEL _cmd, NSFastEnumerationState *hostState,
        id __unsafe_unretained hostObjects[], NSUInteger hostCount) {
    if(!hostState || !hostObjects || hostCount == 0) return 0;

    LC32StoredFastEnumerationState stored = {};
    const bool continuing = hostState->state != 0;
    if(continuing) {
        memcpy(&stored, hostState->extra, sizeof(stored));
        if(stored.guest.mutationsPtr) {
            u32 currentMutation = 0;
            bool mutationRead = false;
            const u32 previousGuestState =
                stored.previousGuestBuffer >=
                        sizeof(LC32GuestFastEnumerationState32)
                    ? stored.previousGuestBuffer -
                        sizeof(LC32GuestFastEnumerationState32)
                    : 0;
            if(previousGuestState &&
                    stored.guest.mutationsPtr >= previousGuestState &&
                    stored.guest.mutationsPtr <=
                        previousGuestState + sizeof(stored.guest) -
                            sizeof(currentMutation)) {
                const u32 offset =
                    stored.guest.mutationsPtr - previousGuestState;
                memcpy(&currentMutation,
                    reinterpret_cast<const char *>(&stored.guest) + offset,
                    sizeof(currentMutation));
                mutationRead = true;
            } else {
                mutationRead = Dynarmic_mem_1read(
                    stored.guest.mutationsPtr, sizeof(currentMutation),
                    reinterpret_cast<char *>(&currentMutation)) == 0;
            }
            if(!mutationRead) {
                fprintf(stderr,
                    "LC32: cannot read guest mutation state for selector "
                    "%s at 0x%08x\n",
                    sel_getName(_cmd), stored.guest.mutationsPtr);
                abort();
            }
            if(currentMutation != stored.mutationValue) {
                objc_enumerationMutation(self);
            }
        }
    }

    constexpr u32 guestObjectBytes = sizeof(u32);
    constexpr u32 guestAllocationBytes =
        sizeof(LC32GuestFastEnumerationState32) + guestObjectBytes;
    const u32 guestAllocation = LC32GuestMalloc(guestAllocationBytes);
    if(!guestAllocation) {
        fprintf(stderr,
            "LC32: could not allocate guest fast-enumeration staging for "
            "selector %s\n", sel_getName(_cmd));
        abort();
    }
    const u32 guestBuffer =
        guestAllocation + sizeof(LC32GuestFastEnumerationState32);

    /* Rebase pointers which the implementation retained into the preceding
     * caller-owned staging block. Pointers into the collection's own storage
     * are preserved unchanged. */
    if(continuing && stored.previousGuestBuffer >=
            sizeof(LC32GuestFastEnumerationState32)) {
        const u32 previousGuestAllocation =
            stored.previousGuestBuffer -
                sizeof(LC32GuestFastEnumerationState32);
        const u32 previousGuestAllocationEnd =
            previousGuestAllocation + guestAllocationBytes;
        auto rebaseStagingPointer = [&](u32 pointer) -> u32 {
            if(pointer < previousGuestAllocation ||
                    pointer >= previousGuestAllocationEnd) {
                return pointer;
            }
            return guestAllocation +
                (pointer - previousGuestAllocation);
        };
        stored.guest.itemsPtr =
            rebaseStagingPointer(stored.guest.itemsPtr);
        stored.guest.mutationsPtr =
            rebaseStagingPointer(stored.guest.mutationsPtr);
    }

    u32 zero = 0;
    bool stagingWritten = Dynarmic_mem_1write(
        guestAllocation, sizeof(stored.guest),
        reinterpret_cast<char *>(&stored.guest)) == 0;
    stagingWritten = stagingWritten && Dynarmic_mem_1write(
        guestBuffer, sizeof(zero), reinterpret_cast<char *>(&zero)) == 0;
    if(!stagingWritten) {
        guest_free(guestAllocation);
        fprintf(stderr,
            "LC32: could not initialize guest fast-enumeration staging for "
            "selector %s\n", sel_getName(_cmd));
        abort();
    }

    const u32 words[] = {guestAllocation, guestBuffer, 1};
    const u32 result = (u32)LC32InvokeGuestSelectorWordsRaw(
        self, _cmd, words, sizeof(words) / sizeof(*words));

    LC32GuestFastEnumerationState32 updatedGuestState = {};
    bool stateRead = Dynarmic_mem_1read(
        guestAllocation, sizeof(updatedGuestState),
        reinterpret_cast<char *>(&updatedGuestState)) == 0;
    u32 guestObject = 0;
    if(stateRead && result != 0 && updatedGuestState.itemsPtr != 0) {
        stateRead = Dynarmic_mem_1read(
            updatedGuestState.itemsPtr, sizeof(guestObject),
            reinterpret_cast<char *>(&guestObject)) == 0;
    }

    u32 updatedMutation = stored.mutationValue;
    if(stateRead && updatedGuestState.mutationsPtr != 0) {
        stateRead = Dynarmic_mem_1read(
            updatedGuestState.mutationsPtr, sizeof(updatedMutation),
            reinterpret_cast<char *>(&updatedMutation)) == 0;
    }
    const bool mutationChanged = stateRead && continuing &&
        updatedGuestState.mutationsPtr != 0 &&
        updatedMutation != stored.mutationValue;
    guest_free(guestAllocation);

    if(!stateRead || result > 1 || (result != 0 && guestObject == 0)) {
        fprintf(stderr,
            "LC32: invalid guest fast-enumeration result for selector %s "
            "(count=%u, items=0x%08x, mutation=0x%08x)\n",
            sel_getName(_cmd), result, updatedGuestState.itemsPtr,
            updatedGuestState.mutationsPtr);
        abort();
    }
    if(mutationChanged) objc_enumerationMutation(self);

    stored.guest = updatedGuestState;
    stored.previousGuestBuffer = guestBuffer;
    stored.mutationValue = updatedMutation;
    memcpy(hostState->extra, &stored, sizeof(stored));

    static unsigned long stableHostMutationSentinel = 0;
    hostState->state = updatedGuestState.state
        ? (NSUInteger)updatedGuestState.state : (NSUInteger)1;
    hostState->itemsPtr = hostObjects;
    hostState->mutationsPtr = &stableHostMutationSentinel;

    if(result != 0) {
        hostObjects[0] = (id)LC32GuestToHostReturnType(
            const_cast<char *>("@"), guestObject);
    }
    return result;
}

static bool LC32FastEnumerationSignatureMatches(const char *types) {
    if(!types) return false;
    NSMethodSignature *signature =
        [NSMethodSignature signatureWithObjCTypes:types];
    if(!signature || signature.numberOfArguments != 5) return false;

    auto unqualified = [](const char *type) -> const char * {
        while(type && *type && strchr("rnNoORVA", *type)) type++;
        return type;
    };
    const char *returnType = unqualified(signature.methodReturnType);
    const char *stateType = unqualified(
        [signature getArgumentTypeAtIndex:2]);
    const char *objectsType = unqualified(
        [signature getArgumentTypeAtIndex:3]);
    const char *countType = unqualified(
        [signature getArgumentTypeAtIndex:4]);
    return returnType && strchr("ILQ", returnType[0]) &&
        stateType && stateType[0] == '^' && stateType[1] == '{' &&
        objectsType && objectsType[0] == '^' && objectsType[1] == '@' &&
        countType && strchr("ILQ", countType[0]);
}

static bool LC32RangeTypeHasFields(const char *type, char fieldType) {
    while(type && *type && strchr("rnNoORVA", *type)) type++;
    if(!type ||
       (strncmp(type, "{_NSRange=", sizeof("{_NSRange=") - 1) &&
        strncmp(type, "{NSRange=", sizeof("{NSRange=") - 1))) {
        return false;
    }
    const char *fields = strchr(type, '=');
    return fields && fields[1] == fieldType && fields[2] == fieldType &&
        fields[3] == '}' && fields[4] == '\0';
}

static bool LC32UniCharRangeSignatureMatches(const char *types,
                                             char rangeFieldType) {
    if(!types) return false;
    NSMethodSignature *signature =
        [NSMethodSignature signatureWithObjCTypes:types];
    const char *returnType = signature.methodReturnType;
    while(returnType && *returnType && strchr("rnNoORVA", *returnType))
        returnType++;
    const char *charactersType = signature.numberOfArguments > 2
        ? [signature getArgumentTypeAtIndex:2] : nullptr;
    while(charactersType && *charactersType &&
          strchr("rnNoORVA", *charactersType)) charactersType++;
    if(!signature || signature.numberOfArguments != 4 ||
       !returnType || strcmp(returnType, "v") ||
       !charactersType || strcmp(charactersType, "^S")) {
        return false;
    }
    return LC32RangeTypeHasFields(
        [signature getArgumentTypeAtIndex:3], rangeFieldType);
}

static bool LC32ObjectRangeSignatureMatches(const char *types,
                                            char rangeFieldType) {
    if(!types) return false;
    NSMethodSignature *signature =
        [NSMethodSignature signatureWithObjCTypes:types];
    if(!signature || signature.numberOfArguments != 4) return false;

    auto unqualified = [](const char *type) -> const char * {
        while(type && *type && strchr("rnNoORVA", *type)) type++;
        return type;
    };
    const char *returnType = unqualified(signature.methodReturnType);
    const char *objectsType = unqualified(
        [signature getArgumentTypeAtIndex:2]);
    return returnType && !strcmp(returnType, "v") &&
        objectsType && !strcmp(objectsType, "^@") &&
        LC32RangeTypeHasFields(
            [signature getArgumentTypeAtIndex:3], rangeFieldType);
}

/*
 * NSArray's primitive -getObjects:range: writes native object pointers into
 * caller-owned ARM64 storage.  A mirrored guest collection instead expects
 * an array of 32-bit guest object addresses.  Stage that array synchronously
 * in guest memory, then convert each borrowed element back into the native
 * caller's unsafe-unretained output buffer.
 */
static void LC32InvokeGuestSelectorObjectRange(
        id self, SEL _cmd, id __unsafe_unretained hostObjects[],
        NSRange range) {
    constexpr NSUInteger kMaximumObjectBridgeBytes =
        64u * 1024u * 1024u;
    if(range.location > UINT32_MAX ||
       range.length > UINT32_MAX / sizeof(u32) ||
       range.location > UINT32_MAX - range.length ||
       range.length * sizeof(u32) > kMaximumObjectBridgeBytes ||
       (range.length && !hostObjects)) {
        fprintf(stderr,
            "LC32: invalid host object range for selector %s "
            "(location=%llu, length=%llu, output=%p)\n",
            sel_getName(_cmd), (unsigned long long)range.location,
            (unsigned long long)range.length, hostObjects);
        abort();
    }

    const u32 objectCount = (u32)range.length;
    const u32 byteCount = objectCount * sizeof(u32);
    /* Preserve non-null pointer identity for valid zero-length ranges. Some
     * guest collection primitives validate pointer/range consistency even
     * though they do not dereference the output in that case. */
    const u32 allocationBytes = byteCount
        ? byteCount : (hostObjects ? (u32)sizeof(u32) : 0);
    const u32 guestObjects = allocationBytes
        ? LC32GuestMalloc(allocationBytes) : 0;
    if(allocationBytes && !guestObjects) {
        fprintf(stderr,
            "LC32: could not allocate %u guest object bytes for selector "
            "%s\n", allocationBytes, sel_getName(_cmd));
        abort();
    }
    if(allocationBytes) {
        std::vector<char> emptyObjects(allocationBytes, 0);
        if(Dynarmic_mem_1write(guestObjects, allocationBytes,
                reinterpret_cast<char *>(emptyObjects.data())) != 0) {
            guest_free(guestObjects);
            fprintf(stderr,
                "LC32: could not initialize guest object output for "
                "selector %s\n", sel_getName(_cmd));
            abort();
        }
    }

    const u32 words[] = {
        guestObjects,
        (u32)range.location,
        objectCount,
    };
    (void)LC32InvokeGuestSelectorWordsRaw(
        self, _cmd, words, sizeof(words) / sizeof(*words));

    std::vector<u32> guestResults(objectCount, 0);
    const bool copied = !byteCount || Dynarmic_mem_1read(
        guestObjects, byteCount,
        reinterpret_cast<char *>(guestResults.data())) == 0;
    if(guestObjects) guest_free(guestObjects);
    if(!copied) {
        fprintf(stderr,
            "LC32: could not copy guest object output for selector %s\n",
            sel_getName(_cmd));
        abort();
    }

    for(u32 index = 0; index < objectCount; index++) {
        const u32 guestObject = guestResults[index];
        if(!guestObject) {
            fprintf(stderr,
                "LC32: guest selector %s returned a null object at index "
                "%u\n", sel_getName(_cmd), index);
            abort();
        }
        id hostObject = (id)LC32GuestToHostReturnType(
            const_cast<char *>("@"), guestObject);
        if(!hostObject) {
            fprintf(stderr,
                "LC32: could not convert guest object 0x%08x from selector "
                "%s\n", guestObject, sel_getName(_cmd));
            abort();
        }
        hostObjects[index] = hostObject;
    }
}

/*
 * NSString subclasses implement this primitive in the guest, but native
 * Foundation supplies an ARM64 UniChar output buffer.  Stage that buffer in
 * guest-addressable storage for the synchronous callback, then copy the
 * result back before returning to Foundation.
 */
static void LC32InvokeGuestSelectorUniCharRange(
        id self, SEL _cmd, UniChar *hostCharacters, NSRange range) {
    constexpr NSUInteger kMaximumUniCharBridgeBytes =
        64u * 1024u * 1024u;
    if(range.location > UINT32_MAX ||
       range.length > UINT32_MAX / sizeof(UniChar) ||
       range.location > UINT32_MAX - range.length ||
       range.length * sizeof(UniChar) > kMaximumUniCharBridgeBytes ||
       (range.length && !hostCharacters)) {
        fprintf(stderr,
            "LC32: invalid host UniChar range for selector %s "
            "(location=%llu, length=%llu, output=%p)\n",
            sel_getName(_cmd), (unsigned long long)range.location,
            (unsigned long long)range.length, hostCharacters);
        abort();
    }

    const u32 byteCount = (u32)range.length * sizeof(UniChar);
    const u32 guestCharacters = byteCount ? LC32GuestMalloc(byteCount) : 0;
    if(byteCount && !guestCharacters) {
        fprintf(stderr,
            "LC32: could not allocate %u guest bytes for selector %s\n",
            byteCount, sel_getName(_cmd));
        abort();
    }
    if(byteCount) {
        std::vector<char> poison(byteCount, static_cast<char>(0xa5));
        if(Dynarmic_mem_1write(guestCharacters, byteCount,
                poison.data()) != 0) {
            guest_free(guestCharacters);
            fprintf(stderr,
                "LC32: could not initialize guest UniChar output for "
                "selector %s\n", sel_getName(_cmd));
            abort();
        }
    }

    const u32 words[] = {
        guestCharacters,
        (u32)range.location,
        (u32)range.length,
    };
    (void)LC32InvokeGuestSelectorWordsRaw(
        self, _cmd, words, sizeof(words) / sizeof(*words));

    const bool copied = !byteCount || Dynarmic_mem_1read(
        guestCharacters, byteCount,
        reinterpret_cast<char *>(hostCharacters)) == 0;
    if(guestCharacters) guest_free(guestCharacters);
    if(!copied) {
        fprintf(stderr,
            "LC32: could not copy guest UniChar output for selector %s\n",
            sel_getName(_cmd));
        abort();
    }
}

static u32 LC32GuestFloatWord(CGFloat value) {
    const float guestValue = (float)value;
    u32 word;
    memcpy(&word, &guestValue, sizeof(word));
    return word;
}

static bool LC32CGSizeTypeHasFields(const char *type, char fieldType) {
    while(type && *type && strchr("rnNoORVA", *type)) type++;
    if(!type ||
       (strncmp(type, "{CGSize=", sizeof("{CGSize=") - 1) &&
        strncmp(type, "{_CGSize=", sizeof("{_CGSize=") - 1))) {
        return false;
    }
    const char *fields = strchr(type, '=');
    return fields && fields[1] == fieldType && fields[2] == fieldType &&
        fields[3] == '}' && fields[4] == '\0';
}

static bool LC32CGPointTypeHasFields(const char *type, char fieldType) {
    while(type && *type && strchr("rnNoORVA", *type)) type++;
    if(!type ||
       (strncmp(type, "{CGPoint=", sizeof("{CGPoint=") - 1) &&
        strncmp(type, "{_CGPoint=", sizeof("{_CGPoint=") - 1))) {
        return false;
    }
    const char *fields = strchr(type, '=');
    return fields && fields[1] == fieldType && fields[2] == fieldType &&
        fields[3] == '}' && fields[4] == '\0';
}

static bool LC32PointObjectSignatureMatches(const char *types,
                                            char pointFieldType) {
    /*
     * NSMethodSignature in current Foundation rejects a few legacy Objective-C
     * encodings (notably anonymous unions such as "(?=...)").  This matcher is
     * consulted for every guest method, so only ask Foundation to parse methods
     * which can actually contain the CGPoint argument we are looking for.
     */
    if(!types ||
       (!strstr(types, "{CGPoint=") && !strstr(types, "{_CGPoint="))) {
        return false;
    }
    NSMethodSignature *signature =
        [NSMethodSignature signatureWithObjCTypes:types];
    if(!signature || signature.numberOfArguments != 4 ||
       !LC32CGPointTypeHasFields(
           [signature getArgumentTypeAtIndex:2], pointFieldType)) {
        return false;
    }
    const char *objectType = [signature getArgumentTypeAtIndex:3];
    while(objectType && *objectType && strchr("rnNoORVA", *objectType)) {
        objectType++;
    }
    const char *returnType = signature.methodReturnType;
    while(returnType && *returnType && strchr("rnNoORVA", *returnType)) {
        returnType++;
    }
    return objectType && objectType[0] == '@' && objectType[1] != '?' &&
        returnType && strchr("vBCILQSbcilqs@#", returnType[0]);
}

static bool LC32CGSizeToCGSizeSignatureMatches(const char *types,
                                               char fieldType) {
    if(!types) return false;
    const char *returnType = types;
    while(*returnType && strchr("rnNoORVA", *returnType)) returnType++;
    const char *fields = strchr(returnType, '=');
    if((strncmp(returnType, "{CGSize=", sizeof("{CGSize=") - 1) &&
        strncmp(returnType, "{_CGSize=", sizeof("{_CGSize=") - 1)) ||
       !fields || fields[1] != fieldType || fields[2] != fieldType ||
       fields[3] != '}') {
        return false;
    }
    NSMethodSignature *signature =
        [NSMethodSignature signatureWithObjCTypes:types];
    return signature && signature.numberOfArguments == 3 &&
        LC32CGSizeTypeHasFields(signature.methodReturnType, fieldType) &&
        LC32CGSizeTypeHasFields(
            [signature getArgumentTypeAtIndex:2], fieldType);
}

static bool LC32CGRectTypeHasFields(const char *type, char fieldType) {
    while(type && *type && strchr("rnNoORVA", *type)) type++;
    if(!type ||
       (strncmp(type, "{CGRect=", sizeof("{CGRect=") - 1) &&
        strncmp(type, "{_CGRect=", sizeof("{_CGRect=") - 1))) {
        return false;
    }

    const char *field = strchr(type, '=');
    if(!field) return false;
    field++;
    if(!strncmp(field, "{CGPoint=", sizeof("{CGPoint=") - 1)) {
        field += sizeof("{CGPoint=") - 1;
    } else if(!strncmp(field, "{_CGPoint=", sizeof("{_CGPoint=") - 1)) {
        field += sizeof("{_CGPoint=") - 1;
    } else {
        return false;
    }
    if(field[0] != fieldType || field[1] != fieldType || field[2] != '}')
        return false;
    field += 3;
    if(!strncmp(field, "{CGSize=", sizeof("{CGSize=") - 1)) {
        field += sizeof("{CGSize=") - 1;
    } else if(!strncmp(field, "{_CGSize=", sizeof("{_CGSize=") - 1)) {
        field += sizeof("{_CGSize=") - 1;
    } else {
        return false;
    }
    return field[0] == fieldType && field[1] == fieldType &&
        field[2] == '}' && field[3] == '}' && field[4] == '\0';
}

static bool LC32CGRectToCGRectSignatureMatches(const char *types,
                                               char fieldType) {
    if(!types) return false;
    const char *returnType = types;
    while(*returnType && strchr("rnNoORVA", *returnType)) returnType++;
    if(strncmp(returnType, "{CGRect=", sizeof("{CGRect=") - 1) &&
       strncmp(returnType, "{_CGRect=", sizeof("{_CGRect=") - 1)) {
        return false;
    }
    NSMethodSignature *signature =
        [NSMethodSignature signatureWithObjCTypes:types];
    return signature && signature.numberOfArguments == 3 &&
        LC32CGRectTypeHasFields(signature.methodReturnType, fieldType) &&
        LC32CGRectTypeHasFields(
            [signature getArgumentTypeAtIndex:2], fieldType);
}

static void LC32GuestObjCMsgSendStret(int argc, u32 *args) {
    LC32DrainDeferredGuestPinReleases();
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "objc_msgSend_stret");
    if(!guestPtr) {
        fprintf(stderr, "LC32: guest objc_msgSend_stret is unavailable\n");
        abort();
    }
    (void)LC32InvokeGuestC(guestPtr, false, argc, args);
}

/*
 * CGSize is a two-double HFA in the ARM64 host ABI, so a typed IMP is needed
 * to receive and return it through d0-d1.  In Apple's ARMv7 ABI the same
 * two-float result is indirect: objc_msgSend_stret receives the result buffer
 * in r0, shifting self/cmd to r1/r2, with width in r3 and height on the stack.
 */
static CGSize LC32InvokeGuestSelectorCGSizeToCGSize(
        id self, SEL _cmd, CGSize hostSize) {
    const u32 guestSelf = (u32)(u64)[self guest_self];
    const u32 guestCommand = guest_sel_registerName(sel_getName(_cmd));

    std::array<std::uint32_t, 16> &regs = threadHandle.jit->Regs();
    const u32 originalStackPointer = regs[Reg::SP];
    const u32 guestResult = (originalStackPointer - sizeof(u32[2])) & ~7u;
    regs[Reg::SP] = guestResult;
    Dynarmic_current_user_callbacks()->MemoryWrite32(guestResult, 0);
    Dynarmic_current_user_callbacks()->MemoryWrite32(guestResult + 4, 0);

    u32 args[] = {
        guestResult,
        guestSelf,
        guestCommand,
        LC32GuestFloatWord(hostSize.width),
        LC32GuestFloatWord(hostSize.height),
    };
    LC32GuestObjCMsgSendStret(sizeof(args) / sizeof(*args), args);

    const u32 widthBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(guestResult);
    const u32 heightBits =
        Dynarmic_current_user_callbacks()->MemoryRead32(guestResult + 4);
    regs[Reg::SP] = originalStackPointer;

    float guestWidth;
    float guestHeight;
    memcpy(&guestWidth, &widthBits, sizeof(guestWidth));
    memcpy(&guestHeight, &heightBits, sizeof(guestHeight));
    CGSize result = {};
    result.width = (CGFloat)guestWidth;
    result.height = (CGFloat)guestHeight;
    return result;
}

/*
 * CGRect is likewise returned indirectly by ARMv7 objc_msgSend_stret, while
 * the ARM64 host passes and returns its four-double CGRect as an HFA in
 * d0-d3.  Calling an ARMv7 CGRect-returning IMP through ordinary
 * objc_msgSend shifts self/cmd by one register: the IMP mistakes the selector
 * for self and crashes on its first nested message send.
 */
static CGRect LC32InvokeGuestSelectorCGRectToCGRect(
        id self, SEL _cmd, CGRect hostRect) {
    const u32 guestSelf = (u32)(u64)[self guest_self];
    const u32 guestCommand = guest_sel_registerName(sel_getName(_cmd));

    std::array<std::uint32_t, 16> &regs = threadHandle.jit->Regs();
    const u32 originalStackPointer = regs[Reg::SP];
    const u32 guestResult = (originalStackPointer - sizeof(u32[4])) & ~7u;
    regs[Reg::SP] = guestResult;
    for(u32 offset = 0; offset < sizeof(u32[4]); offset += sizeof(u32)) {
        Dynarmic_current_user_callbacks()->MemoryWrite32(
            guestResult + offset, 0);
    }

    u32 args[] = {
        guestResult,
        guestSelf,
        guestCommand,
        LC32GuestFloatWord(hostRect.origin.x),
        LC32GuestFloatWord(hostRect.origin.y),
        LC32GuestFloatWord(hostRect.size.width),
        LC32GuestFloatWord(hostRect.size.height),
    };
    LC32GuestObjCMsgSendStret(sizeof(args) / sizeof(*args), args);

    float guestFields[4] = {};
    for(u32 index = 0; index < 4; index++) {
        const u32 bits = Dynarmic_current_user_callbacks()->MemoryRead32(
            guestResult + index * sizeof(u32));
        memcpy(&guestFields[index], &bits, sizeof(bits));
    }
    regs[Reg::SP] = originalStackPointer;

    CGRect result = {
        {(CGFloat)guestFields[0], (CGFloat)guestFields[1]},
        {(CGFloat)guestFields[2], (CGFloat)guestFields[3]},
    };
    return result;
}

static u64 LC32InvokeGuestSelectorCGRectRaw(id self, SEL _cmd, CGRect rect) {
    const u32 words[] = {
        LC32GuestFloatWord(rect.origin.x),
        LC32GuestFloatWord(rect.origin.y),
        LC32GuestFloatWord(rect.size.width),
        LC32GuestFloatWord(rect.size.height),
    };
    return LC32InvokeGuestSelectorWordsRaw(
        self, _cmd, words, sizeof(words) / sizeof(*words));
}

// A CGRect is an HFA of four doubles in the arm64 host ABI, but four floats in
// the ARMv7 guest ABI. A typed IMP is required so the host values are captured
// from d0-d3 before they are narrowed and placed in the guest argument words.
static u64 LC32InvokeGuestSelectorCGRect(id self, SEL _cmd, CGRect rect) {
    const u32 words[] = {
        LC32GuestFloatWord(rect.origin.x),
        LC32GuestFloatWord(rect.origin.y),
        LC32GuestFloatWord(rect.size.width),
        LC32GuestFloatWord(rect.size.height),
    };
    return LC32InvokeGuestSelectorWords(
        self, _cmd, words, sizeof(words) / sizeof(*words));
}

/*
 * CGPoint is a two-double HFA in the ARM64 host ABI and arrives in d0-d1;
 * an object following it still arrives independently in x2.  The generic
 * integer-register trampoline therefore cannot observe the point.  Narrow it
 * through a typed IMP, then lay out the ARMv7 call as r2/r3/[sp].
 */
static u64 LC32InvokeGuestSelectorPointObject(
        id self, SEL _cmd, CGPoint point, id object) {
    const u32 words[] = {
        LC32GuestFloatWord(point.x),
        LC32GuestFloatWord(point.y),
        object ? [object guest_self] : 0,
    };
    return LC32InvokeGuestSelectorWords(
        self, _cmd, words, sizeof(words) / sizeof(*words));
}

static float LC32InvokeGuestSelectorCGRectGuestFloatHostFloat(
        id self, SEL _cmd, CGRect rect) {
    return LC32GuestFloatReturn(
        LC32InvokeGuestSelectorCGRectRaw(self, _cmd, rect));
}

static double LC32InvokeGuestSelectorCGRectGuestFloatHostDouble(
        id self, SEL _cmd, CGRect rect) {
    return (double)LC32GuestFloatReturn(
        LC32InvokeGuestSelectorCGRectRaw(self, _cmd, rect));
}

static float LC32InvokeGuestSelectorCGRectGuestDoubleHostFloat(
        id self, SEL _cmd, CGRect rect) {
    return (float)LC32GuestDoubleReturn(
        LC32InvokeGuestSelectorCGRectRaw(self, _cmd, rect));
}

static double LC32InvokeGuestSelectorCGRectGuestDoubleHostDouble(
        id self, SEL _cmd, CGRect rect) {
    return LC32GuestDoubleReturn(
        LC32InvokeGuestSelectorCGRectRaw(self, _cmd, rect));
}

// Keep x2-x7 as explicit parameters, then consume any arguments which the
// arm64 caller placed on the stack through va_list.
static u64 LC32InvokeGuestSelectorRaw(id self, SEL _cmd,
                                     u64 arg2, u64 arg3, u64 arg4,
                                     u64 arg5, u64 arg6, u64 arg7,
                                     va_list *hostStackArguments,
                                     Method *resolvedMethod) {
    LC32TraceGuestMethodCallback(self, _cmd);
    // FIXME: fast path to get guest selector? cache to hash map?
    u32 guest_cmd = guest_sel_registerName(sel_getName(_cmd));
    Method method = object_isClass(self) ? class_getClassMethod(self, _cmd) : class_getInstanceMethod((Class)[self class], _cmd);

    // Objective-C method metadata describes logical arguments, but an arm64
    // NSRange occupies two general-purpose argument slots. Keep an independent
    // raw-slot cursor so following arguments stay aligned.
    const u64 hostRegisterArguments[] = {
        arg2, arg3, arg4, arg5, arg6, arg7
    };
    constexpr size_t hostRegisterArgumentCount =
        sizeof(hostRegisterArguments) / sizeof(*hostRegisterArguments);
    size_t hostArgumentSlot = 0;
    auto nextHostArgument = [&]() -> u64 {
        if(hostArgumentSlot < hostRegisterArgumentCount) {
            return hostRegisterArguments[hostArgumentSlot++];
        }
        hostArgumentSlot++;
        return va_arg(*hostStackArguments, u64);
    };

    size_t guest_argc = 0;
    u32 guest_args[20];
    guest_args[guest_argc++] = (u32)(u64)[self guest_self];
    guest_args[guest_argc++] = guest_cmd;

    int nargs = method_getNumberOfArguments(method);
    // The generic trampoline has six logical host argument positions. Structs
    // may expand those into extra raw GPR slots (and at most one supported
    // stack argument); broader stack/FP signatures need typed trampolines.
    assert(nargs <= 8);
    for(int i = 2; i < nargs; i++) {
        char *argType = method_copyArgumentType(method, i);
        const char *unqualifiedType = argType;
        while(*unqualifiedType && strchr("rnNoORVA", *unqualifiedType)) {
            unqualifiedType++;
        }

        const bool isNSRange =
            !strncmp(unqualifiedType, "{_NSRange=",
                     sizeof("{_NSRange=") - 1) ||
            !strncmp(unqualifiedType, "{NSRange=",
                     sizeof("{NSRange=") - 1);
        if(isNSRange) {
            /*
             * AAPCS64 never splits an aggregate between registers and the
             * stack. If only x7 remains, it is unused and both NSUInteger
             * fields begin on the stack.
             */
            if(hostArgumentSlot < hostRegisterArgumentCount &&
                    hostRegisterArgumentCount - hostArgumentSlot < 2) {
                hostArgumentSlot = hostRegisterArgumentCount;
            }
            assert(guest_argc + 2 <=
                   sizeof(guest_args) / sizeof(*guest_args));
            guest_args[guest_argc++] = (u32)nextHostArgument();
            guest_args[guest_argc++] = (u32)nextHostArgument();
        } else {
            assert(guest_argc < sizeof(guest_args) / sizeof(*guest_args));
            const u64 hostArgument = nextHostArgument();
            if(unqualifiedType[0] == '@' &&
               unqualifiedType[1] != '?') {
                LC32TraceNativeNetworkObject(
                    "host->guest", _cmd, (unsigned int)(i - 2),
                    (id)hostArgument);
            }
            const char *selectorName = sel_getName(_cmd);
            if(unqualifiedType[0] == '^' &&
                    !(unqualifiedType[1] == 'v' &&
                      hostArgument == (u64)(u32)hostArgument) &&
                    strncmp(unqualifiedType, "^{_NSZone=",
                            sizeof("^{_NSZone=") - 1) &&
                    strncmp(unqualifiedType, "^{NSZone=",
                            sizeof("^{NSZone=") - 1)) {
                fprintf(stderr,
                    "LC32: cannot marshal host pointer argument %d "
                    "(%s) for selector %s (value=0x%llx)\n",
                    i - 2, unqualifiedType,
                    selectorName ? selectorName : "<null>",
                    (unsigned long long)hostArgument);
            }
            guest_args[guest_argc++] = LC32HostToGuestArgument(
                argType, hostArgument);
        }
        free(argType);
    }
    if(resolvedMethod) *resolvedMethod = method;
    return guest_objc_msgSend((int)guest_argc, guest_args);
}

u64 LC32InvokeGuestSelector(id self, SEL _cmd, u64 arg2, u64 arg3,
                            u64 arg4, u64 arg5, u64 arg6, u64 arg7, ...) {
    va_list hostStackArguments;
    va_start(hostStackArguments, arg7);
    Method method = nullptr;
    const u64 guest_result = LC32InvokeGuestSelectorRaw(
        self, _cmd, arg2, arg3, arg4, arg5, arg6, arg7,
        &hostStackArguments, &method);
    va_end(hostStackArguments);

    char *returnType = method_copyReturnType(method);
    u64 host_result = LC32GuestToHostReturnType(returnType, guest_result);
    free(returnType);
    return host_result;
}

static float LC32InvokeGuestSelectorGuestFloatHostFloat(
        id self, SEL _cmd, u64 arg2, u64 arg3, u64 arg4,
        u64 arg5, u64 arg6, u64 arg7, ...) {
    va_list hostStackArguments;
    va_start(hostStackArguments, arg7);
    const u64 guestResult = LC32InvokeGuestSelectorRaw(
        self, _cmd, arg2, arg3, arg4, arg5, arg6, arg7,
        &hostStackArguments, nullptr);
    va_end(hostStackArguments);
    return LC32GuestFloatReturn(guestResult);
}

static double LC32InvokeGuestSelectorGuestFloatHostDouble(
        id self, SEL _cmd, u64 arg2, u64 arg3, u64 arg4,
        u64 arg5, u64 arg6, u64 arg7, ...) {
    va_list hostStackArguments;
    va_start(hostStackArguments, arg7);
    const u64 guestResult = LC32InvokeGuestSelectorRaw(
        self, _cmd, arg2, arg3, arg4, arg5, arg6, arg7,
        &hostStackArguments, nullptr);
    va_end(hostStackArguments);
    return (double)LC32GuestFloatReturn(guestResult);
}

static float LC32InvokeGuestSelectorGuestDoubleHostFloat(
        id self, SEL _cmd, u64 arg2, u64 arg3, u64 arg4,
        u64 arg5, u64 arg6, u64 arg7, ...) {
    va_list hostStackArguments;
    va_start(hostStackArguments, arg7);
    const u64 guestResult = LC32InvokeGuestSelectorRaw(
        self, _cmd, arg2, arg3, arg4, arg5, arg6, arg7,
        &hostStackArguments, nullptr);
    va_end(hostStackArguments);
    return (float)LC32GuestDoubleReturn(guestResult);
}

static double LC32InvokeGuestSelectorGuestDoubleHostDouble(
        id self, SEL _cmd, u64 arg2, u64 arg3, u64 arg4,
        u64 arg5, u64 arg6, u64 arg7, ...) {
    va_list hostStackArguments;
    va_start(hostStackArguments, arg7);
    const u64 guestResult = LC32InvokeGuestSelectorRaw(
        self, _cmd, arg2, arg3, arg4, arg5, arg6, arg7,
        &hostStackArguments, nullptr);
    va_end(hostStackArguments);
    return LC32GuestDoubleReturn(guestResult);
}

/*
 * Selector names are process-global, while the same selector can refer to a
 * different backing ivar in every class.  Keep each synthetic accessor bound
 * to the class where it was installed and walk the receiver's superclass
 * chain for inherited accessors.
 */
struct LC32GuestIvarBinding {
    std::string name;
    u32 offset = 0;
    char type = '\0';
};

static std::mutex LC32GuestIvarGetterMutex;
static std::unordered_map<Class,
    std::unordered_map<SEL, LC32GuestIvarBinding>>
    LC32GuestIvarBindings;

static void LC32RegisterGuestIvarAccessor(Class cls, SEL selector,
                                           const char *ivarName,
                                           u32 offset, char type) {
    if(!cls || !selector || !ivarName || !*ivarName || !type) return;
    std::lock_guard<std::mutex> lock(LC32GuestIvarGetterMutex);
    LC32GuestIvarBindings[cls][selector] = {
        std::string(ivarName), offset, type
    };
}

static bool LC32GuestIvarBindingForReceiver(
        id receiver, SEL selector, LC32GuestIvarBinding *result) {
    if(!receiver || !selector || !result) return false;
    std::lock_guard<std::mutex> lock(LC32GuestIvarGetterMutex);
    for(Class cls = object_getClass(receiver); cls;
            cls = class_getSuperclass(cls)) {
        auto classIt = LC32GuestIvarBindings.find(cls);
        if(classIt == LC32GuestIvarBindings.end()) continue;
        auto bindingIt = classIt->second.find(selector);
        if(bindingIt == classIt->second.end()) continue;
        *result = bindingIt->second;
        return true;
    }
    return false;
}

static u64 LC32ReadGuestScalarIvar(
        u32 guestObject, const LC32GuestIvarBinding &binding) {
    auto *callbacks = Dynarmic_current_user_callbacks();
    const u32 address = guestObject + binding.offset;
    switch(binding.type) {
        case 'B':
        case 'C': return callbacks->MemoryRead8(address);
        case 'c': return (u64)(int64_t)(int8_t)
            callbacks->MemoryRead8(address);
        case 'S': return callbacks->MemoryRead16(address);
        case 's': return (u64)(int64_t)(int16_t)
            callbacks->MemoryRead16(address);
        case 'I':
        case 'L': return callbacks->MemoryRead32(address);
        case 'i':
        case 'l': return (u64)(int64_t)(int32_t)
            callbacks->MemoryRead32(address);
        case 'Q': return callbacks->MemoryRead64(address);
        case 'q': return (u64)(int64_t)callbacks->MemoryRead64(address);
        default: return 0;
    }
}

static void LC32WriteGuestScalarIvar(
        u32 guestObject, const LC32GuestIvarBinding &binding, u64 value) {
    auto *callbacks = Dynarmic_current_user_callbacks();
    const u32 address = guestObject + binding.offset;
    switch(binding.type) {
        case 'B':
        case 'C':
        case 'c': callbacks->MemoryWrite8(address, (u8)value); break;
        case 'S':
        case 's': callbacks->MemoryWrite16(address, (u16)value); break;
        case 'I':
        case 'L':
        case 'i':
        case 'l': callbacks->MemoryWrite32(address, (u32)value); break;
        case 'Q':
        case 'q': callbacks->MemoryWrite64(address, value); break;
        default: break;
    }
}

void LC32SetGuestScalarIvar(id self, SEL _cmd, u64 value) {
    LC32GuestIvarBinding binding;
    if(!LC32GuestIvarBindingForReceiver(self, _cmd, &binding)) return;
    LC32WriteGuestScalarIvar([self guest_self], binding, value);
}

void LC32SetGuestNSObjectIvar(id self, SEL _cmd, id value) {
    LC32GuestIvarBinding binding;
    if(!LC32GuestIvarBindingForReceiver(self, _cmd, &binding)) return;
    guest_object_setInstanceVariable([self guest_self], binding.name.c_str(),
                                     (u32)(u64)[value guest_self]);
}

id LC32GetGuestNSObjectIvar(id self, SEL _cmd) {
    LC32GuestIvarBinding binding;
    if(!LC32GuestIvarBindingForReceiver(self, _cmd, &binding)) return nil;
    u32 guestValue = 0;
    guest_object_getInstanceVariable([self guest_self], binding.name.c_str(),
                                     &guestValue);
    if(!guestValue) return nil;
    /* Resolve the guest object to its native peer (creating one if needed). */
    return (id)LC32GuestToHostReturnType((char *)"@", guestValue);
}

u64 LC32GetGuestScalarIvar(id self, SEL _cmd) {
    LC32GuestIvarBinding binding;
    if(!LC32GuestIvarBindingForReceiver(self, _cmd, &binding)) return 0;
    return LC32ReadGuestScalarIvar([self guest_self], binding);
}

u32 guest_dlsym(const char *host_name) {
    DynarmicGuestStackString guest_name(host_name);
    u32 args[] = {(u32)(u64)RTLD_DEFAULT, guest_name.guestPtr};
    return LC32InvokeGuestC(sharedHandle.guest_dlsym, false, sizeof(args)/sizeof(*args), args);
}

u32 guest_free(u32 guest_ptr) {
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "free");
    if(!guestPtr) {
        fprintf(stderr,
            "LC32: cannot release guest allocation because free is missing\n");
        return 0;
    }
    u32 args[] = {guest_ptr};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

// These class_copy*List shims are pretty much the same
u32 guest_class_copyIvarList(u32 guest_cls, unsigned int *outCount) {
    if(!threadHandle.jit) return false;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "class_copyIvarList");
    u32 guest_outCount = threadHandle.jit->Regs()[Reg::SP] -= sizeof(u32);
    u32 args[] = {guest_cls, guest_outCount};
    u32 result = LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
    *outCount = Dynarmic_current_user_callbacks()->MemoryRead32(guest_outCount);
    threadHandle.jit->Regs()[Reg::SP] += sizeof(u32);
    return result;
}
u32 guest_class_copyMethodList(u32 guest_cls, unsigned int *outCount) {
    if(!threadHandle.jit) return false;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "class_copyMethodList");
    u32 guest_outCount = threadHandle.jit->Regs()[Reg::SP] -= sizeof(u32);
    u32 args[] = {guest_cls, guest_outCount};
    u32 result = LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
    *outCount = Dynarmic_current_user_callbacks()->MemoryRead32(guest_outCount);
    threadHandle.jit->Regs()[Reg::SP] += sizeof(u32);
    return result;
}
u32 guest_class_copyProtocolList(u32 guest_cls, unsigned int *outCount) {
    if(!threadHandle.jit) return false;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "class_copyProtocolList");
    u32 guest_outCount = threadHandle.jit->Regs()[Reg::SP] -= sizeof(u32);
    u32 args[] = {guest_cls, guest_outCount};
    u32 result = LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
    *outCount = Dynarmic_current_user_callbacks()->MemoryRead32(guest_outCount);
    threadHandle.jit->Regs()[Reg::SP] += sizeof(u32);
    return result;
}

u32 guest_class_createInstance(u32 guest_cls, u32 extraBytes) {
    if(!threadHandle.jit) return false;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "class_createInstance");
    u32 args[] = {guest_cls, extraBytes};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

u32 guest_class_getClassMethod(u32 guest_cls, u32 guest_sel) {
    if(!threadHandle.jit) return false;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "class_getClassMethod");
    u32 args[] = {guest_cls, guest_sel};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

u32 guest_class_getInstanceMethod(u32 guest_cls, u32 guest_sel) {
    if(!threadHandle.jit) return false;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "class_getInstanceMethod");
    u32 args[] = {guest_cls, guest_sel};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

u32 guest_class_getName(u32 guest_cls) {
    if(!threadHandle.jit) return false;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "class_getName");
    u32 args[] = {guest_cls};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

u32 guest_class_getSuperclass(u32 guest_cls) {
    if(!guest_cls) return 0;
    return Dynarmic_current_user_callbacks()->MemoryRead32(guest_cls + 4);
}

u32 guest_ivar_getName(u32 guest_ivar) {
    return Dynarmic_current_user_callbacks()->MemoryRead32(guest_ivar + sizeof(u32[1]));
}

u32 guest_ivar_getTypeEncoding(u32 guest_ivar) {
    return Dynarmic_current_user_callbacks()->MemoryRead32(guest_ivar + sizeof(u32[2]));
}

u32 guest_object_getClass(u32 guest_obj) {
    if(!guest_obj) return 0;
    return Dynarmic_current_user_callbacks()->MemoryRead32(guest_obj);
}

u32 guest_object_setInstanceVariable(u32 guest_obj, const char *host_name, u32 newValue) {
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(
        cache, "object_setInstanceVariable");
    DynarmicGuestStackString guest_name(host_name);
    u32 args[] = {guest_obj, guest_name.guestPtr, newValue};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

u32 guest_object_getInstanceVariable(u32 guest_obj, const char *host_name, u32 *outValue) {
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(
        cache, "object_getInstanceVariable");
    DynarmicGuestStackString guest_name(host_name);
    /* ARM32 object_getInstanceVariable writes one pointer-sized value; zero
     * the whole slot so unread upper bytes never leak stack garbage. */
    u32 guest_outValue = threadHandle.jit->Regs()[Reg::SP] -= sizeof(u64);
    const u64 zero = 0;
    Dynarmic_mem_1write(guest_outValue, sizeof(zero),
                        const_cast<char *>(
                            reinterpret_cast<const char *>(&zero)));
    u32 args[] = {guest_obj, guest_name.guestPtr, guest_outValue};
    const u32 result = LC32InvokeGuestC(
        guestPtr, false, sizeof(args)/sizeof(*args), args);
    if(outValue) {
        *outValue = Dynarmic_current_user_callbacks()->MemoryRead32(
            guest_outValue);
    }
    threadHandle.jit->Regs()[Reg::SP] += sizeof(u64);
    return result;
}

u32 guest_protocol_getName(u32 guest_protocol) {
    return Dynarmic_current_user_callbacks()->MemoryRead32(guest_protocol + sizeof(u32[1]));
}

u32 guest_sel_registerName(const char *host_name) {
    if(!host_name || !Dynarmic_guest_thread_is_registered()) return 0;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "sel_registerName");
    if(!guestPtr) return 0;
    DynarmicGuestStackString guest_name(host_name);
    u32 args[] = {guest_name.guestPtr};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

//if(!guestPtr) guestPtr = guest_dlsym("LC32TestHostToGuestCall");
//u32 args[] = {0x40404040, 0x41414141, 0x42424242, 0x43434343, 0x44444444, 0x45454545, 0x46464646, 0x47474747};
u32 guest_objc_getClass(const char *name) {
    if(!threadHandle.jit) return 0;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "objc_getClass");

    DynarmicGuestStackString guest_name(name);
    u32 args[] = {guest_name.guestPtr};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

Class guest_objc_getClass_retHostClass(const char *name) {
    // Get the guest class pointer
    u32 guest_outClass = guest_objc_getClass(name);
    if(!guest_outClass) return nil;

    // Now that we will be recursively resolving subclass
    Class subclass;
    u32 guest_superclass = guest_class_getSuperclass(guest_outClass);
    DynarmicHostString superclassName(guest_class_getName(guest_superclass));
    subclass = objc_getClass(superclassName.hostPtr);
    if(!subclass) return nil;

    // Now we can construct the class
    Class outClass = objc_allocateClassPair(subclass, name, 0);
    // set class to class
    [(id)outClass setGuest_self:guest_outClass];
    // set metaclass to metaclass
    [(id)object_getClass(outClass) setGuest_self:guest_object_getClass(guest_outClass)];
    // resolve methods and register a dynamic resolver
    [LC32ObjCMethodResolver registerClass:outClass];
    LC32UIKitPrepareGuestClass(outClass);
    /* Native owners of a synthesized guest class can outlive every ordinary
     * guest reference. Coordinate its final native release so the lifetime
     * pin runs guest -dealloc while this mirror is still retainable. */
    LC32InstallGuestMirrorReferenceCounting(outClass);
    // register to objc
    objc_registerClassPair(outClass);
    [outClass setGuestClass:YES];
    [(id)object_getClass(outClass) setGuestClass:YES];
    return outClass;
}

u64 guest_objc_msgSend(int argc, u32 *args) {
    LC32DrainDeferredGuestPinReleases();
#ifdef LC32_TRACE_GUEST_OBJC_MSGSEND
    if(argc >= 2 && args != nullptr) {
        bool trace = args[1] == 0;
#ifdef LC32_TRACE_GUEST_OBJC_RECEIVER
        trace = trace || args[0] ==
            static_cast<u32>(LC32_TRACE_GUEST_OBJC_RECEIVER);
#endif
        if(trace) {
            fprintf(stderr,
                "LC32 guest objc_msgSend trace: receiver=0x%08x "
                "selector=0x%08x argc=%d host_thread=%u caller=%p\n",
                args[0], args[1], argc,
                pthread_mach_thread_np(pthread_self()),
                __builtin_return_address(0));
        }
    }
#endif
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "objc_msgSend");
    return LC32InvokeGuestC(guestPtr, true, argc, args);
}

/*
 * Native collections retain a dynamically mirrored host object without
 * touching the ARM32 object's retain count. Keep one guest-only +1 alive for
 * exactly as long as the host mirror rather than trying to mirror every host
 * retain/release. Ordinary guest ownership operations continue to mirror
 * their corresponding native ownership operations.
 */
enum class LC32GuestReleaseKind : uint8_t {
    LifetimePin,
    LogicalOwnership,
    OrdinaryOwnership,
    BlockRuntime,
    GuestMirrorFinalRelease,
};

static bool LC32AdjustGuestReferenceNow(
        u32 guestObject, bool retaining,
        LC32GuestReleaseKind releaseKind =
            LC32GuestReleaseKind::LifetimePin) {
    assert(releaseKind !=
           LC32GuestReleaseKind::GuestMirrorFinalRelease);
    if(releaseKind == LC32GuestReleaseKind::BlockRuntime) {
        assert(!retaining);
        static std::atomic<u32> blockRelease{0};
        const u32 releaseFunction = LC32CachedGuestSymbol(
            blockRelease, "_Block_release");
        if(!releaseFunction) {
            fprintf(stderr,
                "LC32: guest _Block_release is unavailable for 0x%x\n",
                guestObject);
            return false;
        }
        u32 args[] = {guestObject};
        (void)LC32InvokeGuestC(releaseFunction, false,
                              sizeof(args) / sizeof(*args), args);
        return true;
    }

    if(!retaining && releaseKind == LC32GuestReleaseKind::LifetimePin) {
        static std::atomic<u32> lifetimePinRelease{0};
        const u32 releaseFunction = LC32CachedGuestSymbol(
            lifetimePinRelease, "LC32ReleaseGuestLifetimePin");
        if(!releaseFunction) {
            fprintf(stderr,
                "LC32: guest lifetime-pin release is unavailable for 0x%x\n",
                guestObject);
            return false;
        }
        u32 args[] = {guestObject};
        return LC32InvokeGuestC(releaseFunction, false,
                               sizeof(args) / sizeof(*args), args) != 0;
    }

    static std::atomic<u32> retainSelector{0};
    static std::atomic<u32> releaseSelector{0};
    static std::atomic<u32> logicalReleaseSelector{0};
    static std::atomic<u32> ordinaryReleaseSelector{0};
    u32 selector;
    if(retaining) {
        selector = LC32CachedGuestSelector(
            retainSelector, "LC32_retain");
    } else if(releaseKind == LC32GuestReleaseKind::LogicalOwnership) {
        selector = LC32CachedGuestSelector(
            logicalReleaseSelector,
            "LC32_releaseGuestOwnershipOnly");
    } else if(releaseKind == LC32GuestReleaseKind::OrdinaryOwnership) {
        // Public release is the ownership-bridging implementation after the
        // guest NSObject method exchange. It remains guest-only when no peer
        // exists, and also decrements a peer acquired since scheduling.
        selector = LC32CachedGuestSelector(
            ordinaryReleaseSelector, "release");
    } else {
        selector = LC32CachedGuestSelector(
            releaseSelector, "LC32_release");
    }
    u32 args[] = {guestObject, selector};
    guest_objc_msgSend(sizeof(args) / sizeof(*args), args);
    return true;
}

struct LC32DeferredGuestRelease {
    u32 guestObject;
    LC32GuestReleaseKind kind;
    u64 retainedHostObject;
    u64 weakRegistryGeneration;
};

static std::mutex& LC32DeferredGuestPinReleaseMutex() {
    // Associated objects can be torn down during process shutdown. Intentionally
    // keep this synchronization state alive until the process exits.
    static std::mutex *mutex = new std::mutex;
    return *mutex;
}

static std::vector<LC32DeferredGuestRelease>&
LC32DeferredGuestPinReleases() {
    static std::vector<LC32DeferredGuestRelease> *releases =
        new std::vector<LC32DeferredGuestRelease>;
    return *releases;
}

static thread_local bool LC32DrainingGuestPinReleases;

static void LC32ReleaseGuestReference(
        u32 guestObject, LC32GuestReleaseKind kind,
        id hostObjectToKeepAlive = nil,
        u64 weakRegistryGeneration = 0) {
    if(threadHandle.jit && threadHandle.cb) {
        if(kind == LC32GuestReleaseKind::LifetimePin) {
            LC32RefreshHostWeakMappingRetiringOwner(
                guestObject, weakRegistryGeneration);
        }
        const bool lifetimePinWasFinal =
            LC32AdjustGuestReferenceNow(guestObject, false, kind);
        if(kind == LC32GuestReleaseKind::LifetimePin &&
           lifetimePinWasFinal) {
            LC32FinalizeHostWeakMappingRetirement(
                guestObject, weakRegistryGeneration);
        }
        return;
    }
    if(kind == LC32GuestReleaseKind::BlockRuntime &&
            Dynarmic_submit_guest_block_release(guestObject)) {
        return;
    }

    u64 retainedHostObject = 0;
    if(hostObjectToKeepAlive) {
        LC32ObjCRetainWithoutARC(hostObjectToKeepAlive);
        retainedHostObject = (u64)hostObjectToKeepAlive;
    }

    // The guest reference remains held until a registered guest thread drains
    // this entry. Logical ownership releases also keep the native mirror alive
    // so they can safely clear its reverse mapping before releasing it.
    std::lock_guard<std::mutex> lock(
        LC32DeferredGuestPinReleaseMutex());
    LC32DeferredGuestPinReleases().push_back({
        guestObject, kind, retainedHostObject, weakRegistryGeneration,
    });
}

static void LC32ReleaseGuestPin(u32 guestObject,
                                u64 weakRegistryGeneration) {
    LC32ReleaseGuestReference(
        guestObject, LC32GuestReleaseKind::LifetimePin, nil,
        weakRegistryGeneration);
}

static void LC32ReleaseGuestLogicalOwnership(
        u32 guestObject, id hostObject) {
    LC32ReleaseGuestReference(
        guestObject, LC32GuestReleaseKind::LogicalOwnership,
        hostObject);
}

static void LC32ReleaseGuestOrdinaryOwnership(u32 guestObject) {
    LC32ReleaseGuestReference(
        guestObject, LC32GuestReleaseKind::OrdinaryOwnership);
}

static void LC32DeferGuestMirrorFinalRelease(id hostObject) {
    if(!hostObject) return;

    /* The caller transfers the temporary root guard which is now the mirror's
     * final native +1. Do not retain it again: a registered guest thread will
     * detach the lifetime pin first and consume this exact reference last. */
    std::lock_guard<std::mutex> lock(
        LC32DeferredGuestPinReleaseMutex());
    LC32DeferredGuestPinReleases().push_back({
        0, LC32GuestReleaseKind::GuestMirrorFinalRelease,
        (u64)hostObject, 0,
    });
}

extern "C" u32 LC32CopyGuestBlock(u32 guestBlock) {
    if(!guestBlock || !threadHandle.jit || !threadHandle.cb) return 0;

    static std::atomic<u32> blockCopy{0};
    const u32 copyFunction = LC32CachedGuestSymbol(
        blockCopy, "_Block_copy");
    if(!copyFunction) {
        fprintf(stderr,
            "LC32: guest _Block_copy is unavailable for 0x%x\n",
            guestBlock);
        return 0;
    }
    u32 args[] = {guestBlock};
    return (u32)LC32InvokeGuestC(copyFunction, false,
                                sizeof(args) / sizeof(*args), args);
}

extern "C" void LC32ReleaseGuestBlock(u32 guestBlock) {
    if(!guestBlock) return;
    LC32ReleaseGuestReference(
        guestBlock, LC32GuestReleaseKind::BlockRuntime);
}

static void LC32DrainDeferredGuestPinReleases() {
    if(LC32DrainingGuestPinReleases ||
            !threadHandle.jit || !threadHandle.cb) {
        return;
    }

    std::vector<LC32DeferredGuestRelease> pending;
    {
        std::lock_guard<std::mutex> lock(
            LC32DeferredGuestPinReleaseMutex());
        pending.swap(LC32DeferredGuestPinReleases());
    }
    if(pending.empty()) return;

    LC32DrainingGuestPinReleases = true;
    for(const LC32DeferredGuestRelease &release : pending) {
        if(release.kind ==
                LC32GuestReleaseKind::GuestMirrorFinalRelease) {
            LC32RetireGuestMirrorWithTransferredReference(
                (id)release.retainedHostObject);
            continue;
        }
        if(release.kind == LC32GuestReleaseKind::LifetimePin) {
            LC32RefreshHostWeakMappingRetiringOwner(
                release.guestObject, release.weakRegistryGeneration);
        }
        const bool lifetimePinWasFinal = LC32AdjustGuestReferenceNow(
            release.guestObject, false, release.kind);
        if(release.kind == LC32GuestReleaseKind::LifetimePin &&
           lifetimePinWasFinal) {
            LC32FinalizeHostWeakMappingRetirement(
                release.guestObject, release.weakRegistryGeneration);
        }
        if(release.retainedHostObject) {
            objc_release((id)release.retainedHostObject);
        }
    }
    LC32DrainingGuestPinReleases = false;
}

@interface LC32GuestLifetimePin : NSObject {
@public
    u32 guestObject;
    u64 weakRegistryGeneration;
    u64 tracedHostObject;
    const char *tracedClassName;
}
@end

@implementation LC32GuestLifetimePin
- (void)dealloc {
    if(guestObject) {
        LC32MarkHostWeakMappingRetiring(
            guestObject, weakRegistryGeneration);
        if(tracedHostObject) {
            LC32OperationTraceDeallocated(
                tracedHostObject, guestObject, tracedClassName);
        }
        LC32ReleaseGuestPin(guestObject, weakRegistryGeneration);
    }
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}
@end

@interface LC32GuestAutoreleaseToken : NSObject {
@public
    u32 guestObject;
    id hostObject;
}
@end

@implementation LC32GuestAutoreleaseToken
- (void)dealloc {
    if(hostObject) {
        LC32OperationTraceLiveObject(
            "guest-autorelease-drain", hostObject, guestObject);
        // Keep hostObject strongly held while the guest removes its
        // corresponding logical +1 and, if final, clears the host's reverse
        // mapping. The token owns the paired native autorelease operation.
        LC32ReleaseGuestLogicalOwnership(guestObject, hostObject);
    } else {
        /*
         * The object was guest-only when autoreleased. Use an ordinary guest
         * release: it remains local if the object was never bridged, or also
         * decrements a peer created before this token drained.
         */
        LC32ReleaseGuestOrdinaryOwnership(guestObject);
    }
#if !__has_feature(objc_arc)
    [hostObject release];
    [super dealloc];
#endif
}
@end

static void LC32ScheduleGuestAutoreleaseNow(
        id __unsafe_unretained hostObject, u32 guestObject) {
    if(!guestObject) return;

#ifdef LC32_TRACE_AUTORELEASE
    fprintf(stderr,
        "LC32 autorelease trace: schedule begin guest=0x%08x "
        "host=%p host_thread=%u\n",
        guestObject, hostObject,
        pthread_mach_thread_np(pthread_self()));
#endif

    if(hostObject) {
        LC32OperationTraceLiveObject(
            "guest-autorelease", hostObject, guestObject);
    }

    LC32GuestAutoreleaseToken *token =
        [LC32GuestAutoreleaseToken new];
#ifdef LC32_TRACE_AUTORELEASE
    fprintf(stderr,
        "LC32 autorelease trace: token allocated guest=0x%08x "
        "token=%p\n",
        guestObject, token);
#endif
    token->guestObject = guestObject;
#if __has_feature(objc_arc)
    token->hostObject = hostObject;
    // Transfer a dedicated +1 to the host autorelease pool. Clearing the ARC
    // local first leaves exactly that transferred ownership outstanding.
    void *retainedToken = (__bridge_retained void *)token;
    token = nil;
    LC32ObjCAutoreleaseWithoutARC((__bridge id)retainedToken);
#ifdef LC32_TRACE_AUTORELEASE
    fprintf(stderr,
        "LC32 autorelease trace: token queued guest=0x%08x "
        "token=%p\n",
        guestObject, retainedToken);
#endif
#else
    token->hostObject = [hostObject retain];
    [token autorelease];
#endif

    if(hostObject) {
        // The token now owns the mirror's existing guest-paired +1. Its
        // eventual destruction releases guest logical ownership first, then
        // this host +1.
        objc_release(hostObject);
    }
#ifdef LC32_TRACE_AUTORELEASE
    fprintf(stderr,
        "LC32 autorelease trace: schedule end guest=0x%08x\n",
        guestObject);
#endif
}

extern "C" u32 LC32ScheduleGuestAutorelease(
        u32 hostLow, u32 hostHigh, u32 guestStackPointer) {
    const u64 hostAddress = hostLow | ((u64)hostHigh << 32);
    id __unsafe_unretained hostObject = (id)hostAddress;
#ifdef LC32_TRACE_AUTORELEASE
    fprintf(stderr,
        "LC32 autorelease trace: entry host=%p guest_sp=0x%08x "
        "host_thread=%u\n",
        hostObject, guestStackPointer,
        pthread_mach_thread_np(pthread_self()));
#endif
    // SVC 1002 forwards r2/r3 directly and passes the guest SP as its third
    // native argument. The next ARMv7 vararg (the guest object) is at [SP].
    const u32 guestObject =
        Dynarmic_current_user_callbacks()->MemoryRead32(guestStackPointer);
#ifdef LC32_TRACE_AUTORELEASE
    fprintf(stderr,
        "LC32 autorelease trace: decoded guest=0x%08x from "
        "guest_sp=0x%08x\n",
        guestObject, guestStackPointer);
#endif
    if(!guestObject) return 0;

    LC32ScheduleGuestAutoreleaseNow(hostObject, guestObject);
#ifdef LC32_TRACE_AUTORELEASE
    fprintf(stderr,
        "LC32 autorelease trace: return guest=0x%08x\n",
        guestObject);
#endif
    return 0;
}

static void LC32PinGuestObjectToHost(id hostObject, u32 guestObject,
                                     bool retainGuestObject) {
    if(!hostObject || !guestObject) return;

    @synchronized(hostObject) {
        LC32GuestLifetimePin *existing = objc_getAssociatedObject(
            hostObject, LC32GuestLifetimePinKey);
        if(existing) {
            assert(existing->guestObject == guestObject);
            return;
        }

        if(retainGuestObject) {
            assert(threadHandle.jit && threadHandle.cb);
            LC32AdjustGuestReferenceNow(guestObject, true);
        }

        LC32GuestLifetimePin *pin = [LC32GuestLifetimePin new];
        pin->guestObject = guestObject;
        pin->weakRegistryGeneration =
            LC32RegisterHostWeakMapping(hostObject, guestObject);
        assert(pin->weakRegistryGeneration != 0);
        if(LC32OperationTraceEnabled() &&
           LC32HostObjectIsOperation(hostObject)) {
            pin->tracedHostObject = (u64)hostObject;
            pin->tracedClassName = class_getName(object_getClass(hostObject));
            LC32OperationTraceLiveObject(
                retainGuestObject ? "pin-create-retaining-guest"
                                  : "pin-create-adopting-guest",
                hostObject, guestObject);
        }
        objc_setAssociatedObject(hostObject, LC32GuestLifetimePinKey, pin,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
#if !__has_feature(objc_arc)
        [pin release];
#endif
    }
}

static std::mutex& LC32GuestMirrorReleaseMutex() {
    /* Native releases of the last two owners may race. Serialize the short
     * root-reference handoff so exactly one caller becomes the retirement
     * owner. Guest destruction itself runs after this lock is released. */
    static std::mutex *mutex = new std::mutex;
    return *mutex;
}

static constexpr const char *LC32GuestMirrorRetiringIvarName =
    "__lc32_host_mirror_retiring_state_7f84d2";

static u8 *LC32GuestMirrorRetiringState(id hostObject) {
    if(!hostObject) return nullptr;
    Ivar ivar = class_getInstanceVariable(
        object_getClass(hostObject), LC32GuestMirrorRetiringIvarName);
    if(!ivar) return nullptr;
    return reinterpret_cast<u8 *>(hostObject) + ivar_getOffset(ivar);
}

static bool LC32GuestMirrorIsRetiring(id hostObject) {
    u8 *state = LC32GuestMirrorRetiringState(hostObject);
    return state && __atomic_load_n(state, __ATOMIC_ACQUIRE) != 0;
}

static void LC32SetGuestMirrorRetiring(id hostObject, bool retiring) {
    u8 *state = LC32GuestMirrorRetiringState(hostObject);
    assert(state);
    __atomic_store_n(state, retiring ? 1 : 0, __ATOMIC_RELEASE);
}

static bool LC32GuestMirrorPinSnapshot(
        id hostObject, u32 *guestObject, u64 *generation) {
    LC32GuestLifetimePin *pin = objc_getAssociatedObject(
        hostObject, LC32GuestLifetimePinKey);
    if(!pin || !pin->guestObject) return false;
    *guestObject = pin->guestObject;
    *generation = pin->weakRegistryGeneration;
    return true;
}

static bool LC32DetachGuestMirrorPin(
        id hostObject, u32 *guestObject, u64 *generation,
        u64 *tracedHostObject, const char **tracedClassName) {
    @synchronized(hostObject) {
        LC32GuestLifetimePin *pin = objc_getAssociatedObject(
            hostObject, LC32GuestLifetimePinKey);
        if(!pin || !pin->guestObject) return false;

        *guestObject = pin->guestObject;
        *generation = pin->weakRegistryGeneration;
        *tracedHostObject = pin->tracedHostObject;
        *tracedClassName = pin->tracedClassName;

        /* Disarm the associated object's ordinary -dealloc path. Its release
         * may be autorelease-delayed by objc_getAssociatedObject, whereas the
         * coordinated guest release below must finish under the host guard. */
        pin->guestObject = 0;
        pin->weakRegistryGeneration = 0;
        pin->tracedHostObject = 0;
        pin->tracedClassName = nullptr;
        objc_setAssociatedObject(hostObject, LC32GuestLifetimePinKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return true;
    }
}

static void LC32ClearGuestSelfIfEqualWhileSynchronized(
        id hostObject, u32 expectedGuestObject) {
    NSNumber *mappedGuestSelf =
        objc_getAssociatedObject(hostObject, kGuestSelf);
    if(mappedGuestSelf.unsignedLongLongValue != expectedGuestObject) {
        return;
    }
    LC32OperationTraceLiveObject(
        "reverse-map-clear", hostObject, expectedGuestObject);
    objc_setAssociatedObject(hostObject, kGuestSelf, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void LC32ClearGuestSelfIfEqual(id hostObject,
                                      u32 expectedGuestObject) {
    @synchronized(hostObject) {
        LC32ClearGuestSelfIfEqualWhileSynchronized(
            hostObject, expectedGuestObject);
    }
}

class LC32TransferredRootReference {
public:
    explicit LC32TransferredRootReference(id object) : object(object) {}
    ~LC32TransferredRootReference() {
        if(object) _objc_rootRelease(object);
    }

    LC32TransferredRootReference(const LC32TransferredRootReference&) = delete;
    LC32TransferredRootReference& operator=(
        const LC32TransferredRootReference&) = delete;

    id relinquish() {
        id transferred = object;
        object = nil;
        return transferred;
    }

private:
    id object;
};

static void LC32RetireGuestMirrorWithTransferredReference(id hostObject) {
    if(!hostObject) return;
    LC32TransferredRootReference nativeGuard(hostObject);

    u32 guestObject = 0;
    u64 generation = 0;
    {
        std::lock_guard<std::mutex> lock(
            LC32GuestMirrorReleaseMutex());
        if(!LC32GuestMirrorPinSnapshot(
                hostObject, &guestObject, &generation)) {
            return;
        }

        /* A foreign-thread deferral may give an existing owner time to retain
         * the mirror. Keep retirement published and preserve the queued
         * guard until every real owner has drained. */
        if(_objc_rootRetainCount(hostObject) != 1) {
            LC32DeferGuestMirrorFinalRelease(nativeGuard.relinquish());
            return;
        }
    }

    /* This may run arbitrary guest -dealloc code. Keep both the native root
     * guard, lifetime pin, and reverse mapping intact until it returns, so
     * messages sent on `self` during teardown still resolve to this live
     * native mirror.  The guest helper atomically decides whether releasing
     * the pin reached zero. */
    LC32RefreshHostWeakMappingRetiringOwner(
        guestObject, generation);
    const bool lifetimePinWasFinal = LC32AdjustGuestReferenceNow(
        guestObject, false, LC32GuestReleaseKind::LifetimePin);
    if(!lifetimePinWasFinal) {
        /* With host-first weak tokens and first-publication serialization,
         * an extra stable guest owner must have a paired native owner. Keep
         * the pin and guard intact and retry after that owner drains. */
        LC32DeferGuestMirrorFinalRelease(nativeGuard.relinquish());
        return;
    }

    u64 tracedHostObject = 0;
    const char *tracedClassName = nullptr;
    if(!LC32DetachGuestMirrorPin(
            hostObject, &guestObject, &generation,
            &tracedHostObject, &tracedClassName)) {
        fprintf(stderr,
            "LC32: finalized guest mirror 0x%llx without its lifetime pin\n",
            (unsigned long long)(u64)hostObject);
    }
    LC32FinalizeHostWeakMappingRetirement(guestObject, generation);
    if(tracedHostObject) {
        LC32OperationTraceDeallocated(
            tracedHostObject, guestObject, tracedClassName);
    }
    LC32ClearGuestSelfIfEqual(hostObject, guestObject);
}

static BOOL LC32GuestMirrorRetainWeakReference(id self, SEL) {
    /* libobjc invokes this with the object's SideTable lock held.  The root
     * helper is the no-lock try-retain primitive intended for that context;
     * do not take LC32GuestMirrorReleaseMutex here. */
    if(LC32GuestMirrorIsRetiring(self)) return NO;
    if(!_objc_rootTryRetain(self)) return NO;
    if(LC32GuestMirrorIsRetiring(self)) {
        /* Retirement may have been published between the first state load
         * and the no-lock root try-retain. Balance that +1 away from the
         * SideTable critical section and fail the weak load. */
        LC32DeferOwnedHostRelease((void *)self);
        return NO;
    }
    return YES;
}

static BOOL LC32GuestMirrorAllowsWeakReference(id self, SEL) {
    /* See LC32GuestMirrorRetainWeakReference: this callback also runs under
     * libobjc's weak-reference lock. */
    if(LC32GuestMirrorIsRetiring(self)) return NO;
    return _objc_rootIsDeallocating(self) ? NO : YES;
}

static void LC32GuestMirrorRelease(id self, SEL) {
    if(!self) return;

    std::unique_lock<std::mutex> lock(
        LC32GuestMirrorReleaseMutex());
    if(LC32GuestMirrorIsRetiring(self)) {
        /* Every actual -release message owns a distinct native +1. Deferred
         * retirement guards are transferred directly to Retire and are never
         * sent this selector. Drop the caller's reference outside the global
         * release mutex: it may be the final rejected weak temporary and run
         * native teardown recursively. */
        lock.unlock();
        _objc_rootRelease(self);
        return;
    }

    /* Hold a temporary root reference while consuming the caller's +1. If
     * another real owner remains, drop the guard and finish normally. If the
     * guard is now the sole owner, transfer it to coordinated retirement. */
    _objc_rootRetain(self);
    _objc_rootRelease(self);
    if(_objc_rootRetainCount(self) != 1) {
        _objc_rootRelease(self);
        return;
    }

    u32 guestObject = 0;
    u64 generation = 0;
    if(!LC32GuestMirrorPinSnapshot(
            self, &guestObject, &generation)) {
        lock.unlock();
        _objc_rootRelease(self);
        return;
    }

    LC32SetGuestMirrorRetiring(self, true);
    LC32MarkHostWeakMappingRetiring(guestObject, generation);
    /* A native weak load which entered before the retiring marker may have
     * completed its root try-retain. Recheck after publication while the
     * release handoff is still serialized; later weak loads are rejected by
     * the custom weak-RR methods below. */
    if(_objc_rootRetainCount(self) != 1) {
        LC32SetGuestMirrorRetiring(self, false);
        LC32RestoreHostWeakMappingLive(guestObject, generation);
        _objc_rootRelease(self);
        return;
    }
    lock.unlock();

    if(!Dynarmic_guest_thread_is_registered()) {
        LC32DeferGuestMirrorFinalRelease(self);
        return;
    }
    LC32RetireGuestMirrorWithTransferredReference(self);
}

static void LC32InstallGuestMirrorReferenceCounting(Class cls) {
    if(!cls) return;
    Class superclass = class_getSuperclass(cls);
    if(!class_getInstanceVariable(
            superclass, LC32GuestMirrorRetiringIvarName)) {
        const bool added = class_addIvar(
            cls, LC32GuestMirrorRetiringIvarName, sizeof(u8), 0, "C");
        assert(added);
    }
    assert(class_getInstanceVariable(
        cls, LC32GuestMirrorRetiringIvarName));

    Method releaseMethod = class_getInstanceMethod(
        NSObject.class, @selector(release));
    const char *types = releaseMethod
        ? method_getTypeEncoding(releaseMethod) : "v@:";
    class_replaceMethod(cls, @selector(release),
                        (IMP)&LC32GuestMirrorRelease, types);

    const SEL retainWeakSelector =
        sel_registerName("retainWeakReference");
    Method retainWeakMethod = class_getInstanceMethod(
        NSObject.class, retainWeakSelector);
    class_replaceMethod(cls, retainWeakSelector,
        (IMP)&LC32GuestMirrorRetainWeakReference,
        retainWeakMethod ? method_getTypeEncoding(retainWeakMethod) : "c@:");

    const SEL allowsWeakSelector =
        sel_registerName("allowsWeakReference");
    Method allowsWeakMethod = class_getInstanceMethod(
        NSObject.class, allowsWeakSelector);
    class_replaceMethod(cls, allowsWeakSelector,
        (IMP)&LC32GuestMirrorAllowsWeakReference,
        allowsWeakMethod ? method_getTypeEncoding(allowsWeakMethod) : "c@:");
}

objc_hook_getClass host_getClass;
BOOL host_hook_getClass(const char *name, Class *outClass) {
    if(host_getClass && host_getClass(name, outClass)) {
        return true;
    }

    /*
     * NSZombie implements diagnostics by looking up private replacement
     * classes named _NSZombie_<original class>.  Those names are host runtime
     * bookkeeping, not guest classes.  Synthesizing an ARM32-backed class for
     * them corrupts the zombie object before it can report the original
     * over-release (and can crash during early framework initialization).
     */
    if(name && strncmp(name, "_NSZombie_", 10) == 0) {
        return false;
    }

    printf("host_hook_getClass: %s\n", name);
    *outClass = guest_objc_getClass_retHostClass(name);
    return *outClass != nil;
}

@implementation NSObject(LC32)
- (void)setGuestClass:(BOOL)value {
    return objc_setAssociatedObject(self, kGuestClass, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)isGuestClass {
    return ((NSNumber *)objc_getAssociatedObject(self, kGuestClass)).boolValue;
}

// Set the equivalent guest object pointer.
// Called from guest_self if the object has not been known by guest before (eg passing UIApplication object to guest)
// Called from guest's setHost_self if the object is created by guest code (eg creating AppDelegate, UIWindow, etc)
- (void)setGuest_self:(u32)ptr {
    //assert(!self.guest_selfOrNull);
    @synchronized(self) {
        objc_setAssociatedObject(self, kGuestSelf, @(ptr),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    LC32OperationTraceLiveObject("reverse-map-set", self, ptr);
}

- (u32)guest_selfOrNull {
    return ((NSNumber *)objc_getAssociatedObject(self, kGuestSelf)).unsignedLongValue;
}

- (u32)LC32_bindGuestSelfIfAbsent:(u32)ptr {
    u32 boundGuestObject;
    @synchronized(self) {
        const u32 existing = self.guest_selfOrNull;
        if(existing) {
            boundGuestObject = existing;
        } else {
            objc_setAssociatedObject(self, kGuestSelf, @(ptr),
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            boundGuestObject = ptr;
        }
    }
    /*
     * An initializer may replace its +alloc placeholder (class clusters do
     * this routinely). Move the lifetime guarantee to the returned native
     * object as soon as it acquires the reverse mapping. The placeholder's
     * pin is released independently when that object is destroyed.
     */
    if(boundGuestObject == ptr) {
        /*
         * This is also needed when +alloc and -init return the same object:
         * +alloc installed its reverse mapping but deliberately did not pin
         * native class-cluster placeholders, which may be shared.
         */
        LC32PinGuestObjectToHost(self, ptr, true);
    }
    return boundGuestObject;
}

- (void)LC32_clearGuestSelfIfEqual:(u64)expectedGuestSelf {
    LC32ClearGuestSelfIfEqual(self, (u32)expectedGuestSelf);
}

- (u32)guest_self {
    u32 ptr = self.guest_selfOrNull;
    if(ptr) {
        LC32OperationTraceLiveObject("guest-self-existing", self, ptr);
        return ptr;
    }
    if(LC32GuestMirrorIsRetiring(self)) return 0;

    @synchronized(self) {
    ptr = self.guest_selfOrNull;
    if(ptr) {
        LC32OperationTraceLiveObject(
            "guest-self-existing-locked", self, ptr);
        return ptr;
    }
    if(LC32GuestMirrorIsRetiring(self)) return 0;

    Class hostClass = self.class;
    const char *className = class_getName(hostClass);
    Class matchedHostClass = hostClass;
    if(LC32HostObjectIsDispatchData(self)) {
        /*
         * OS_dispatch_data stores its state in a private allocation made by
         * libdispatch's +allocWithZone:.  A normal bridge proxy created with
         * class_createInstance has none of that state, so guest -length and
         * -bytes read beyond the object.  Treat native dispatch data as an
         * immutable NSData peer; LC32CopyHostDataBytes flattens it natively.
         */
        matchedHostClass = [NSData class];
        ptr = guest_objc_getClass("NSData");
    } else {
        while(matchedHostClass != Nil) {
            ptr = guest_objc_getClass(class_getName(matchedHostClass));
            if(ptr) break;
            matchedHostClass = class_getSuperclass(matchedHostClass);
        }
    }
    if(!ptr) {
        printf("LC32: Error: Host required missing guest class %s\n", className);
        return 0;
    }
    if(matchedHostClass != hostClass) {
        printf("LC32: mapping host class %s through guest superclass %s\n",
            className, class_getName(matchedHostClass));
    }
    if(object_isClass(self)) return self.guest_self = ptr;

    static std::atomic<u32> guestSetHostSelfCache{0};
    const u32 guest_setHost_self = LC32CachedGuestSelector(
        guestSetHostSelfCache, "initWithHostSelf:");
    ptr = guest_class_createInstance(ptr, 0);

    //guest_objc_performSelector(ptr, guest_setHost_self, (u32)(u64)self, (u32)((u64)self >> 32));
    {
        u32 args[] = {ptr, guest_setHost_self, (u32)(u64)self, (u32)((u64)self >> 32)};
        ptr = guest_objc_msgSend(sizeof(args)/sizeof(*args), args);
    }

    if(!ptr) return 0;

    self.guest_self = ptr;
    /*
     * Host-to-guest conversion is a borrowed (+0) operation.  Consume the
     * class_createInstance +1 as a lifetime pin owned by the native object,
     * so a callback argument or autoreleased method result cannot leave a
     * guest proxy containing a dangling host pointer.  Guest retain/release
     * calls made after conversion still create and remove paired ownership on
     * both sides through the LC32 NSObject swizzles.
     *
     * Dynamic guest classes already used this pin.  Ordinary native classes
     * need it too: NSBlockOperation convenience results exposed the missing
     * half when their host autorelease pool drained before later guest use.
     */
    LC32PinGuestObjectToHost(self, ptr, false);
    LC32OperationTraceLiveObject("guest-self-created", self, ptr);
    return ptr;
    }
}
@end

extern "C" u32 LC32GuestObjectForOwnedHostObject(CFTypeRef object) {
    if(!object) return 0;

    id hostObject = (id)object;
    u32 guestObject = 0;
    @synchronized(hostObject) {
        /*
         * -guest_self is always a borrowed conversion whose initial guest +1
         * belongs to the native lifetime pin.  A Create/Copy result carries a
         * separate native +1, so add the corresponding guest-only +1 whether
         * this call created or reused the proxy.  The public guest release
         * will later decrement both sides exactly once.
         *
         * Keep conversion and ownership transfer under the same object lock:
         * another native guest thread may otherwise change the reverse
         * mapping between those operations.
         */
        guestObject = [hostObject guest_self];
        if(guestObject) {
            LC32AdjustGuestReferenceNow(guestObject, true);
            LC32OperationTraceLiveObject(
                "owned-result-add-guest-reference",
                hostObject, guestObject);
        }
    }

    if(!guestObject) CFRelease(object);
    return guestObject;
}

static u32 LC32GuestObjectForBorrowedHostResult(id hostObject) {
    if(!hostObject) return 0;

    /*
     * The native method already supplies the autorelease lifetime required by
     * a +0 return.  The reverse-mapping lifetime pin owns the proxy's initial
     * guest reference until that native object dies.  Adding another paired
     * autorelease here duplicates the native +0 lifetime and can leave the
     * method's original autorelease-pool entry pointing at a freed object.
     */
    const u32 guestObject = [hostObject guest_self];
    LC32OperationTraceLiveObject(
        "borrowed-result", hostObject, guestObject);
    return guestObject;
}

extern "C" u32 LC32GuestObjectForOwnedHostObjectAddress(u64 object) {
    return LC32GuestObjectForOwnedHostObject(
        reinterpret_cast<CFTypeRef>(static_cast<uintptr_t>(object)));
}

static const char *LC32UnqualifiedType(const char *type) {
    while(type && *type && strchr("rnNoORVA", *type)) type++;
    return type;
}

static const char *LC32ProtocolMethodTypes(Protocol *protocol, SEL selector,
                                           BOOL instanceMethod,
                                           unsigned int depth) {
    if(!protocol || depth > 16) return nullptr;

    for(BOOL required : {YES, NO}) {
        const struct objc_method_description description =
            protocol_getMethodDescription(protocol, selector, required,
                                          instanceMethod);
        if(description.name && description.types) return description.types;
    }

    unsigned int adoptedCount = 0;
    Protocol *__unsafe_unretained *adoptedProtocols =
        protocol_copyProtocolList(protocol, &adoptedCount);
    for(unsigned int index = 0; index < adoptedCount; index++) {
        const char *types = LC32ProtocolMethodTypes(
            adoptedProtocols[index], selector, instanceMethod, depth + 1);
        if(types) {
            free(adoptedProtocols);
            return types;
        }
    }
    free(adoptedProtocols);
    return nullptr;
}

static const char *LC32ClassProtocolMethodTypes(Class cls, SEL selector,
                                                BOOL instanceMethod) {
    if(!cls) return nullptr;

    unsigned int protocolCount = 0;
    Protocol *__unsafe_unretained *protocols =
        class_copyProtocolList(cls, &protocolCount);
    for(unsigned int index = 0; index < protocolCount; index++) {
        const char *types = LC32ProtocolMethodTypes(
            protocols[index], selector, instanceMethod, 0);
        if(types) {
            free(protocols);
            return types;
        }
    }
    free(protocols);
    return nullptr;
}

static const char *LC32ClassHierarchyProtocolMethodTypes(
        Class cls, SEL selector, BOOL instanceMethod) {
    for(Class current = cls; current;
            current = class_getSuperclass(current)) {
        const char *types = LC32ClassProtocolMethodTypes(
            current, selector, instanceMethod);
        if(types) return types;
    }
    return nullptr;
}

// Protocol adoption belongs to the ordinary class, but class methods are
// installed on its metaclass. Keep the owner available while a newly
// allocated class is still unregistered and cannot yet be found by name.
static const void *LC32ProtocolOwnerClassKey =
    &LC32ProtocolOwnerClassKey;

static Class LC32ProtocolOwnerClass(Class cls) {
    if(!class_isMetaClass(cls)) return cls;

    Class owner = (Class)objc_getAssociatedObject(
        (id)cls, LC32ProtocolOwnerClassKey);
    if(owner) return owner;
    return objc_lookUpClass(class_getName(cls));
}

/*
 * A guest CGFloat is encoded as `f`, while the same public method is `d` in
 * the ARM64 UIKit ABI.  Prefer the native declaration inherited by the mirror
 * class, then a native protocol declaration adopted anywhere in its class
 * hierarchy.
 */
static const char *LC32ExpectedHostMethodTypes(Class cls, SEL selector) {
    Class superclass = class_getSuperclass(cls);
    Method inheritedMethod = superclass
        ? class_getInstanceMethod(superclass, selector)
        : nullptr;
    if(inheritedMethod) return method_getTypeEncoding(inheritedMethod);

    const BOOL instanceMethod = !class_isMetaClass(cls);
    return LC32ClassHierarchyProtocolMethodTypes(
        LC32ProtocolOwnerClass(cls), selector, instanceMethod);
}

@implementation LC32ObjCMethodResolver
+ (void)addMethod:(Method)method toClass:(Class)cls {
    class_addMethod(cls, method_getName(method), method_getImplementation(method), method_getTypeEncoding(method));
}

+ (void)addGuestIvar:(u32)guest_ivar toClass:(Class)cls {
    DynarmicHostString name(guest_ivar_getName(guest_ivar));
    DynarmicHostString typeEncoding(guest_ivar_getTypeEncoding(guest_ivar));
    const char *guestType = typeEncoding.hostPtr;
    while(*guestType && strchr("rnNoORVA", *guestType)) guestType++;
    const u32 guestOffsetPointer =
        Dynarmic_current_user_callbacks()->MemoryRead32(guest_ivar);
    const u32 guestOffset = guestOffsetPointer
        ? Dynarmic_current_user_callbacks()->MemoryRead32(guestOffsetPointer)
        : 0;

    // According to https://github.com/Quotation/LongestCocoa#longest-objective-c-property-names, the longest public property has 56 characters
    // still, we need to add an assert
    char setterName[0x50];
    char literalIvarSetterName[0x50] = {};
    assert(strlen(name.hostPtr) + 4 < sizeof(setterName));
    if(name.hostPtr[0] == '_') {
        snprintf(setterName, sizeof(setterName)-1, "_set%c%s:", toupper(name.hostPtr[1]), &name.hostPtr[2]);
        // Some older nibs archive the literal ivar name as their KVC key.
        // KVC asks for set_btnGameMode: when the key is _btnGameMode, while
        // _setBtnGameMode: above is the accessor for the logical key
        // btnGameMode. Register both spellings against the same guest ivar.
        snprintf(literalIvarSetterName, sizeof(literalIvarSetterName)-1,
                 "set%s:", name.hostPtr);
    } else {
        snprintf(setterName, sizeof(setterName)-1, "set%c%s:", toupper(name.hostPtr[0]), &name.hostPtr[1]);
    }

    char setterTypeEncoding[10];
    snprintf(setterTypeEncoding, sizeof(setterTypeEncoding)-1,
             "v@:%c", *guestType);

    IMP setterImplementation = nullptr;
    switch(*guestType) {
        case '@':
        case '#':
            setterImplementation = (IMP)&LC32SetGuestNSObjectIvar;
            break;
        case 'B':
        case 'C':
        case 'I':
        case 'L':
        case 'Q':
        case 'S':
        case 'c':
        case 'i':
        case 'l':
        case 'q':
        case 's':
            setterImplementation = (IMP)&LC32SetGuestScalarIvar;
            break;
        default:
            printf("LC32: skipping ivar %s with unhandled type %s\n", name.hostPtr, typeEncoding.hostPtr);
            break;
    }
    if(setterImplementation) {
        SEL setterSelector = sel_registerName(setterName);
        if(class_addMethod(cls, setterSelector, setterImplementation,
                           setterTypeEncoding)) {
            LC32RegisterGuestIvarAccessor(
                cls, setterSelector, name.hostPtr, guestOffset, *guestType);
        }
        if(literalIvarSetterName[0]) {
            SEL literalSetterSelector =
                sel_registerName(literalIvarSetterName);
            if(class_addMethod(cls, literalSetterSelector,
                               setterImplementation, setterTypeEncoding)) {
                LC32RegisterGuestIvarAccessor(
                    cls, literalSetterSelector, name.hostPtr,
                    guestOffset, *guestType);
            }
        }
    }

    /*
     * Mirror the setters with KVC-compliant getters.  Without them the host
     * proxy has no accessor for a guest ivar, so KVC falls into
     * valueForUndefinedKey: and raises NSUnknownKeyException.  Register both
     * the raw underscore spelling (the literal ivar name) and the
     * property-cased spelling for underscored ivars, matching how KVC probes
     * both when the key itself is underscored.
     */
    char getterName[0x50];
    char propertyGetterName[0x50] = {};
    if(name.hostPtr[0] == '_') {
        snprintf(getterName, sizeof(getterName)-1, "%s", name.hostPtr);
        snprintf(propertyGetterName, sizeof(propertyGetterName)-1,
                 "%c%s", tolower(name.hostPtr[1]), &name.hostPtr[2]);
    } else {
        snprintf(getterName, sizeof(getterName)-1, "%s", name.hostPtr);
    }

    char getterTypeEncoding[10];
    snprintf(getterTypeEncoding, sizeof(getterTypeEncoding)-1,
             "%c@:", *guestType);

    IMP getterImplementation = nullptr;
    switch(*guestType) {
        case '@':
        case '#':
            getterImplementation = (IMP)&LC32GetGuestNSObjectIvar;
            break;
        case 'B':
        case 'C':
        case 'I':
        case 'L':
        case 'Q':
        case 'S':
        case 'c':
        case 'i':
        case 'l':
        case 'q':
        case 's':
            getterImplementation = (IMP)&LC32GetGuestScalarIvar;
            break;
        default:
            break;
    }
    if(getterImplementation) {
        SEL rawGetterSelector = sel_registerName(getterName);
        if(class_addMethod(cls, rawGetterSelector, getterImplementation,
                           getterTypeEncoding)) {
            LC32RegisterGuestIvarAccessor(
                cls, rawGetterSelector, name.hostPtr,
                guestOffset, *guestType);
        }
        if(propertyGetterName[0]) {
            SEL propertyGetterSelector =
                sel_registerName(propertyGetterName);
            if(class_addMethod(cls, propertyGetterSelector,
                               getterImplementation, getterTypeEncoding)) {
                LC32RegisterGuestIvarAccessor(
                    cls, propertyGetterSelector, name.hostPtr,
                    guestOffset, *guestType);
            }
        }
    }

    // We currently don't bind setter, just leaving here for future references
    // for getter booleans, we have to register total 3 variants: name, hasName and isName, since we don't want to run a LLM here to predict which is best ¯\_(ツ)_/¯
}

+ (void)addGuestMethod:(u32)guest_method selector:(SEL)sel toClass:(Class)cls {
    objc_method_32 host_method_32;
    Dynarmic_mem_1read(guest_method, sizeof(host_method_32), (char *)&host_method_32);
    DynarmicHostString host_method_types(host_method_32.method_types);
    if(!sel) {
        DynarmicHostString host_sel(host_method_32.method_name);
        sel = sel_registerName(host_sel.hostPtr);
    }

    // The Objective-C runtime calls these lifecycle hooks as id (*)(id) and
    // void (*)(id), without a selector argument. Installing the generic
    // (id, SEL, ...) trampoline therefore interprets garbage in x1 as _cmd.
    // Guest C++ ivars belong to the guest object and are already managed by
    // the guest runtime, so forwarding would also construct/destruct twice.
    const char *selectorName = sel_getName(sel);
    if(!strcmp(selectorName, ".cxx_construct") ||
            !strcmp(selectorName, ".cxx_destruct") ||
            !strcmp(selectorName, "dealloc")) {
        return;
    }

    const char *guestMethodTypes = host_method_types.hostPtr;
    const char *installedMethodTypes = guestMethodTypes;
    const char guestReturnType = *LC32UnqualifiedType(guestMethodTypes);
    char hostReturnType = guestReturnType;
    IMP floatingImplementation = nullptr;
    if(guestReturnType == 'f' || guestReturnType == 'd') {
        const char *expectedHostTypes =
            LC32ExpectedHostMethodTypes(cls, sel);
        if(expectedHostTypes) {
            const char expectedReturnType =
                *LC32UnqualifiedType(expectedHostTypes);
            if(expectedReturnType == 'f' || expectedReturnType == 'd') {
                installedMethodTypes = expectedHostTypes;
                hostReturnType = expectedReturnType;
            }
        }

        if(guestReturnType == 'f') {
            floatingImplementation = hostReturnType == 'd'
                ? (IMP)&LC32InvokeGuestSelectorGuestFloatHostDouble
                : (IMP)&LC32InvokeGuestSelectorGuestFloatHostFloat;
        } else {
            floatingImplementation = hostReturnType == 'f'
                ? (IMP)&LC32InvokeGuestSelectorGuestDoubleHostFloat
                : (IMP)&LC32InvokeGuestSelectorGuestDoubleHostDouble;
        }
        if(hostReturnType != guestReturnType) {
            fprintf(stderr,
                "LC32: floating return ABI for %s: guest %c -> host %c\n",
                selectorName, guestReturnType, hostReturnType);
        }
    }

    IMP implementation = floatingImplementation
        ? floatingImplementation
        : (IMP)&LC32InvokeGuestSelector;
    const char *expectedHostTypes =
        LC32ExpectedHostMethodTypes(cls, sel);
    if(LC32CGSizeToCGSizeSignatureMatches(guestMethodTypes, 'f') &&
       LC32CGSizeToCGSizeSignatureMatches(expectedHostTypes, 'd')) {
        implementation =
            (IMP)&LC32InvokeGuestSelectorCGSizeToCGSize;
        installedMethodTypes = expectedHostTypes;
    }
    if(LC32PointObjectSignatureMatches(guestMethodTypes, 'f') &&
       LC32PointObjectSignatureMatches(expectedHostTypes, 'd')) {
        implementation =
            (IMP)&LC32InvokeGuestSelectorPointObject;
        installedMethodTypes = expectedHostTypes;
    }
    if(!strcmp(selectorName, "getCharacters:range:") &&
       LC32UniCharRangeSignatureMatches(guestMethodTypes, 'I')) {
        if(LC32UniCharRangeSignatureMatches(expectedHostTypes, 'Q')) {
            implementation =
                (IMP)&LC32InvokeGuestSelectorUniCharRange;
            installedMethodTypes = expectedHostTypes;
        }
    }
    if(!strcmp(selectorName, "getObjects:range:") &&
       LC32ObjectRangeSignatureMatches(guestMethodTypes, 'I') &&
       LC32ObjectRangeSignatureMatches(expectedHostTypes, 'Q')) {
        implementation =
            (IMP)&LC32InvokeGuestSelectorObjectRange;
        installedMethodTypes = expectedHostTypes;
    }
    /*
     * KVO's opaque context has the same logical register ABI on both sides,
     * and LC32HostToGuestArgument safely round-trips the zero-extended ARM32
     * token.  Install the native declaration so Foundation reflection and
     * forwarding see ARM64-sized argument offsets instead of guest metadata.
     */
    if(!strcmp(selectorName,
               "observeValueForKeyPath:ofObject:change:context:")) {
        if(expectedHostTypes) installedMethodTypes = expectedHostTypes;
    }
    if(!strcmp(selectorName,
               "countByEnumeratingWithState:objects:count:") &&
            LC32FastEnumerationSignatureMatches(guestMethodTypes) &&
            LC32FastEnumerationSignatureMatches(expectedHostTypes)) {
        implementation =
            (IMP)&LC32InvokeGuestSelectorFastEnumeration;
        installedMethodTypes = expectedHostTypes;
    }
    if(strstr(installedMethodTypes, "{CGRect=")) {
        NSMethodSignature *signature =
            [NSMethodSignature signatureWithObjCTypes:installedMethodTypes];
        if(signature.numberOfArguments == 3) {
            const char *argumentType = [signature getArgumentTypeAtIndex:2];
            while(*argumentType && strchr("rnNoORVA", *argumentType)) {
                argumentType++;
            }
            if(!strncmp(argumentType, "{CGRect=", sizeof("{CGRect=") - 1)) {
                if(floatingImplementation) {
                    if(guestReturnType == 'f') {
                        implementation = hostReturnType == 'd'
                            ? (IMP)&LC32InvokeGuestSelectorCGRectGuestFloatHostDouble
                            : (IMP)&LC32InvokeGuestSelectorCGRectGuestFloatHostFloat;
                    } else {
                        implementation = hostReturnType == 'f'
                            ? (IMP)&LC32InvokeGuestSelectorCGRectGuestDoubleHostFloat
                            : (IMP)&LC32InvokeGuestSelectorCGRectGuestDoubleHostDouble;
                    }
                } else {
                    implementation = (IMP)&LC32InvokeGuestSelectorCGRect;
                }
            }
        }
    }
    if(LC32CGRectToCGRectSignatureMatches(guestMethodTypes, 'f') &&
       LC32CGRectToCGRectSignatureMatches(expectedHostTypes, 'd')) {
        implementation =
            (IMP)&LC32InvokeGuestSelectorCGRectToCGRect;
        installedMethodTypes = expectedHostTypes;
    }
    class_addMethod(cls, sel, implementation, installedMethodTypes);
}


+ (void)addGuestProtocol:(u32)guest_protocol toClass:(Class)cls {
    DynarmicHostString host_protocolName(guest_protocol_getName(guest_protocol));
    Protocol *protocol = objc_getProtocol(host_protocolName.hostPtr);
    if(protocol) {
        class_addProtocol(cls, protocol);
    } else {
        printf("LC32: skipping nonexistent protocol %s\n", host_protocolName.hostPtr);
    }
}

+ (void)registerClass:(Class)clsObject {
    u32 count;
    u32 list;

    Class cls = object_getClass(clsObject);
    objc_setAssociatedObject((id)cls, LC32ProtocolOwnerClassKey,
                             (id)clsObject, OBJC_ASSOCIATION_ASSIGN);
    [self addMethod:class_getClassMethod(self, @selector(resolveClassMethod:)) toClass:cls];
    [self addMethod:class_getClassMethod(self, @selector(resolveInstanceMethod:)) toClass:cls];
    [cls resolveInstanceMethod:@selector(init)];
    [cls setGuestClass:YES];

    // FIXME: can't call free on copied lists
    // Register protocols
    list = guest_class_copyProtocolList([clsObject guest_self], &count);
    for(int i = 0; i < count; i++, list += sizeof(u32)) {
        [self addGuestProtocol:Dynarmic_current_user_callbacks()->MemoryRead32(list) toClass:clsObject];
    }
    //if(list) guest_free(list);

    // Register class methods. Pass metaclass (cls) here!
    list = guest_class_copyMethodList([cls guest_self], &count);
    for(int i = 0; i < count; i++, list += sizeof(u32)) {
        [self addGuestMethod:Dynarmic_current_user_callbacks()->MemoryRead32(list) selector:nil toClass:cls];
    }
    //if(list) guest_free(list);

    // Register instance methods
    list = guest_class_copyMethodList([clsObject guest_self], &count);
    for(int i = 0; i < count; i++, list += sizeof(u32)) {
        [self addGuestMethod:Dynarmic_current_user_callbacks()->MemoryRead32(list) selector:nil toClass:clsObject];
    }
    //if(list) guest_free(list);

    // Add synthetic ivar setters only after real guest methods. They are a
    // fallback for nib/KVC assignment when the binary has no setter; adding
    // them first would shadow an app's retaining property implementation.
    list = guest_class_copyIvarList([clsObject guest_self], &count);
    for(int i = 0; i < count; i++, list += sizeof(u32)) {
        [self addGuestIvar:Dynarmic_current_user_callbacks()->MemoryRead32(list) toClass:clsObject];
    }
    //if(list) guest_free(list);
}

// FIXME: currently using class_get*Method which may return superclass's method, but I guess this shouldn't affect anything
+ (BOOL)resolveClassMethod:(SEL)sel {
    printf("resolveClassMethod %s\n", sel_getName(sel));
    /*
     * Native frameworks may ask about an optional selector from one of their
     * own queues.  Such a thread has no ARM32 JIT or guest stack.  All methods
     * present when the mirrored class was registered were already installed
     * above, so safely decline this dynamic fallback instead of borrowing a
     * different guest thread's execution context.
     */
    if(!Dynarmic_guest_thread_is_registered()) {
        return [super resolveClassMethod:sel];
    }
    u32 guest_sel = guest_sel_registerName(sel_getName(sel));
    u32 guest_method = guest_class_getClassMethod(self.guest_self, guest_sel);
    if(guest_method) {
        [LC32ObjCMethodResolver addGuestMethod:guest_method selector:sel toClass:self.class];
    }
    return [super resolveClassMethod:sel];
}

+ (BOOL)resolveInstanceMethod:(SEL)sel {
    printf("resolveInstanceMethod %s\n", sel_getName(sel));
    if(!Dynarmic_guest_thread_is_registered()) {
        return [super resolveInstanceMethod:sel];
    }
    u32 guest_sel = guest_sel_registerName(sel_getName(sel));
    u32 guest_method = guest_class_getInstanceMethod(self.guest_self, guest_sel);
    if(guest_method) {
        [LC32ObjCMethodResolver addGuestMethod:guest_method selector:sel toClass:self];
    }
    return [super resolveInstanceMethod:sel];
}
@end

__attribute__((constructor)) void LC32InstallGetClassHook() {
    objc_setHook_getClass(host_hook_getClass, &host_getClass);
}

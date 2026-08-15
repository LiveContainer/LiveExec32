#import <Foundation/Foundation+LC32.h>
#import <LC32/LC32.h>

/*
 * Key-value coding is implemented by Foundation as methods on NSObject.  The
 * guest runtime only supplies NSObject's libobjc core, so generated framework
 * classes cannot inherit KVC unless the root methods are bridged explicitly.
 * Forwarding KVC to the native peer also lets host Foundation discover the
 * synthetic accessors installed for ivars on guest-defined classes.
 */
@implementation NSObject (LC32KeyValueCoding)

+ (BOOL)accessInstanceVariablesDirectly {
    static uint64_t hostSelector;
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    return (BOOL)LC32InvokeHostSelector(
        self.host_self, selector, (uint64_t)0);
}

- (id)valueForKey:(NSString *)key {
    static uint64_t hostSelector;
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    return LC32InvokeHostObjectSelector(
        self.host_self, selector, key.host_self, (uint64_t)0);
}

- (id)valueForKeyPath:(NSString *)keyPath {
    static uint64_t hostSelector;
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    return LC32InvokeHostObjectSelector(
        self.host_self, selector, keyPath.host_self, (uint64_t)0);
}

- (void)setValue:(id)value forKey:(NSString *)key {
    static uint64_t hostSelector;
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    LC32InvokeHostSelector(self.host_self, selector,
                           [(NSObject *)value host_self], key.host_self,
                           (uint64_t)0);
}

- (void)setValue:(id)value forKeyPath:(NSString *)keyPath {
    static uint64_t hostSelector;
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    LC32InvokeHostSelector(self.host_self, selector,
                           [(NSObject *)value host_self], keyPath.host_self,
                           (uint64_t)0);
}

- (NSDictionary *)dictionaryWithValuesForKeys:(NSArray<NSString *> *)keys {
    static uint64_t hostSelector;
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    return LC32InvokeHostObjectSelector(
        self.host_self, selector, keys.host_self, (uint64_t)0);
}

- (void)setValuesForKeysWithDictionary:(NSDictionary<NSString *, id> *)values {
    static uint64_t hostSelector;
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    LC32InvokeHostSelector(self.host_self, selector,
                           values.host_self, (uint64_t)0);
}

- (id)valueForUndefinedKey:(NSString *)key {
    static uint64_t hostSelector;
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    return LC32InvokeHostObjectSelector(
        self.host_self, selector, key.host_self, (uint64_t)0);
}

- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
    static uint64_t hostSelector;
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    LC32InvokeHostSelector(self.host_self, selector,
                           [(NSObject *)value host_self], key.host_self,
                           (uint64_t)0);
}

- (void)setNilValueForKey:(NSString *)key {
    static uint64_t hostSelector;
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    LC32InvokeHostSelector(self.host_self, selector,
                           key.host_self, (uint64_t)0);
}

@end

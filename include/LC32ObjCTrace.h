#ifndef LC32_OBJC_TRACE_H
#define LC32_OBJC_TRACE_H

// Independent of host debug logging; opt in when building guest frameworks.
#ifndef LC32_OBJC_TRACE
#define LC32_OBJC_TRACE 0
#endif

// Keep generated and handwritten call sites constant-foldable, even without
// optimization. Disabled tracing must not evaluate class/selector log arguments.
#define LC32ObjCTraceEnabled() (LC32_OBJC_TRACE != 0)

#endif

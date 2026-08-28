#ifndef LC32_HELP_UI_H
#define LC32_HELP_UI_H

#ifdef __cplusplus
extern "C" {
#endif

/** Enters UIApplicationMain for the standalone LiveExec32 help interface. */
__attribute__((visibility("default")))
int LC32RunHelpUI(int argc, char *argv[]);

#ifdef __cplusplus
}
#endif

#endif

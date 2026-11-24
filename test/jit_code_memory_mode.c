#define main LC32LauncherMain
#define dyld_get_active_platform LC32TestActivePlatform
#include "../App/main.c"
#undef main

static uint32_t platform;
uint32_t LC32TestActivePlatform(void) { return platform; }

static unsigned failures;
static void check(uint32_t activePlatform, const char *setting,
                  const char *expected) {
    platform = activePlatform;
    if(setting) setenv("DYNARMIC_DUAL_MAPPED", setting, 1);
    else unsetenv("DYNARMIC_DUAL_MAPPED");
    ConfigureDynarmicCodeMemoryMode();
    const char *actual = getenv("DYNARMIC_DUAL_MAPPED");
    bool passed = expected ? actual && strcmp(actual, expected) == 0
                           : actual == NULL;
    printf("jit-code-memory platform=%u setting=%s expected=%s: %s\n",
        activePlatform, setting ? setting : "unset",
        expected ? expected : "unset", passed ? "PASS" : "FAIL");
    failures += !passed;
}

int main(void) {
    const uint32_t platforms[] = {
        PLATFORM_MACOS, PLATFORM_IOS, PLATFORM_MACCATALYST, PLATFORM_IOSSIMULATOR
    };
    for(unsigned i = 0; i < sizeof(platforms) / sizeof(platforms[0]); ++i) {
        bool automatic = platforms[i] == PLATFORM_IOSSIMULATOR;
#ifdef LC32_JAILBREAK_PACKAGE
        automatic |= platforms[i] == PLATFORM_IOS;
#endif
        check(platforms[i], NULL, automatic ? "1" : NULL);
        check(platforms[i], "0", "0");
        check(platforms[i], "1", "1");
        check(platforms[i], "", "");
    }
    return failures != 0;
}

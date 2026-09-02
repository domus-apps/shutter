import AppKit

/* Flips the system appearance between Light and Dark.

   Primary path: SkyLight's SLSSetAppearanceThemeLegacy — the call System
   Settings itself lands on. Instant, animated by the system, and needs no
   permission. It is private API, so both symbols are resolved at runtime
   and their absence downgrades gracefully to the scripted path below
   instead of failing to link.

   Fallback: AppleEvents to System Events (the documented route every
   appearance utility used for years). Slower and gated behind a one-time
   Automation prompt, but immune to private-API churn. */
enum AppearanceSwitcher {
    private typealias GetThemeFunction = @convention(c) () -> Bool
    private typealias SetThemeFunction = @convention(c) (Bool) -> Void

    private static let skyLight:
        (isDark: GetThemeFunction, setDark: SetThemeFunction)? = {
            guard
                let handle = dlopen(
                    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                    RTLD_LAZY),
                let getSymbol = dlsym(handle, "SLSGetAppearanceThemeLegacy"),
                let setSymbol = dlsym(handle, "SLSSetAppearanceThemeLegacy")
            else { return nil }
            return (
                unsafeBitCast(getSymbol, to: GetThemeFunction.self),
                unsafeBitCast(setSymbol, to: SetThemeFunction.self)
            )
        }()

    static var isDark: Bool {
        if let skyLight { return skyLight.isDark() }
        /* The global default is only written for Dark; absence means Light. */
        return UserDefaults.standard.persistentDomain(
            forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String
            == "Dark"
    }

    static func toggle() {
        setDark(!isDark)
    }

    static func setDark(_ dark: Bool) {
        if let skyLight {
            skyLight.setDark(dark)
            return
        }
        /* NSAppleScript is main-thread-only. The first run raises the
           Automation consent prompt for System Events. */
        let source = """
            tell application "System Events" to tell appearance preferences \
            to set dark mode to \(dark)
            """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            NSLog("Shutter: appearance change via System Events failed: \(error)")
        }
    }
}

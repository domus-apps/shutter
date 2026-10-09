import AppKit

/* Follows the ambient light while the setting is on: reads the sensor every
   couple of seconds, lets AmbientTracker decide, and flips the appearance
   when the light settles into a new zone. Reads stop while the lid is
   closed, the displays sleep, or the Mac sleeps. */
final class AutoAppearance {
    /// Posted after every reading, for the live marker in Settings.
    static let readingChanged = Notification.Name("Shutter.AmbientReadingChanged")

    /// The latest reading; nil while the sensor isn't being read.
    private(set) var lux: Double?

    private var tracker = AmbientTracker(darkBelow: AppPreferences.darkBelowLux)
    private var timer: Timer?
    private var isAsleep = false
    private var wasOn = AppPreferences.followsAmbientLight

    init() {
        NotificationCenter.default.addObserver(
            forName: AppPreferences.changed, object: nil, queue: .main
        ) { [weak self] _ in
            self?.preferencesChanged()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.isAsleep = true
                self?.update()
            }
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.isAsleep = false
                self?.update()
            }
        }
        update()
    }

    private func preferencesChanged() {
        /* Turning the feature on or moving the slider starts a fresh count,
           so the new setting takes effect within seconds. */
        let isOn = AppPreferences.followsAmbientLight
        let darkBelow = AppPreferences.darkBelowLux
        if darkBelow != tracker.darkBelow || (isOn && !wasOn) {
            tracker = AmbientTracker(darkBelow: darkBelow)
        }
        wasOn = isOn
        update()
    }

    private func update() {
        let wantsReadings = AppPreferences.followsAmbientLight && AmbientLight.isAvailable && !isAsleep
        if wantsReadings, timer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                self?.read()
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            read()
        } else if !wantsReadings, let timer {
            timer.invalidate()
            self.timer = nil
            tracker.interrupt()
            setLux(nil)
        }
    }

    private func read() {
        guard let lux = AmbientLight.lux() else {
            tracker.interrupt()
            setLux(nil)
            return
        }
        setLux(lux)
        guard let zone = tracker.feed(lux: lux, at: Date()) else { return }
        let dark = zone == .dark
        if AppearanceSwitcher.isDark != dark {
            AppearanceSwitcher.setDark(dark)
        }
    }

    private func setLux(_ lux: Double?) {
        guard lux != self.lux else { return }
        self.lux = lux
        NotificationCenter.default.post(name: Self.readingChanged, object: self)
    }
}

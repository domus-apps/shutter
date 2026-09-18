import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let hotKeys = HotKeyCenter()
    private let updater = UpdaterController()
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        /* A translocated launch relaunches itself from the real bundle —
           nothing else must start in this doomed instance. */
        if TranslocationHealer.healIfNeeded() { return }

        setUpMainMenu()
        updateStatusItemVisibility()
        registerToggleHotKey()

        NotificationCenter.default.addObserver(
            forName: AppPreferences.changed, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateStatusItemVisibility()
        }
        NotificationCenter.default.addObserver(
            forName: ToggleShortcutStore.changed, object: nil, queue: .main
        ) { [weak self] _ in
            self?.registerToggleHotKey()
        }
        /* Release the hotkey while the settings recorder is capturing, or it
           would swallow the very combination being recorded. */
        NotificationCenter.default.addObserver(
            forName: .shortcutRecordingBegan, object: nil, queue: .main
        ) { [weak self] _ in
            self?.hotKeys.unregisterAll()
        }
        NotificationCenter.default.addObserver(
            forName: .shortcutRecordingEnded, object: nil, queue: .main
        ) { [weak self] _ in
            self?.registerToggleHotKey()
        }
        /* Whoever flips the appearance — Shutter, System Settings, the
           scheduled Auto switch — the icon follows. */
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateStatusIcon()
        }

        if CommandLine.arguments.contains("--settings") {
            openSettings()
        }
    }

    private func registerToggleHotKey() {
        hotKeys.unregisterAll()
        let spec = ToggleShortcutStore.spec
        hotKeys.register(keyCode: spec.keyCode, modifiers: spec.carbonModifiers) {
            AppearanceSwitcher.toggle()
        }
    }

    /* Launching the app again while it's already running sends "reopen" to
       the live instance. With the menu bar icon hidden this is the only way
       back into the UI, so surface Settings (which also puts the app in the
       Dock via updateActivationPolicy). */
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows: Bool
    ) -> Bool {
        if AppPreferences.isMenuBarIconHidden {
            openSettings()
        }
        return false
    }

    // MARK: - Status item

    private func updateStatusItemVisibility() {
        if AppPreferences.isMenuBarIconHidden {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
        } else if statusItem == nil {
            setUpStatusItem()
        }
        updateActivationPolicy()
    }

    private func setUpStatusItem() {
        /* A fixed length instead of squareLength: square items are as wide
           as the menu bar is tall, which pads a ~18pt symbol with a lot of
           dead space. 20pt hugs the icon while keeping its natural size. */
        let item = NSStatusBar.system.statusItem(withLength: 20)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        /* Left click toggles, right click opens the menu — the standard
           idiom for toggle-style menu bar apps (same as Pharos). */
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        updateStatusIcon()
    }

    /* Not an SF Symbol on purpose: a sun collides with Transom's menu bar
       icon and a moon with the system Focus indicator. The app icon's own
       glyph — two shutter leaves — is unique in the bar, and the filled
       leaf points at the current mode (left/day or right/night). */
    private func updateStatusIcon() {
        let dark = AppearanceSwitcher.isDark
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            func leaf(x: CGFloat, filled: Bool) {
                let rect = NSRect(x: x, y: 2, width: 6.2, height: 14)
                let path = NSBezierPath(roundedRect: filled ? rect : rect.insetBy(dx: 0.65, dy: 0.65), xRadius: 2.4, yRadius: 2.4)
                if filled {
                    NSColor.black.setFill()
                    path.fill()
                } else {
                    NSColor.black.setStroke()
                    path.lineWidth = 1.3
                    path.stroke()
                }
            }
            leaf(x: 2.2, filled: !dark)
            leaf(x: 9.6, filled: dark)
            return true
        }
        image.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = dark
            ? L("Shutter — Dark Mode is on") : L("Shutter — Light Mode is on")
        statusItem?.button?.setAccessibilityLabel(
            dark ? L("Shutter — Dark Mode is on") : L("Shutter — Light Mode is on"))
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event.map {
            $0.type == .rightMouseUp || $0.modifierFlags.contains(.control)
        } ?? true
        if wantsMenu {
            showStatusMenu()
        } else {
            AppearanceSwitcher.toggle()
        }
    }

    /* The menu is attached only for the duration of one tracking session:
       a permanently-assigned menu would swallow left clicks, killing the
       click-to-toggle behavior. Built fresh each time so the toggle title
       matches the current appearance. */
    private func showStatusMenu() {
        guard let item = statusItem else { return }

        let menu = NSMenu()
        menu.delegate = self

        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let about = NSMenuItem(title: "Shutter \(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: AppearanceSwitcher.isDark
                ? L("Switch to Light Mode") : L("Switch to Dark Mode"),
            action: #selector(toggleAppearance), keyEquivalent: "")
        toggle.target = self
        /* Purely informative: the global hotkey does the real work. */
        let equivalent = ToggleShortcutStore.spec.menuKeyEquivalent
        toggle.keyEquivalent = equivalent.key
        toggle.keyEquivalentModifierMask = equivalent.modifiers
        menu.addItem(toggle)
        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: L("Settings…"), action: #selector(openSettingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(updater.makeMenuItem())
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: L("Quit Shutter"),
                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        item.button?.performClick(nil)
    }

    /* Detach after the tracking session so the next left click reaches
       statusItemClicked instead of reopening the menu. */
    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }

    @objc private func toggleAppearance() {
        AppearanceSwitcher.toggle()
    }

    // MARK: - Menus & windows

    /* An accessory app has no visible menu bar, but ⌘-key equivalents are
       still dispatched through the main menu — without one, ⌘W/⌘Q do
       nothing in the settings window. The menu also becomes visible for
       real whenever the app temporarily joins the Dock (regular policy). */
    private func setUpMainMenu() {
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: L("Settings…"), action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(updater.makeMenuItem())
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: L("Quit Shutter"),
                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let windowMenu = NSMenu(title: L("Window"))
        windowMenu.addItem(
            NSMenuItem(
                title: L("Close Window"),
                action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(
            NSMenuItem(
                title: L("Minimize"),
                action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))

        let mainMenu = NSMenu()
        for submenu in [appMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        NSApp.mainMenu = mainMenu
    }

    private var isSettingsWindowVisible: Bool {
        settingsWindowController?.window?.isVisible == true
    }

    /* Activation hand-back. An accessory app that activates itself to show
       a window stays the active app after that window closes — macOS never
       moves activation on window close — so a windowless Shutter would be left
       frontmost until the user clicked elsewhere. Anything keyed off the
       frontmost app then misbehaves (Atrium's Option+` lists the front app's
       windows and finds none; plain keys beep). Remember who was active
       before we came forward and give activation back once our last window
       is gone. */
    private var previouslyActiveApp: NSRunningApplication?

    private func comeForward() {
        if !NSApp.isActive,
            let front = NSWorkspace.shared.frontmostApplication,
            front.processIdentifier != ProcessInfo.processInfo.processIdentifier
        {
            previouslyActiveApp = front
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handBackActivationIfWindowless() {
        guard NSApp.isActive, settingsWindowController?.window?.isVisible != true
        else { return }
        let previous = previouslyActiveApp
        previouslyActiveApp = nil
        if let previous, !previous.isTerminated,
            previous.activate(from: .current, options: [])
        {
            return
        }
        /* No one to hand back to (quit meanwhile): hiding yields activation
           to whatever the system picks next. */
        NSApp.hide(nil)
    }

    private func observeClose(of window: NSWindow?) {
        guard let window else { return }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            /* isVisible is still true inside willClose; re-evaluate (leave the Dock, hand
               activation back) on the next runloop cycle. */
            DispatchQueue.main.async {
                self?.updateActivationPolicy()
                self?.handBackActivationIfWindowless()
            }
        }
    }

    /* Dock presence: the app normally stays invisible (accessory policy),
       but while the menu bar icon is hidden AND Settings is open there would
       be no sign the app is running — so it joins the Dock for the duration
       and leaves again when the settings window closes. */
    private func updateActivationPolicy() {
        let wantsDock = AppPreferences.isMenuBarIconHidden && isSettingsWindowVisible
        let policy: NSApplication.ActivationPolicy = wantsDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        /* Flipping the policy can drop activation; keep Settings in front.
           Going back to accessory has to wait: macOS 27.2 (measured
           2026-09-18) leaves the window undraggable by its title bar until
           the app goes through a real activation, and the deactivation the
           flip causes lands asynchronously — re-activating right away (even
           on the next run-loop turn or on didResignActive, ~10 ms) is a
           no-op that leaves the window stuck; 50 ms was borderline, 0.2 s
           and up always worked. Going to regular has no such problem. */
        guard isSettingsWindowVisible else { return }
        if policy == .regular {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, isSettingsWindowVisible else { return }
                NSApp.activate(ignoringOtherApps: true)
                settingsWindowController?.window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(updater: updater)
            observeClose(of: settingsWindowController?.window)
        }
        /* Accessory apps don't come forward on their own — activate first or
           the window opens behind the current app. */
        comeForward()
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        updateActivationPolicy()
    }
}

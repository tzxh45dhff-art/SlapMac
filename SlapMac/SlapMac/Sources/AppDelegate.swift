import Cocoa
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var countLabel: NSTextField!
    private var sensorStatusLabel: NSTextField!
    private var statusItem: NSStatusItem?
    private var slapDetector: SlapDetector?
    private var usbMonitor: USBMonitor?
    private var updaterController: SPUStandardUpdaterController!

    private var slapCount: Int {
        get { UserDefaults.standard.integer(forKey: "slapCount") }
        set { UserDefaults.standard.set(newValue, forKey: "slapCount") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        buildMainMenu()
        NSApp.setActivationPolicy(.regular)
        buildWindow()
        buildStatusItem()

        // Force activation after the run loop processes the window
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window.makeKeyAndOrderFront(nil)
            self?.window.orderFrontRegardless()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startDetectors()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        slapDetector?.stop()
    }

    // MARK: - Main Menu (required when there's no storyboard/xib)

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About SlapMac", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updaterController
        appMenu.addItem(updateItem)
        
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit SlapMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Window
    private var sensitivitySlider: NSSlider!
    private var sensitivityValueLabel: NSTextField!
    private var cooldownSlider: NSSlider!
    private var cooldownValueLabel: NSTextField!

    private func buildWindow() {
        let contentRect = NSRect(x: 0, y: 0, width: 420, height: 380)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SlapMac"
        window.isReleasedWhenClosed = false
        window.center()

        let contentView = NSView(frame: contentRect)

        // — Title
        let titleLabel = NSTextField(labelWithString: "👋 SlapMac")
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 20, y: 340, width: 380, height: 30)

        // — Sensor status
        sensorStatusLabel = NSTextField(labelWithString: "Checking accelerometer...")
        sensorStatusLabel.font = .systemFont(ofSize: 12, weight: .regular)
        sensorStatusLabel.alignment = .center
        sensorStatusLabel.textColor = .secondaryLabelColor
        sensorStatusLabel.frame = NSRect(x: 20, y: 318, width: 380, height: 18)

        // — Counter
        countLabel = NSTextField(labelWithString: "Total slaps: \(slapCount)")
        countLabel.font = .systemFont(ofSize: 18, weight: .medium)
        countLabel.alignment = .center
        countLabel.frame = NSRect(x: 20, y: 282, width: 380, height: 26)

        let hintLabel = NSTextField(labelWithString: "Slap your MacBook to trigger a sound!")
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .center
        hintLabel.frame = NSRect(x: 20, y: 262, width: 380, height: 18)

        // ── Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.frame = NSRect(x: 20, y: 250, width: 380, height: 1)

        // ── Sensitivity (threshold) slider ──
        // Lower threshold = MORE sensitive (easier to trigger)
        let savedThreshold = UserDefaults.standard.double(forKey: "slapThreshold")
        let thresholdValue = savedThreshold > 0 ? savedThreshold : 0.6

        let sensLabel = NSTextField(labelWithString: "Sensitivity")
        sensLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        sensLabel.frame = NSRect(x: 20, y: 218, width: 100, height: 20)

        sensitivitySlider = NSSlider(value: thresholdValue, minValue: 0.2, maxValue: 3.0,
                                     target: self, action: #selector(sensitivityChanged(_:)))
        sensitivitySlider.frame = NSRect(x: 120, y: 218, width: 200, height: 20)

        sensitivityValueLabel = NSTextField(labelWithString: String(format: "%.1fg", thresholdValue))
        sensitivityValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sensitivityValueLabel.alignment = .right
        sensitivityValueLabel.frame = NSRect(x: 325, y: 218, width: 70, height: 20)

        let sensHint = NSTextField(labelWithString: "← More sensitive        Less sensitive →")
        sensHint.font = .systemFont(ofSize: 9)
        sensHint.textColor = .tertiaryLabelColor
        sensHint.alignment = .center
        sensHint.frame = NSRect(x: 120, y: 200, width: 200, height: 14)

        // ── Cooldown slider ──
        let savedCooldown = UserDefaults.standard.double(forKey: "slapCooldown")
        let cooldownValue = savedCooldown > 0 ? savedCooldown : 0.4

        let cdLabel = NSTextField(labelWithString: "Cooldown")
        cdLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        cdLabel.frame = NSRect(x: 20, y: 168, width: 100, height: 20)

        cooldownSlider = NSSlider(value: cooldownValue, minValue: 0.1, maxValue: 2.0,
                                  target: self, action: #selector(cooldownChanged(_:)))
        cooldownSlider.frame = NSRect(x: 120, y: 168, width: 200, height: 20)

        cooldownValueLabel = NSTextField(labelWithString: String(format: "%.1fs", cooldownValue))
        cooldownValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        cooldownValueLabel.alignment = .right
        cooldownValueLabel.frame = NSRect(x: 325, y: 168, width: 70, height: 20)

        let cdHint = NSTextField(labelWithString: "← Faster repeat        Slower repeat →")
        cdHint.font = .systemFont(ofSize: 9)
        cdHint.textColor = .tertiaryLabelColor
        cdHint.alignment = .center
        cdHint.frame = NSRect(x: 120, y: 150, width: 200, height: 14)

        // ── Separator 2
        let separator2 = NSBox()
        separator2.boxType = .separator
        separator2.frame = NSRect(x: 20, y: 130, width: 380, height: 1)

        // ── Buttons
        let slapButton = NSButton(title: "Test Slap Sound", target: self, action: #selector(testSlapSound))
        slapButton.frame = NSRect(x: 30, y: 80, width: 170, height: 34)

        let usbButton = NSButton(title: "Test USB Sound", target: self, action: #selector(testUSBSound))
        usbButton.frame = NSRect(x: 220, y: 80, width: 170, height: 34)

        let resetButton = NSButton(title: "Reset Counter", target: self, action: #selector(resetCounter))
        resetButton.frame = NSRect(x: 30, y: 38, width: 170, height: 30)

        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quitApp))
        quitButton.frame = NSRect(x: 220, y: 38, width: 170, height: 30)

        contentView.addSubview(titleLabel)
        contentView.addSubview(sensorStatusLabel)
        contentView.addSubview(countLabel)
        contentView.addSubview(hintLabel)
        contentView.addSubview(separator)
        contentView.addSubview(sensLabel)
        contentView.addSubview(sensitivitySlider)
        contentView.addSubview(sensitivityValueLabel)
        contentView.addSubview(sensHint)
        contentView.addSubview(cdLabel)
        contentView.addSubview(cooldownSlider)
        contentView.addSubview(cooldownValueLabel)
        contentView.addSubview(cdHint)
        contentView.addSubview(separator2)
        contentView.addSubview(slapButton)
        contentView.addSubview(usbButton)
        contentView.addSubview(resetButton)
        contentView.addSubview(quitButton)

        window.contentView = contentView
        self.window = window
    }

    @objc private func sensitivityChanged(_ sender: NSSlider) {
        let value = sender.doubleValue
        sensitivityValueLabel.stringValue = String(format: "%.1fg", value)
        slapDetector?.threshold = value
        UserDefaults.standard.set(value, forKey: "slapThreshold")
    }

    @objc private func cooldownChanged(_ sender: NSSlider) {
        let value = sender.doubleValue
        cooldownValueLabel.stringValue = String(format: "%.1fs", value)
        slapDetector?.cooldown = value
        UserDefaults.standard.set(value, forKey: "slapCooldown")
    }

    // MARK: - Menu Bar Status Item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "hand.raised.fill",
                accessibilityDescription: "SlapMac"
            )
            button.title = " \(slapCount)"
            button.imagePosition = .imageLeft
            button.toolTip = "SlapMac \(slapCount)"
        }

        let menu = NSMenu()
        let countItem = NSMenuItem(title: "Total slaps: \(slapCount)", action: nil, keyEquivalent: "")
        countItem.tag = 1
        menu.addItem(countItem)
        menu.addItem(.separator())

        let testSlapItem = NSMenuItem(title: "Test Slap Sound", action: #selector(testSlapSound), keyEquivalent: "t")
        testSlapItem.target = self
        menu.addItem(testSlapItem)

        let testUSBItem = NSMenuItem(title: "Test USB Sound", action: #selector(testUSBSound), keyEquivalent: "u")
        testUSBItem.target = self
        menu.addItem(testUSBItem)

        let showWindowItem = NSMenuItem(title: "Show Window", action: #selector(showWindow), keyEquivalent: "s")
        showWindowItem.target = self
        menu.addItem(showWindowItem)

        menu.addItem(.separator())

        let resetItem = NSMenuItem(title: "Reset Counter", action: #selector(resetCounter), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)

        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updaterController
        menu.addItem(updateItem)

        let quitItem = NSMenuItem(title: "Quit SlapMac", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    // MARK: - Detectors

    private func startDetectors() {
        // Check if accelerometer is available
        if SlapDetector.isAvailable() {
            sensorStatusLabel?.stringValue = "✅ Accelerometer detected — listening for slaps"
            sensorStatusLabel?.textColor = .systemGreen
        } else {
            sensorStatusLabel?.stringValue = "⚠️ No accelerometer found — try running with sudo"
            sensorStatusLabel?.textColor = .systemOrange
        }

        slapDetector = SlapDetector { [weak self] intensity in
            DispatchQueue.main.async {
                self?.handleSlap(intensity: intensity)
            }
        }

        // Apply saved settings
        let savedThreshold = UserDefaults.standard.double(forKey: "slapThreshold")
        if savedThreshold > 0 { slapDetector?.threshold = savedThreshold }
        let savedCooldown = UserDefaults.standard.double(forKey: "slapCooldown")
        if savedCooldown > 0 { slapDetector?.cooldown = savedCooldown }

        slapDetector?.start()

        usbMonitor = USBMonitor { [weak self] connected in
            DispatchQueue.main.async {
                self?.handleUSB(connected: connected)
            }
        }
        usbMonitor?.start()
    }

    private func refreshUI() {
        countLabel?.stringValue = "Total slaps: \(slapCount)"
        statusItem?.button?.title = " \(slapCount)"
        statusItem?.button?.toolTip = "SlapMac \(slapCount)"
        statusItem?.menu?.item(withTag: 1)?.title = "Total slaps: \(slapCount)"
    }

    private func handleSlap(intensity: Double) {
        slapCount += 1
        refreshUI()
        SoundManager.shared.playSlap(intensity: intensity)
    }

    private func handleUSB(connected: Bool) {
        SoundManager.shared.playUSB(connected: connected)
    }

    @objc
    private func testSlapSound() {
        handleSlap(intensity: 0.75)
    }

    @objc
    private func testUSBSound() {
        handleUSB(connected: true)
    }

    @objc
    private func resetCounter() {
        slapCount = 0
        refreshUI()
    }

    @objc
    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}

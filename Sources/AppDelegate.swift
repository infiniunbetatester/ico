import AppKit
import UserNotifications

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var updateMenuItem: NSMenuItem?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let icon = Bundle.main.image(forResource: "AppIcon") ?? NSImage(contentsOfFile: "Resources/AppIcon.png") {
            NSApp.applicationIconImage = icon
        }
        setupStatusBar()
        NotchWindowController.shared.setup()
        IslandTouchBarController.shared.setup()
        NSApp.touchBar = IslandTouchBarController.shared.touchBar
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        
        UpdateChecker.shared.onUpdateFound = { [weak self] version, _ in
            self?.updateMenuItem?.title = "⚡ Скачать ICO \(version)..."
        }
        
        // Auto check for GitHub releases in background
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            UpdateChecker.shared.checkForUpdates(notifyIfUpToDate: false)
        }
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: "ICO")
            button.image?.isTemplate = true
        }
        
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "ICO — Dynamic Notch", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let toggleItem = NSMenuItem(title: "Раскрыть / Свернуть челку", action: #selector(toggleIsland), keyEquivalent: "d")
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        // Compact styles submenu
        let styleMenuItem = NSMenuItem(title: "Стиль свернутой челки", action: nil, keyEquivalent: "")
        let styleSubmenu = NSMenu()
        
        let styleStandard = NSMenuItem(title: "Компактная (24px)", action: #selector(setStyleStandard), keyEquivalent: "")
        styleStandard.target = self
        styleSubmenu.addItem(styleStandard)
        
        let styleMinimal = NSMenuItem(title: "Тонкая полоска (6px)", action: #selector(setStyleMinimal), keyEquivalent: "")
        styleMinimal.target = self
        styleSubmenu.addItem(styleMinimal)
        
        let styleHidden = NSMenuItem(title: "Невидимая (0px, только трей)", action: #selector(setStyleHidden), keyEquivalent: "")
        styleHidden.target = self
        styleSubmenu.addItem(styleHidden)
        
        styleMenuItem.submenu = styleSubmenu
        menu.addItem(styleMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let updateItem = NSMenuItem(title: "Проверить обновления...", action: #selector(checkUpdates), keyEquivalent: "u")
        updateItem.target = self
        menu.addItem(updateItem)
        self.updateMenuItem = updateItem
        
        let recenterItem = NSMenuItem(title: "Центрировать на экране", action: #selector(recenter), keyEquivalent: "r")
        recenterItem.target = self
        menu.addItem(recenterItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Выйти", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func checkUpdates() {
        if UpdateChecker.shared.hasAvailableUpdate {
            UpdateChecker.shared.openDownloadPage()
        } else {
            UpdateChecker.shared.checkForUpdates(notifyIfUpToDate: true)
        }
    }
    
    @objc private func toggleIsland() {
        let state = IslandState.shared
        if state.view == .open {
            state.collapse()
        } else {
            state.setView(.open)
        }
    }
    
    @objc private func setStyleStandard() {
        IslandState.shared.setCompactStyle(.standard)
    }
    
    @objc private func setStyleMinimal() {
        IslandState.shared.setCompactStyle(.minimal)
    }
    
    @objc private func setStyleHidden() {
        IslandState.shared.setCompactStyle(.hidden)
    }
    
    @objc private func recenter() {
        NotchWindowController.shared.recenterOnCurrentScreen()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

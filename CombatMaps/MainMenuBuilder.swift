import AppKit

enum MainMenuBuilder {
    static func build() -> NSMenu {
        let menu = NSMenu(title: "CombatMaps")

        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu(title: "CombatMaps")
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About CombatMaps", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit CombatMaps", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem()
        menu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "Open", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")

        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = RecentDocumentsMenuController.shared.menu
        recentItem.submenu = recentMenu
        fileMenu.addItem(recentItem)

        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let areaItem = NSMenuItem()
        menu.addItem(areaItem)
        let areaMenu = NSMenu(title: "Area of Effect")
        areaItem.submenu = areaMenu
        areaMenu.addItem(withTitle: "Line", action: #selector(AppDelegate.addLineOverlay(_:)), keyEquivalent: "")
        areaMenu.addItem(withTitle: "Circle", action: #selector(AppDelegate.addCircleOverlay(_:)), keyEquivalent: "")
        areaMenu.addItem(withTitle: "Rectangle", action: #selector(AppDelegate.addRectangleOverlay(_:)), keyEquivalent: "")
        areaMenu.addItem(withTitle: "Cone", action: #selector(AppDelegate.addConeOverlay(_:)), keyEquivalent: "")
        areaMenu.addItem(.separator())
        areaMenu.addItem(withTitle: "Color", action: #selector(AppDelegate.chooseOverlayColor(_:)), keyEquivalent: "")

        let windowItem = NSMenuItem()
        menu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        NSApp.windowsMenu = windowMenu

        let displayItem = NSMenuItem()
        menu.addItem(displayItem)
        displayItem.submenu = DisplayMenuController.shared.menu

        return menu
    }
}

final class DisplayMenuController: NSObject, NSMenuDelegate {
    static let shared = DisplayMenuController()
    let menu = NSMenu(title: "Display")

    private override init() {
        super.init()
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        for (index, screen) in NSScreen.screens.enumerated() {
            let item = NSMenuItem(title: displayName(for: screen, index: index), action: #selector(moveDocumentsToDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = screen
            menu.addItem(item)
        }

        if NSScreen.screens.isEmpty {
            let item = NSMenuItem(title: "No Displays", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    @objc private func moveDocumentsToDisplay(_ sender: NSMenuItem) {
        guard let screen = sender.representedObject as? NSScreen else { return }
        for document in NSDocumentController.shared.documents {
            for controller in document.windowControllers {
                (controller as? MapWindowController)?.moveToScreen(screen)
            }
        }
    }

    private func displayName(for screen: NSScreen, index: Int) -> String {
        let name = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
        if screen == NSScreen.main {
            return "\(name) (Main)"
        }
        return name
    }
}

import AppKit

enum MainMenuBuilder {
    static func build() -> NSMenu {
        let menu = NSMenu(title: "CombatMaps")

        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu(title: "CombatMaps")
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About CombatMaps", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
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

        let windowItem = NSMenuItem()
        menu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        NSApp.windowsMenu = windowMenu

        return menu
    }
}

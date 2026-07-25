import AppKit

enum MainMenuBuilder {
    static func build() -> NSMenu {
        let menu = NSMenu(title: "CombatMaps")

        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu(title: "CombatMaps")
        appItem.submenu = appMenu
        let aboutItem = appMenu.addItem(withTitle: "About CombatMaps", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        aboutItem.target = NSApp.delegate
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide CombatMaps", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h").target = NSApp
        let hideOthersItem = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.target = NSApp
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "").target = NSApp
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit CombatMaps", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp

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
        areaMenu.addItem(withTitle: "Oval", action: #selector(AppDelegate.addOvalOverlay(_:)), keyEquivalent: "")
        areaMenu.addItem(withTitle: "Rectangle", action: #selector(AppDelegate.addRectangleOverlay(_:)), keyEquivalent: "")
        areaMenu.addItem(withTitle: "Cone", action: #selector(AppDelegate.addConeOverlay(_:)), keyEquivalent: "")
        areaMenu.addItem(.separator())
        areaMenu.addItem(withTitle: "Color", action: #selector(AppDelegate.chooseOverlayColor(_:)), keyEquivalent: "")

        let mapViewItem = NSMenuItem()
        menu.addItem(mapViewItem)
        mapViewItem.submenu = MapViewMenuController.shared.menu

        let displayItem = NSMenuItem()
        menu.addItem(displayItem)
        displayItem.submenu = DisplayMenuController.shared.menu

        return menu
    }
}

final class MapViewMenuController: NSObject, NSMenuDelegate {
    static let shared = MapViewMenuController()
    let menu = NSMenu(title: "Map View")

    private override init() {
        super.init()
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let zoomItem = NSMenuItem(title: "Zoom", action: nil, keyEquivalent: "")
        zoomItem.submenu = zoomMenu()
        menu.addItem(zoomItem)

        let rotateItem = NSMenuItem(title: "Rotate Map", action: nil, keyEquivalent: "")
        rotateItem.submenu = rotateMenu()
        menu.addItem(rotateItem)

        let fogItem = NSMenuItem(title: "Fog of War", action: #selector(toggleFogOfWar(_:)), keyEquivalent: "f")
        fogItem.target = self
        if activeCanvasView()?.isFogOfWarVisible == true {
            fogItem.state = .on
        }
        menu.addItem(fogItem)

        let fogShapeItem = NSMenuItem(title: "Toggle Fog of War Shape", action: #selector(toggleFogOfWarShape(_:)), keyEquivalent: "t")
        fogShapeItem.target = self
        menu.addItem(fogShapeItem)

        let windowItems = openDocumentWindowItems()
        if windowItems.isEmpty == false {
            menu.addItem(.separator())
            for item in windowItems {
                menu.addItem(item)
            }
        }
    }

    private func zoomMenu() -> NSMenu {
        let menu = NSMenu(title: "Zoom")
        menu.addItem(withTitle: "Zoom In", action: #selector(zoomIn(_:)), keyEquivalent: "+").target = self
        menu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-").target = self
        menu.addItem(.separator())

        let currentZoom = activeCanvasView()?.currentZoom
        for preset in MapCanvasView.zoomPresets {
            let item = NSMenuItem(title: "\(Int(preset * 100))%", action: #selector(setZoomPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            if let currentZoom, abs(currentZoom - preset) / preset <= 0.10 {
                item.state = .on
            }
            menu.addItem(item)
        }
        return menu
    }

    private func rotateMenu() -> NSMenu {
        let menu = NSMenu(title: "Rotate Map")
        let currentRotation = activeCanvasView()?.currentMapRotationDegrees
        for degrees in MapCanvasView.rotationPresets {
            let item = NSMenuItem(title: "\(degrees)\u{00B0}", action: #selector(setRotation(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = degrees
            if currentRotation == degrees {
                item.state = .on
            }
            menu.addItem(item)
        }
        return menu
    }

    private func openDocumentWindowItems() -> [NSMenuItem] {
        NSDocumentController.shared.documents.flatMap { document in
            document.windowControllers.compactMap { controller -> NSMenuItem? in
                guard let window = controller.window else { return nil }
                let item = NSMenuItem(title: window.title, action: #selector(showWindow(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = window
                if window.isKeyWindow {
                    item.state = .on
                }
                return item
            }
        }
    }

    @objc private func zoomIn(_ sender: Any?) {
        guard let canvasView = activeCanvasView() else {
            NSSound.beep()
            return
        }
        _ = canvasView.zoomInToNextPreset()
    }

    @objc private func zoomOut(_ sender: Any?) {
        guard let canvasView = activeCanvasView() else {
            NSSound.beep()
            return
        }
        _ = canvasView.zoomOutToNextPreset()
    }

    @objc private func setZoomPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? CGFloat,
              let canvasView = activeCanvasView() else {
            NSSound.beep()
            return
        }
        canvasView.setZoom(preset)
    }

    @objc private func setRotation(_ sender: NSMenuItem) {
        guard let degrees = sender.representedObject as? Int,
              let canvasView = activeCanvasView() else {
            NSSound.beep()
            return
        }
        canvasView.setMapRotationDegrees(degrees)
    }

    @objc private func toggleFogOfWar(_ sender: Any?) {
        guard let canvasView = activeCanvasView() else {
            NSSound.beep()
            return
        }
        canvasView.toggleFogOfWar()
    }

    @objc private func toggleFogOfWarShape(_ sender: Any?) {
        guard let canvasView = activeCanvasView() else {
            NSSound.beep()
            return
        }
        canvasView.toggleFogOfWarShape()
    }

    @objc private func showWindow(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? NSWindow else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func activeCanvasView() -> MapCanvasView? {
        (NSApp.delegate as? AppDelegate)?.activeCanvasView()
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

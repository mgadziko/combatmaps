import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayColor = OverlayColor.systemTeal

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.build()
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for window in sender.windows {
            (window.windowController as? MapWindowController)?.saveProfile()
        }
        return .terminateNow
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    @objc func addLineOverlay(_ sender: Any?) {
        activeCanvasView()?.addOverlay(kind: .line, color: overlayColor)
    }

    @objc func addCircleOverlay(_ sender: Any?) {
        activeCanvasView()?.addOverlay(kind: .circle, color: overlayColor)
    }

    @objc func addRectangleOverlay(_ sender: Any?) {
        activeCanvasView()?.addOverlay(kind: .rectangle, color: overlayColor)
    }

    @objc func addConeOverlay(_ sender: Any?) {
        activeCanvasView()?.addOverlay(kind: .cone, color: overlayColor)
    }

    @objc func chooseOverlayColor(_ sender: Any?) {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(overlayColorChanged(_:)))
        panel.color = overlayColor.nsColor
        panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func overlayColorChanged(_ sender: NSColorPanel) {
        overlayColor = OverlayColor(sender.color)
    }

    @objc func showAbout(_ sender: Any?) {
        AboutBoxController.shared.show()
    }

    private func activeCanvasView() -> MapCanvasView? {
        guard let controller = NSApp.keyWindow?.windowController as? MapWindowController else {
            return nil
        }
        return controller.canvasView
    }
}

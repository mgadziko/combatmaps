import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.build()
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    @objc func addLineOverlay(_ sender: Any?) {
        activeCanvasView()?.addOverlay(kind: .line)
    }

    @objc func addCircleOverlay(_ sender: Any?) {
        activeCanvasView()?.addOverlay(kind: .circle)
    }

    @objc func addRectangleOverlay(_ sender: Any?) {
        activeCanvasView()?.addOverlay(kind: .rectangle)
    }

    @objc func addConeOverlay(_ sender: Any?) {
        activeCanvasView()?.addOverlay(kind: .cone)
    }

    private func activeCanvasView() -> MapCanvasView? {
        guard let controller = NSApp.keyWindow?.windowController as? MapWindowController else {
            return nil
        }
        return controller.canvasView
    }
}

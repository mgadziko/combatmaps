import AppKit

final class MapWindowController: NSWindowController, NSWindowDelegate {
    let canvasView: MapCanvasView
    private let documentURL: URL?
    private let targetScreen: NSScreen?

    init(image: NSImage, documentURL: URL?) {
        self.documentURL = documentURL
        canvasView = MapCanvasView(image: image)
        if let profile = DocumentProfileStore.load(for: documentURL) {
            canvasView.apply(profile: profile)
        }

        let screen = MapWindowController.preferredScreen()
        targetScreen = screen
        let window = NSWindow(
            contentRect: screen?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = documentURL?.lastPathComponent ?? "CombatMaps"
        window.contentView = canvasView
        window.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        if let targetScreen, let window {
            window.setFrame(targetScreen.visibleFrame, display: false)
        }
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        guard ProcessInfo.processInfo.environment["COMBATMAPS_DISABLE_FULLSCREEN"] != "1" else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, !window.styleMask.contains(.fullScreen) else { return }
            window.toggleFullScreen(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        saveProfile()
    }

    func saveProfile() {
        DocumentProfileStore.save(canvasView.profile, for: documentURL)
    }

    private static func preferredScreen() -> NSScreen? {
        guard NSScreen.screens.count > 1 else {
            return NSScreen.main
        }
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        return NSScreen.screens.first { $0 != primary } ?? primary
    }
}

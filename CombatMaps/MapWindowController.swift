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
        window.collectionBehavior = [.fullScreenPrimary]
        window.tabbingMode = .disallowed
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
        bringDocumentToForeground()
        guard ProcessInfo.processInfo.environment["COMBATMAPS_DISABLE_FULLSCREEN"] != "1" else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, !window.styleMask.contains(.fullScreen) else { return }
            window.toggleFullScreen(nil)
            self.bringDocumentToForeground()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.bringDocumentToForeground()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        saveProfile()
    }

    func saveProfile() {
        DocumentProfileStore.save(canvasView.profile, for: documentURL)
    }

    private func bringDocumentToForeground() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        window.makeFirstResponder(canvasView)
    }

    func moveToScreen(_ screen: NSScreen) {
        guard let window else { return }

        let moveWindow = {
            window.setFrame(screen.visibleFrame, display: true, animate: true)
            window.makeKeyAndOrderFront(nil)
        }

        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                moveWindow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard !window.styleMask.contains(.fullScreen) else { return }
                    window.toggleFullScreen(nil)
                }
            }
        } else {
            moveWindow()
        }
    }

    private static func preferredScreen() -> NSScreen? {
        guard NSScreen.screens.count > 1 else {
            return NSScreen.main
        }
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        return NSScreen.screens.first { $0 != primary } ?? primary
    }
}

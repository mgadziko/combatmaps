import AppKit

final class AboutBoxController {
    static let shared = AboutBoxController()

    private var panel: NSPanel?

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 552, height: 300),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.contentView = AboutBoxView(frame: NSRect(x: 0, y: 0, width: 552, height: 300))
        self.panel = panel

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class AboutBoxView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        buildContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildContent() {
        let iconView = NSImageView(frame: NSRect(x: 20, y: 224, width: 52, height: 52))
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        addLabel("CombatMaps", frame: NSRect(x: 20, y: 196, width: 512, height: 22), font: .systemFont(ofSize: 13, weight: .semibold))
        addLabel(aboutVersionText(), frame: NSRect(x: 20, y: 172, width: 512, height: 22), font: .systemFont(ofSize: 13))
        addLabel("Read-only tactical image map viewer.", frame: NSRect(x: 20, y: 134, width: 512, height: 34), font: .systemFont(ofSize: 13))
        addLabel("©2026 Mark Gadzikowski. All Rights Reserved Worldwide.", frame: NSRect(x: 20, y: 100, width: 512, height: 22), font: .systemFont(ofSize: 13, weight: .semibold))
        addLabel("Contact: combatmaps@quantumpenguin.net", frame: NSRect(x: 20, y: 70, width: 512, height: 22), font: .systemFont(ofSize: 13))

        let button = NSButton(frame: NSRect(x: 162, y: 18, width: 228, height: 32))
        button.title = "OK"
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.target = self
        button.action = #selector(closeWindow)
        addSubview(button)
    }

    private func addLabel(_ text: String, frame: NSRect, font: NSFont) {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = font
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        addSubview(label)
    }

    private func aboutVersionText() -> String {
        if let buildTimestamp = Bundle.main.object(forInfoDictionaryKey: "CombatMapsBuildTimestamp") as? String,
           buildTimestamp.isEmpty == false {
            return "Version: \(buildTimestamp)"
        }

        return "Version: Development"
    }

    @objc private func closeWindow() {
        window?.close()
    }
}

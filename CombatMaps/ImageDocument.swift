import AppKit
import CryptoKit

final class ImageDocument: NSDocument {
    private var image: NSImage?
    private var mapWindowController: MapWindowController?

    override class var autosavesInPlace: Bool {
        false
    }

    override class var readableTypes: [String] {
        ["public.png", "public.jpeg", "com.compuserve.gif"]
    }

    override func read(from url: URL, ofType typeName: String) throws {
        guard let loadedImage = NSImage(contentsOf: url) else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadCorruptFileError,
                userInfo: [NSLocalizedDescriptionKey: "CombatMaps could not read this image."]
            )
        }
        image = loadedImage
        fileURL = url
        RecentDocumentStore.record(url)
    }

    override func data(ofType typeName: String) throws -> Data {
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
    }

    override func makeWindowControllers() {
        guard let image else { return }
        let controller = MapWindowController(image: image, documentURL: fileURL)
        mapWindowController = controller
        addWindowController(controller)
    }

    override func close() {
        mapWindowController?.saveProfile()
        super.close()
    }
}

final class RecentDocumentsMenuController: NSObject, NSMenuDelegate {
    static let shared = RecentDocumentsMenuController()
    let menu = NSMenu(title: "Open Recent")

    private override init() {
        super.init()
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()
        let urls = RecentDocumentStore.urls()
        if urls.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
            item.representedObject = url
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear Menu", action: #selector(clearRecentDocuments(_:)), keyEquivalent: "").target = self
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                NSApp.presentError(error)
            }
        }
    }

    @objc private func clearRecentDocuments(_ sender: Any?) {
        RecentDocumentStore.clear()
        rebuild()
    }
}

enum RecentDocumentStore {
    private static let key = "RecentDocumentURLs"
    private static let limit = 7

    static func record(_ url: URL) {
        let path = url.standardizedFileURL.path
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(limit)), forKey: key)
    }

    static func urls() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        return paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

struct DocumentProfile: Codable {
    var zoom: CGFloat
    var panOffset: CGPoint
}

enum DocumentProfileStore {
    static func load(for url: URL?) -> DocumentProfile? {
        guard let key = key(for: url),
              let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(DocumentProfile.self, from: data)
    }

    static func save(_ profile: DocumentProfile, for url: URL?) {
        guard let key = key(for: url),
              let data = try? JSONEncoder().encode(profile) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func key(for url: URL?) -> String? {
        guard let url else { return nil }
        let path = url.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        let suffix = digest.map { String(format: "%02x", $0) }.joined()
        return "DocumentProfile.\(suffix)"
    }
}

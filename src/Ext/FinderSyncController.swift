import Cocoa
import FinderSync

@objc(FinderSyncController)
class FinderSyncController: FIFinderSync {

    let formats: [String] = ["PNG", "JPG", "PDF", "TIFF", "BMP", "GIF", "HEIC"]

    let imageExtensions: Set<String> = [
        "heic", "heif", "jpg", "jpeg", "jpe",
        "png", "gif", "tiff", "tif", "bmp",
        "webp", "jp2", "raw", "dng", "psd", "ico", "icns",
        "pdf"
    ]

    private let pathsLock = NSLock()
    private var lastPaths: [String] = []

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else { return nil }
        guard let urls = FIFinderSyncController.default().selectedItemURLs(),
              !urls.isEmpty,
              urls.allSatisfy({ isImage($0) }) else { return nil }

        let paths = urls.map { $0.path }
        pathsLock.lock()
        lastPaths = paths
        pathsLock.unlock()

        let menuTitle = NSLocalizedString("ConvertFile", comment: "Submenu title")
        let menu = NSMenu(title: "")
        let parent = NSMenuItem(title: menuTitle, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: menuTitle)
        for (index, fmt) in formats.enumerated() {
            let item = NSMenuItem(
                title: fmt,
                action: #selector(convertSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            submenu.addItem(item)
        }
        parent.submenu = submenu
        menu.addItem(parent)
        return menu
    }

    private func isImage(_ url: URL) -> Bool {
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    @objc func convertSelected(_ sender: NSMenuItem) {
        let tag = sender.tag
        guard tag >= 0, tag < formats.count else { return }
        let fmt = formats[tag]

        pathsLock.lock()
        var resolvedPaths = lastPaths
        pathsLock.unlock()

        if resolvedPaths.isEmpty,
           let urls = FIFinderSyncController.default().selectedItemURLs() {
            resolvedPaths = urls.map { $0.path }
        }
        guard !resolvedPaths.isEmpty else { return }

        var components = URLComponents()
        components.scheme = "fileconverter"
        components.host = "convert"
        var items = [URLQueryItem(name: "fmt", value: fmt)]
        for path in resolvedPaths {
            items.append(URLQueryItem(name: "path", value: path))
        }
        components.queryItems = items

        guard let appURL = components.url else { return }
        NSWorkspace.shared.open(appURL)
    }
}

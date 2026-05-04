import Cocoa
import FinderSync

@objc(FinderSyncController)
class FinderSyncController: FIFinderSync {

    let formats: [String] = ["PNG", "JPG", "PDF", "TIFF", "BMP", "GIF", "HEIC", "DOCX"]

    /// Output formats that require pixel data (rasters).
    let imageFormats: Set<String> = ["PNG", "JPG", "TIFF", "BMP", "GIF", "HEIC"]

    /// Map a file extension (lowercased, no dot) to the format title that
    /// represents that extension in the submenu, if any.
    let extensionToFormat: [String: String] = [
        "png": "PNG",
        "jpg": "JPG", "jpeg": "JPG", "jpe": "JPG",
        "pdf": "PDF",
        "tiff": "TIFF", "tif": "TIFF",
        "bmp": "BMP",
        "gif": "GIF",
        "heic": "HEIC", "heif": "HEIC",
        "docx": "DOCX", "doc": "DOCX",
    ]

    /// Files we offer the menu for.
    let supportedExtensions: Set<String> = [
        "heic", "heif", "jpg", "jpeg", "jpe",
        "png", "gif", "tiff", "tif", "bmp",
        "webp", "jp2", "raw", "dng", "psd", "ico", "icns",
        "pdf", "docx", "doc"
    ]

    /// Extensions that are documents (not images).
    let documentExtensions: Set<String> = ["pdf", "docx", "doc"]

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
              urls.allSatisfy({ isSupported($0) }) else { return nil }

        let paths = urls.map { $0.path }
        pathsLock.lock()
        lastPaths = paths
        pathsLock.unlock()

        let visibleFormats = formatsExcludingSelectionFormat(urls: urls)
        guard !visibleFormats.isEmpty else { return nil }

        let menuTitle = NSLocalizedString("ConvertFile", comment: "Submenu title")
        let menu = NSMenu(title: "")
        let parent = NSMenuItem(title: menuTitle, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: menuTitle)
        for (index, fmt) in visibleFormats {
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

    /// Returns the formats to show in the submenu paired with their original
    /// index in `formats`. Filtering rules:
    /// - The format that matches the selection's own extension is excluded
    ///   when every selected file shares that same format.
    /// - DOCX is offered only when every selected file is a PDF or DOCX
    ///   (image -> DOCX would require OCR, out of scope).
    /// - Image formats are excluded when every selected file is a DOCX
    ///   (DOCX -> image isn't a meaningful conversion here).
    private func formatsExcludingSelectionFormat(urls: [URL]) -> [(Int, String)] {
        let exts = urls.map { $0.pathExtension.lowercased() }
        let selectionFormats = Set(exts.compactMap { extensionToFormat[$0] })
        let exclude: String?
        if selectionFormats.count == 1 {
            exclude = selectionFormats.first
        } else {
            exclude = nil
        }

        let allDocsOrPDF = exts.allSatisfy { documentExtensions.contains($0) }
        let allDocx = exts.allSatisfy { $0 == "docx" || $0 == "doc" }

        return formats.enumerated().compactMap { index, fmt in
            if fmt == exclude { return nil }
            if fmt == "DOCX" && !allDocsOrPDF { return nil }
            if allDocx && imageFormats.contains(fmt) { return nil }
            return (index, fmt)
        }
    }

    private func isSupported(_ url: URL) -> Bool {
        return supportedExtensions.contains(url.pathExtension.lowercased())
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

import Cocoa
import ImageIO
import UniformTypeIdentifiers
import PDFKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var receivedURL = false

    struct Format {
        let title: String
        let ext: String
        let utType: UTType?
        let isPDF: Bool

        static let all: [Format] = [
            .init(title: "PNG",  ext: "png",  utType: .png,  isPDF: false),
            .init(title: "JPG",  ext: "jpg",  utType: .jpeg, isPDF: false),
            .init(title: "PDF",  ext: "pdf",  utType: nil,   isPDF: true),
            .init(title: "TIFF", ext: "tiff", utType: .tiff, isPDF: false),
            .init(title: "BMP",  ext: "bmp",  utType: .bmp,  isPDF: false),
            .init(title: "GIF",  ext: "gif",  utType: .gif,  isPDF: false),
            .init(title: "HEIC", ext: "heic", utType: .heic, isPDF: false),
        ]
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !receivedURL {
            showInstructionsWindow()
        }
    }

    @objc func handleURL(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        receivedURL = true
        guard let urlStr = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlStr),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            terminateLater()
            return
        }
        let fmtTitle = comps.queryItems?.first(where: { $0.name == "fmt" })?.value ?? ""
        let paths = comps.queryItems?.filter { $0.name == "path" }.compactMap { $0.value } ?? []
        guard let fmt = Format.all.first(where: { $0.title == fmtTitle }), !paths.isEmpty else {
            terminateLater()
            return
        }
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.global(qos: .userInitiated).async {
            let outputs = self.runConversion(format: fmt, paths: paths)
            DispatchQueue.main.async {
                if let first = outputs.first {
                    NSWorkspace.shared.activateFileViewerSelecting([first])
                }
                self.terminateLater(0.3)
            }
        }
    }

    private func terminateLater(_ delay: TimeInterval = 0.1) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSApp.terminate(nil)
        }
    }

    private func runConversion(format: Format, paths: [String]) -> [URL] {
        var outputs: [URL] = []
        for path in paths {
            let inURL = URL(fileURLWithPath: path)
            let outURL = uniqueOutput(near: inURL, ext: format.ext)
            let ok: Bool
            if format.isPDF {
                ok = convertToPDF(url: inURL, outURL: outURL)
            } else if let type = format.utType {
                ok = convertWithImageIO(url: inURL, outURL: outURL, type: type)
            } else {
                ok = false
            }
            if ok { outputs.append(outURL) }
        }
        return outputs
    }

    private func uniqueOutput(near url: URL, ext: String) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        var out = dir.appendingPathComponent("\(base).\(ext)")
        var i = 1
        while FileManager.default.fileExists(atPath: out.path) {
            out = dir.appendingPathComponent("\(base) (\(i)).\(ext)")
            i += 1
        }
        return out
    }

    private func convertWithImageIO(url: URL, outURL: URL, type: UTType) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, type.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImageFromSource(dest, src, 0, nil)
        return CGImageDestinationFinalize(dest)
    }

    private func convertToPDF(url: URL, outURL: URL) -> Bool {
        guard let img = NSImage(contentsOf: url) else { return false }
        let pdf = PDFDocument()
        guard let page = PDFPage(image: img) else { return false }
        pdf.insert(page, at: 0)
        return pdf.write(to: outURL)
    }

    private func showInstructionsWindow() {
        let rect = NSRect(x: 0, y: 0, width: 540, height: 360)
        let win = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.center()
        win.title = NSLocalizedString("WindowTitle", comment: "Main window title")

        let label = NSTextField(labelWithString: NSLocalizedString("Instructions", comment: "Instructions body"))
        label.alignment = .left
        label.usesSingleLineMode = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = win.contentView!
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 24)
        ])

        let button = NSButton(
            title: NSLocalizedString("OpenSystemSettings", comment: "Button"),
            target: self,
            action: #selector(openSettings)
        )
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24)
        ])

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    @objc func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

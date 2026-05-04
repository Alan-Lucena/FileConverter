import Cocoa
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import CoreText

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var receivedURL = false

    enum Kind { case raster, pdf, docx }

    struct Format {
        let title: String
        let ext: String
        let utType: UTType?
        let kind: Kind

        static let all: [Format] = [
            .init(title: "PNG",  ext: "png",  utType: .png,  kind: .raster),
            .init(title: "JPG",  ext: "jpg",  utType: .jpeg, kind: .raster),
            .init(title: "PDF",  ext: "pdf",  utType: nil,   kind: .pdf),
            .init(title: "TIFF", ext: "tiff", utType: .tiff, kind: .raster),
            .init(title: "BMP",  ext: "bmp",  utType: .bmp,  kind: .raster),
            .init(title: "GIF",  ext: "gif",  utType: .gif,  kind: .raster),
            .init(title: "HEIC", ext: "heic", utType: .heic, kind: .raster),
            .init(title: "DOCX", ext: "docx", utType: nil,   kind: .docx),
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

        // PDF -> DOCX needs LibreOffice for high quality. If not installed,
        // ask the user how to proceed (install vs text-only fallback).
        let needsAlert = fmt.kind == .docx && paths.contains(where: {
            URL(fileURLWithPath: $0).pathExtension.lowercased() == "pdf"
        }) && libreOfficePath() == nil

        if needsAlert {
            let action = askLibreOfficeAction()
            switch action {
            case .install:
                if let libreURL = URL(string: "https://www.libreoffice.org/download/") {
                    NSWorkspace.shared.open(libreURL)
                }
                terminateLater(0.2)
                return
            case .cancel:
                terminateLater()
                return
            case .textOnly:
                runAndExit(format: fmt, paths: paths, forceTextOnly: true)
                return
            }
        }

        runAndExit(format: fmt, paths: paths, forceTextOnly: false)
    }

    private func runAndExit(format: Format, paths: [String], forceTextOnly: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            let outputs = self.runConversion(format: format, paths: paths, forceTextOnly: forceTextOnly)
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

    // MARK: - Conversion dispatcher

    private func runConversion(format: Format, paths: [String], forceTextOnly: Bool) -> [URL] {
        var outputs: [URL] = []
        for path in paths {
            let inURL = URL(fileURLWithPath: path)
            let outURL = uniqueOutput(near: inURL, ext: format.ext)
            let inExt = inURL.pathExtension.lowercased()
            let inputKind: Kind
            switch inExt {
            case "pdf": inputKind = .pdf
            case "docx", "doc": inputKind = .docx
            default: inputKind = .raster
            }

            let ok = convertOne(
                inURL: inURL,
                outURL: outURL,
                inputKind: inputKind,
                format: format,
                forceTextOnly: forceTextOnly
            )
            if ok { outputs.append(outURL) }
        }
        return outputs
    }

    private func convertOne(inURL: URL, outURL: URL, inputKind: Kind, format: Format, forceTextOnly: Bool) -> Bool {
        switch (inputKind, format.kind) {
        case (.docx, .docx):
            return (try? FileManager.default.copyItem(at: inURL, to: outURL)) != nil
        case (.pdf, .pdf):
            return (try? FileManager.default.copyItem(at: inURL, to: outURL)) != nil
        case (.docx, .pdf):
            if let soffice = libreOfficePath(),
               convertWithLibreOffice(input: inURL, outURL: outURL, soffice: soffice) {
                return true
            }
            return convertDOCXToPDFNative(input: inURL, outURL: outURL)
        case (.pdf, .docx):
            if !forceTextOnly, let soffice = libreOfficePath(),
               convertWithLibreOffice(input: inURL, outURL: outURL, soffice: soffice) {
                return true
            }
            return convertPDFToDOCXTextOnly(input: inURL, outURL: outURL)
        case (.raster, .raster):
            guard let type = format.utType else { return false }
            return convertWithImageIO(url: inURL, outURL: outURL, type: type)
        case (.raster, .pdf):
            return convertImageToPDF(url: inURL, outURL: outURL)
        case (.pdf, .raster):
            guard let type = format.utType else { return false }
            return convertPDFToImage(url: inURL, outURL: outURL, type: type)
        case (.docx, .raster), (.raster, .docx):
            return false  // not supported, filtered out by extension menu
        }
    }

    // MARK: - Filenames

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

    // MARK: - Image / PDF conversions

    private func convertWithImageIO(url: URL, outURL: URL, type: UTType) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, type.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImageFromSource(dest, src, 0, nil)
        return CGImageDestinationFinalize(dest)
    }

    private func convertImageToPDF(url: URL, outURL: URL) -> Bool {
        guard let img = NSImage(contentsOf: url) else { return false }
        let pdf = PDFDocument()
        guard let page = PDFPage(image: img) else { return false }
        pdf.insert(page, at: 0)
        return pdf.write(to: outURL)
    }

    private func convertPDFToImage(url: URL, outURL: URL, type: UTType) -> Bool {
        guard let pdf = PDFDocument(url: url),
              let page = pdf.page(at: 0) else { return false }

        let pageBounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let width = Int(pageBounds.width * scale)
        let height = Int(pageBounds.height * scale)
        guard width > 0, height > 0 else { return false }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return false }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        guard let cgImage = context.makeImage() else { return false }
        guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, type.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, cgImage, nil)
        return CGImageDestinationFinalize(dest)
    }

    // MARK: - LibreOffice

    private func libreOfficePath() -> String? {
        let candidates = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/usr/local/bin/soffice",
            "/opt/homebrew/bin/soffice",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func convertWithLibreOffice(input: URL, outURL: URL, soffice: String) -> Bool {
        let dir = outURL.deletingLastPathComponent()
        let targetExt = outURL.pathExtension
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: soffice)
        proc.arguments = [
            "--headless",
            "--convert-to", targetExt,
            "--outdir", dir.path,
            input.path
        ]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 { return false }

            let producedBase = input.deletingPathExtension().lastPathComponent
            let produced = dir.appendingPathComponent("\(producedBase).\(targetExt)")
            if produced.path != outURL.path {
                if FileManager.default.fileExists(atPath: outURL.path) {
                    try? FileManager.default.removeItem(at: outURL)
                }
                if FileManager.default.fileExists(atPath: produced.path) {
                    try FileManager.default.moveItem(at: produced, to: outURL)
                } else {
                    return false
                }
            }
            return FileManager.default.fileExists(atPath: outURL.path)
        } catch {
            return false
        }
    }

    // MARK: - Native DOCX <-> PDF fallbacks

    private func convertDOCXToPDFNative(input: URL, outURL: URL) -> Bool {
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.officeOpenXML
        ]
        guard let attr = try? NSAttributedString(url: input, options: opts, documentAttributes: nil),
              attr.length > 0 else { return false }

        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 72
        var pageBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let textRect = CGRect(
            x: margin,
            y: margin,
            width: pageWidth - margin * 2,
            height: pageHeight - margin * 2
        )

        guard let pdfCtx = CGContext(outURL as CFURL, mediaBox: &pageBox, nil) else { return false }

        let framesetter = CTFramesetterCreateWithAttributedString(attr as CFAttributedString)
        var location = 0
        let total = attr.length
        let path = CGPath(rect: textRect, transform: nil)

        while location < total {
            pdfCtx.beginPage(mediaBox: &pageBox)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: location, length: 0),
                path,
                nil
            )
            CTFrameDraw(frame, pdfCtx)
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length == 0 { break }
            location = visible.location + visible.length
            pdfCtx.endPage()
        }
        pdfCtx.closePDF()
        return FileManager.default.fileExists(atPath: outURL.path)
    }

    private func convertPDFToDOCXTextOnly(input: URL, outURL: URL) -> Bool {
        guard let pdf = PDFDocument(url: input) else { return false }
        let combined = NSMutableAttributedString()
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            if let pageAttr = page.attributedString {
                combined.append(pageAttr)
            } else if let raw = page.string {
                combined.append(NSAttributedString(string: raw))
            }
            if i < pdf.pageCount - 1 {
                combined.append(NSAttributedString(string: "\n\n"))
            }
        }
        guard combined.length > 0 else { return false }

        do {
            let data = try combined.data(
                from: NSRange(location: 0, length: combined.length),
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.officeOpenXML
                ]
            )
            try data.write(to: outURL)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Alert

    enum LibreOfficeAction { case install, textOnly, cancel }

    private func askLibreOfficeAction() -> LibreOfficeAction {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("LibreOfficeMissingTitle", comment: "")
        alert.informativeText = NSLocalizedString("LibreOfficeMissingBody", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("InstallLibreOffice", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("ConvertTextOnly", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .install
        case .alertSecondButtonReturn: return .textOnly
        default:                       return .cancel
        }
    }

    // MARK: - Instructions window

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

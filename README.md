# File Converter

A native macOS Finder extension that adds a **Convert File** submenu to the right-click context menu when you select images. Convert to PNG, JPG, PDF, TIFF, BMP, GIF or HEIC with a single click. Files land next to the original.

No Automator. No dialogs. No external apps. Native submenu, instant.

## Why this exists

macOS doesn't ship with image conversion in the right-click menu. Quick Actions (Automator) are flat items that either pop a dialog or only do one conversion each. Apple's `FIFinderSync` API is the only way to add a real submenu, but the official path requires an Xcode project, a signing certificate, and a paid Developer account.

This repo builds the whole thing with plain `swiftc` and ad-hoc signing. No Xcode project, no paid account, one shell script.

## Features

- Native nested submenu in Finder's right-click menu.
- Multi-select: convert many files at once with a single pick.
- Output sits next to the original. Never overwrites: appends `(1)`, `(2)`, etc. on collision.
- Finder selects the first converted file when done.
- Pure `ImageIO` (CoreGraphics) and `PDFKit`. Zero dependencies.
- Sandboxed extension delegating to non-sandboxed host app via custom URL scheme. Apple-compliant architecture without the Mac App Store.
- Localized UI in 17 languages. The app picks the right one automatically based on your macOS language.

## Requirements

- macOS 13 (Ventura) or later. Tested on macOS 26.
- Xcode Command Line Tools (for `swiftc` and the macOS SDK):

```bash
xcode-select --install
```

## Install

```bash
git clone https://github.com/Alan-Lucena/FileConverter.git
cd FileConverter
./build.sh --install
```

The script compiles, ad-hoc signs, copies the bundle to `/Applications/File Converter.app`, registers it with LaunchServices, and enables the extension. First time, macOS may ask you to allow the extension. If the menu doesn't show up:

System Settings > General > Login Items & Extensions > Finder Extensions > toggle **File Converter** on.

## Usage

1. Select one or more image files in Finder.
2. Right-click > **Convert File** (or your localized name) > pick a format.
3. The output appears next to the original.

## Supported formats

| Read | Write |
|---|---|
| HEIC, HEIF, JPG, PNG, GIF, TIFF, BMP, WebP, JP2, RAW, DNG, PSD, ICO, ICNS | PNG, JPG, PDF, TIFF, BMP, GIF, HEIC |

WebP write isn't supported because `ImageIO` on macOS doesn't ship a WebP encoder.

## Languages

UI strings ship in:

`English`, `Español`, `Français`, `Deutsch`, `Italiano`, `Português (Brasil)`, `Português (Portugal)`, `日本語`, `한국어`, `简体中文`, `繁體中文`, `Русский`, `Nederlands`, `Polski`, `Türkçe`, `العربية`, `हिन्दी`.

The system locale determines which one is used at runtime. To add another language, drop a new `<lang>.lproj` folder under `src/Resources/` with a translated `Localizable.strings` and `InfoPlist.strings`, add the locale identifier to `CFBundleLocalizations` in both `Info.plist` files, and rebuild. PRs welcome.

## How it works

```
Finder
  |
  | right-click on images
  v
FinderSync.appex (sandboxed)
  |
  | builds URL: fileconverter://convert?fmt=PNG&path=...
  | NSWorkspace.shared.open(URL)
  v
File Converter.app (no sandbox)
  |
  | parses URL, resolves format and paths
  | converts via ImageIO or PDFKit
  | writes next to the original
  | reveals first output in Finder
  | exits
```

The Finder Sync extension is sandboxed (Apple requires it for `.appex`) and only assembles a URL. The non-sandboxed host app does the actual conversion, with full filesystem access to write next to the original.

## Project layout

```
src/Host/
  main.swift            # Host app: URL scheme handler + conversion
  Info.plist            # Bundle config + CFBundleURLTypes
  Host.entitlements     # app-sandbox = false
src/Ext/
  main.swift            # NSExtensionMain entry point
  FinderSyncController.swift  # FIFinderSync subclass
  Info.plist            # NSExtension dict, NSPrincipalClass = NSApplication
  Ext.entitlements      # app-sandbox = true + user-selected.read-write
src/Resources/
  <lang>.lproj/Localizable.strings  # UI strings per locale
  <lang>.lproj/InfoPlist.strings    # Bundle display name per locale
build.sh                # Compile, sign, optional install
```

## Build without installing

```bash
./build.sh
# Bundle ends up at build/File Converter.app
```

## Uninstall

```bash
osascript -e 'tell app "File Converter" to quit' 2>/dev/null
pluginkit -e ignore -i com.alanlucena.FileConverter.FinderSync
rm -rf "/Applications/File Converter.app"
killall -KILL pkd 2>/dev/null
```

## Caveats

- Ad-hoc signed, not notarized. Gatekeeper may warn on first launch: right-click the app > Open.
- WebP is read-only.
- Conversion is one-shot with default settings (no quality slider, no resize). PRs welcome.

## License

MIT. See [LICENSE](LICENSE).

## Contributing

PRs welcome. Ideas:

- Quality picker for JPG/HEIC.
- WebP encoding once `ImageIO` supports it (or via a separate encoder).
- "Convert and delete original" option.
- Additional language localizations.
- App icon.

## Credits

Built by [@Alan-Lucena](https://github.com/Alan-Lucena) with [Claude Code](https://claude.com/claude-code).

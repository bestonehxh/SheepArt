<p align="center">
  <img src=".github/icon.png?v=3" width="128" alt="SheepArt app icon">
</p>

# 🐑 SheepArt

**A native macOS image-annotation app — capture a screenshot, mark it up, and copy it back out in seconds.**

SheepArt is written in SwiftUI + AppKit (Swift 6) around one tight loop: capture → paste →
draw → ⌘C → paste anywhere. Everything on the canvas stays an editable object until the
moment you export — there is no "merge" step, flattening happens automatically on copy and
save.

## ⬇️ Download

[![Download SheepArt for macOS](https://img.shields.io/badge/Download-SheepArt_1.0_for_macOS-2ea44f?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/bestonehxh/SheepArt/releases/latest)

**[Get the latest release →](https://github.com/bestonehxh/SheepArt/releases/latest)** — download the `.zip`, unzip, and drag **SheepArt.app** into `Applications`.

> The build is unsigned (not notarized), so macOS will warn on first launch —
> right-click the app and choose **Open**, or run
> `xattr -dr com.apple.quarantine /Applications/SheepArt.app`
>
> Requires macOS 26 (Tahoe) or later, Apple Silicon.

## The Sheep family 🐑

SheepArt is one of eight small native macOS apps that share the same sheep icon set:

|  | App | What it does |
|---|---|---|
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepArt/main/.github/icon.png?v=3" width="44" alt=""> | [SheepArt](https://github.com/bestonehxh/SheepArt) | Screenshot annotation — draw, crop, layers, one-key background removal |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepTerm/main/.github/icon.png?v=3" width="44" alt=""> | [SheepTerm](https://github.com/bestonehxh/SheepTerm) | SSH / Serial / local-shell terminal for network engineers |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepTap/main/.github/icon.png?v=3" width="44" alt=""> | [SheepTap](https://github.com/bestonehxh/SheepTap) | Menu-bar viewer for your Mac's network interfaces with click-to-copy |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepPing/main/.github/icon.png?v=3" width="44" alt=""> | [SheepPing](https://github.com/bestonehxh/SheepPing) | Continuous multi-host ping monitor with per-host logs and CSV export |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepText/main/.github/icon.png?v=3" width="44" alt=""> | [SheepText](https://github.com/bestonehxh/SheepText) | Fast text editor with tree-sitter highlighting and a JavaScript plugin system |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepDrop/main/.github/icon.png?v=3" width="44" alt=""> | [SheepDrop](https://github.com/bestonehxh/SheepDrop) | SFTP / SCP / FTP / TFTP file transfer — client and built-in server |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepRadius/main/.github/icon.png?v=4" width="44" alt=""> | [SheepRadius](https://github.com/bestonehxh/SheepRadius) | RADIUS + LDAP lab for 802.1X, device logins and NAC — with a joinable Samba AD |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepKey/main/.github/icon.png?v=2" width="44" alt=""> | [SheepKey](https://github.com/bestonehxh/SheepKey) | Mac shortcuts (⌘ as Ctrl) inside AnyDesk, TeamViewer and RustDesk |

## Features

### Get an image in
- **Paste to start** — open the app and hit ⌘V; the first image becomes the canvas
  (New from Clipboard, no empty-document dance)
- **Built-in screen capture** (⇧⌘K) — drag an area, it lands on the canvas immediately;
  no reliance on the system screenshot shortcuts
- Open image files (⌘O), or **drag & drop** them onto the canvas — later images stack as
  layers on top
- **Blank canvas** like classic Paint (⌥⌘N, four preset sizes) with the pen pre-armed

### Draw
- **Pen** (smoothed freehand), **line**, **rectangle**, **ellipse**, and **arrow** tools —
  one-key switching (P L R O A), 8 colors, 3 stroke widths
- Stroke width is chosen at *screen* scale and stored in image pixels, so annotations stay
  proportional on huge screenshots
- Select, move, and resize anything; right-click any object to restyle it (color, width,
  z-order, duplicate, delete)
- **Crop** with a darkened overlay, rule-of-thirds grid, and live dimensions — crop is
  non-destructive to your objects: everything stays editable afterwards

### Layers
- Images and shapes live in one z-ordered list — stack multiple images, reorder with
  `[` / `]`, toggle visibility per layer in the Layers panel (⌥⌘L)
- **Remove Background** (⇧⌘B) on any image layer — Apple's Vision subject-lift, the same
  machinery Photos uses; no external dependencies

### Get the result out
- **⌘C is selection-aware**: with nothing selected it copies the flattened image; with an
  object selected it copies that object (as an editable SheepArt object *and* a PNG for
  other apps)
- **Save PNG** (⌘S) or save an editable **`.sheepart` project** (⇧⌘S) that reopens with
  every layer intact
- Full undo/redo across everything, including crop

## Requirements

- macOS 26 (Tahoe) or later, Apple Silicon
- To build: Xcode 26+ (no external dependencies)

## Building

```bash
xcodebuild -project SheepArt.xcodeproj -scheme SheepArt -configuration Release build
```

The app is built at
`~/Library/Developer/Xcode/DerivedData/SheepArt-*/Build/Products/Release/SheepArt.app`.

## License

[MIT](LICENSE) © 2026 bestonehxh

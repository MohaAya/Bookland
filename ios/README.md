# BookLand for iPhone

This is the iPhone 16-focused SwiftUI design and target for BookLand.

The source code is released under the repository’s [MIT License](../LICENSE). Authorship, design, branding, third-party technology, and imported-content terms are recorded in [`INTELLECTUAL_PROPERTY.md`](INTELLECTUAL_PROPERTY.md) and the root [`NOTICE.md`](../NOTICE.md).

## Authorship and intellectual property

BookLand’s concept and design ideas are by **Mohammad Ayati**, created in **August 2026**. This includes the original research-reading workflow, library and comparison-reader structure, page-history interaction, study themes, sketchbook paper treatment, and visual direction. See [`INTELLECTUAL_PROPERTY.md`](INTELLECTUAL_PROPERTY.md) for the project’s authorship and intellectual-property record.

The BookLand logo artwork and logo-specific visual-identity design are credited to **Lida Samadi**, designer of the BookLand logo. GitHub: [@lidasama](https://github.com/lidasama). Instagram: [@lidasamadi.design](https://www.instagram.com/lidasamadi.design/).

Open `BookLand-iOS.xcodeproj` in Xcode, choose an iPhone 16 simulator or connected iPhone, select your development team under the target’s **Signing & Capabilities** tab, and run the `BookLand-iOS` scheme. The project is configured for **Automatic** signing with an **Apple Development** identity. Xcode must be signed in to an Apple Developer account; it will then create/download the matching development certificate and provisioning profile.

For a device build from Terminal after signing in and selecting your team:

```sh
xcodebuild -project BookLand-iOS.xcodeproj -scheme BookLand-iOS -sdk iphoneos -configuration Debug -allowProvisioningUpdates build
```

PDF import paths:

- Telegram: open the PDF, tap Share, swipe through the app row, choose More, then choose BookLand. BookLand stages the file and asks for the library title.
- Mail: press and hold the PDF attachment, then choose Share/Open in BookLand.
- Files, Safari, and other document apps: use their Share/Open in action.
- Inside BookLand: tap Import a PDF and choose from Files.

The document declaration in `Info.plist` registers BookLand as a PDF viewer. The app receives the incoming URL with SwiftUI’s `onOpenURL`, stages the PDF immediately, asks for its title, copies it into its own Documents folder, and persists the library metadata locally. Telegram will not appear as a folder inside the Files picker; the Telegram-to-BookLand route is Share/Open in.

Reader controls:

- Choose **Page turn** for smooth horizontal book-style swipes or **Vertical scroll** for continuous reading. The choice is independent for each reader and compare pane.
- Use the compact Previous/Next page buttons, or tap the page counter to jump to a specific page.
- In full screen, use the persistent back arrow to return to the library, the grid button to browse page thumbnails or the PDF index, and the full-screen menus to change theme or reading mode.
- Use the magnifying-glass menu for Zoom in, Zoom out, and Fit to screen. Pinch-to-zoom remains available in the PDF surface.
- Use the clock button for the separate reading-history trail, including jumps back to earlier pages.
- Use the expand button for distraction-free full-screen reading. Rotate the iPhone to landscape; the reader and Compare layout adapt to the available orientation.
- Touch and hold selectable PDF text to use the native iPhone selection menu, including Copy, Look Up, Search, and related actions when the PDF contains a text layer.
- Paper themes now tint the rendered PDF surface itself: Milky, Sepia, Blue Grey, Sage Study, Sketchbook, Midnight Navy, Graphite Night, and Amber Night. Sketchbook adds a restrained hand-drawn paper grain; the dark themes use low-glare dark paper with readable light text.

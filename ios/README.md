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

## Keeping BookLand installed (the 7-day problem)

An app installed from Xcode with a free Apple ID gets a provisioning profile that is valid for **7 days**; after that iPhone refuses to open it. No setting or code inside the app can extend that, and the only free fixes are to re-sign it before it runs out:

- **In the app:** the Library shows a warning during the last three days, and Settings → *Keeping BookLand installed* shows the exact expiry time and can send a reminder 3 days and 1 day before.
- **One command:** `ios/tools/refresh-iphone.sh --force` rebuilds with a fresh profile and installs over the existing app on your paired iPhone in about 20 seconds. Without `--force` it only refreshes when the last refresh is 4+ days old.
- **Automatic (optional):** `ios/tools/install-refresh-agent.sh` runs that script every 6 hours in the background while you are logged in to your Mac, so a refresh happens by itself whenever the iPhone is reachable on the same Wi-Fi. `--remove` turns it off. It needs this folder to stay on the Mac, the iPhone paired once with a cable, and *Connect via network* ticked in Xcode → Window → Devices and Simulators.
- **Never delete the app first.** Installing over it keeps the library, highlights and notes; deleting it removes them. The library stores only PDF file names, and PDFs found in the app's folder without a library entry are re-added on launch.
- A $99/year Apple Developer Program account would extend the profile to a year. It is not needed for any of the above.

If iPhone says the app cannot be opened because its developer is not trusted: Settings → General → VPN & Device Management → your Apple Development entry → Trust.

## Reading

- The reader hides the tab bar and shows one header: back, title, reading mode, paper theme and a More menu (zoom, fit, reading history). **Tap the page** to hide or show all controls.
- The bottom bar has a page slider, previous/next, the page counter (tap to jump), pages and index, search, and the highlighter.
- Select text and choose **Highlight** (four colours) or **Add note…** from the selection menu, or use the highlighter button. Highlights are drawn one rectangle per line, saved into the PDF, and listed in the Notes tab; tapping a note opens the book on that page. The share button exports every highlight and note as Markdown.
- **Page turn** gives horizontal book-style swipes and **Vertical scroll** gives continuous reading. Paper theme, reading mode and "keep screen on" are remembered across books (Settings).
- Library: books show their first page, progress and tags; swipe or long-press for Rename, Tags and Delete (with confirmation); sort by recently read, title or date added; import several PDFs at once, or tap + → Add from a link to download a PDF from a web address (direct links, Dropbox and Google Drive share links) straight into the library.
- Compare: two panes with their own book, page and controls; the swap button exchanges them. In portrait they stack, in landscape they sit side by side.
- Paper themes tint the rendered PDF itself: Milky, Sepia, Blue Grey, Sage Study, Sketchbook, Midnight Navy, Graphite Night and Amber Night; System follows light/dark mode.

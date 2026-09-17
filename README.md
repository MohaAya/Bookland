# Bookland

Bookland is the open-source repository for the BookLand native iOS and macOS research-reading applications.

## Credits

- **Project author and owner:** Mohammad Ayati
- **Contributor, logo designer and visual identity:** [Lida Samadi](https://github.com/lidasama)
- **Created:** August 2026
- **License:** MIT License

## Contributors

- **Mohammad Ayati** — project author, owner, product concept, direction, and source implementation.
- **[Lida Samadi](https://github.com/lidasama)** — contributor, designer of the BookLand logo and logo-specific visual identity.

The repository preserves the original internal app and target name `BookLand` where changing it could affect existing Xcode or Swift build configuration.

## What is included

- `ios/` — SwiftUI iPhone/iOS project, including the Xcode project and assets.
- `macos/` — native SwiftUI/AppKit/PDFKit source and local build script for macOS.
- `LICENSE` — MIT License under Copyright (c) 2026 Mohammad Ayati.
- `NOTICE.md` — authorship, licensing, logo-design credit, and third-party notices.
- `INTELLECTUAL_PROPERTY.md` — project-design and provenance record.

## Main capabilities

BookLand is designed as a local research-reading workspace for importing, organizing, reading, annotating, and comparing PDFs. The supplied projects include local library management, PDF navigation, study-oriented reading modes, notes and highlights, page history, full-screen reading, and side-by-side document comparison.

## macOS

The macOS source requires macOS 13 or newer and the Swift toolchain.

```sh
cd macos
swift run
```

To create a local `.app` bundle:

```sh
cd macos
./make-app.sh
```

## iOS

Open `ios/BookLand-iOS.xcodeproj` in Xcode, select a simulator or connected iPhone, configure your Apple development team under Signing & Capabilities, and run the project.

## License and attribution

The original software source in this repository is released under the [MIT License](LICENSE). The MIT License permits use, modification, distribution, sublicensing, and commercial use subject to its notice requirements.

© 2026 Mohammad Ayati. The BookLand logo artwork and logo-specific visual identity are designed by **Lida Samadi**. See her GitHub profile at [github.com/lidasama](https://github.com/lidasama). This logo credit does not imply endorsement of modified forks.

Third-party technologies and user-imported PDFs remain subject to their respective owners' terms and rights. See [NOTICE.md](NOTICE.md) for details.

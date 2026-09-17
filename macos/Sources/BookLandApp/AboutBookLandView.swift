// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../../LICENSE.

import AppKit
import SwiftUI

struct AboutBookLandView: View {
    @Environment(\.dismiss) private var dismiss

    private var logoImage: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "book.closed.fill", accessibilityDescription: "BookLand") ?? NSImage()
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: logoImage)
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)

            VStack(spacing: 4) {
                Text("BookLand")
                    .font(.title.weight(.semibold))
                Text("A calm research-reading workspace")
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Concept and product design", value: "Mohammad Ayati")
                LabeledContent("Created", value: "August 2026")
                LabeledContent("Logo designer", value: "Lida Samadi")
                Link("Instagram · @lidasamadi.design", destination: URL(string: "https://www.instagram.com/lidasamadi.design/")!)
                Text("BookLand logo artwork and logo-specific visual-identity design are credited to Lida Samadi. The product concept, source implementation, and product-design record are attributed to Mohammad Ayati.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("© Mohammad Ayati, August 2026. Source code is released under the MIT License. Logo artwork and logo-specific visual identity are credited to Lida Samadi.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(width: 460)
    }
}

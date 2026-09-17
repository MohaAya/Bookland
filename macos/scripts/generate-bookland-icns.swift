// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../LICENSE.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: generate-bookland-icns input.png output.icns\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let iconSizes = [16, 32, 128, 256, 512, 1024]

guard let sourceImage = NSImage(contentsOf: inputURL),
      let sourceCGImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Could not read the source logo.\n", stderr)
    exit(1)
}

func resizedImage(_ size: Int) -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.interpolationQuality = .high
    context.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()
}

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.icns.identifier as CFString,
    iconSizes.count,
    nil
) else {
    fputs("Could not create the ICNS destination.\n", stderr)
    exit(1)
}

for size in iconSizes {
    guard let image = resizedImage(size) else {
        fputs("Could not resize the logo to \(size)x\(size).\n", stderr)
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
}

guard CGImageDestinationFinalize(destination) else {
    fputs("Could not finalize the ICNS file.\n", stderr)
    exit(1)
}

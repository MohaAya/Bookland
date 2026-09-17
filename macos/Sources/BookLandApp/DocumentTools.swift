// BookLand - Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../../LICENSE.

import AppKit
import Foundation
import PDFKit

enum BookLandDocumentToolError: LocalizedError {
    case cannotOpenPDF
    case invalidPage
    case invalidPageRange
    case noSelectableText
    case cannotWriteOutput(String)
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpenPDF:
            return "BookLand could not open the selected PDF."
        case .invalidPage:
            return "That page number is outside the PDF."
        case .invalidPageRange:
            return "Enter pages such as 1-3, 5, 8-10."
        case .noSelectableText:
            return "This PDF does not contain selectable text. OCR is needed before converting it to DOCX."
        case .cannotWriteOutput(let path):
            return "BookLand could not write the output file at \(path)."
        case .conversionFailed(let message):
            return "BookLand DOCX conversion failed: \(message)"
        }
    }
}

enum BookLandDocumentTools {
    static func pageCount(for url: URL) throws -> Int {
        guard let document = PDFDocument(url: url) else { throw BookLandDocumentToolError.cannotOpenPDF }
        return document.pageCount
    }

    static func exportPageAsJPEG(from url: URL, pageNumber: Int, to destinationURL: URL) throws {
        guard let document = PDFDocument(url: url), let page = document.page(at: pageNumber - 1) else {
            throw pageNumber > 0 ? BookLandDocumentToolError.invalidPage : BookLandDocumentToolError.cannotOpenPDF
        }

        let pageBounds = page.bounds(for: .mediaBox)
        let longestSide = max(pageBounds.width, pageBounds.height)
        let renderScale = longestSide > 0 ? min(3.0, max(1.0, 2200.0 / longestSide)) : 2.0
        let imageSize = NSSize(width: max(1, pageBounds.width * renderScale), height: max(1, pageBounds.height * renderScale))
        let image = page.thumbnail(of: imageSize, for: .mediaBox)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else {
            throw BookLandDocumentToolError.cannotWriteOutput(destinationURL.path)
        }
        try jpegData.write(to: destinationURL, options: .atomic)
    }

    static func splitPDF(from url: URL, pages pageNumbers: [Int], to destinationURL: URL) throws {
        guard let document = PDFDocument(url: url) else { throw BookLandDocumentToolError.cannotOpenPDF }
        guard !pageNumbers.isEmpty,
              pageNumbers.allSatisfy({ document.page(at: $0 - 1) != nil }) else {
            throw BookLandDocumentToolError.invalidPageRange
        }

        let output = PDFDocument()
        for pageNumber in pageNumbers {
            guard let page = document.page(at: pageNumber - 1),
                  let copiedPage = page.copy() as? PDFPage else { continue }
            output.insert(copiedPage, at: output.pageCount)
        }
        try write(output, to: destinationURL)
    }

    static func combinePDFs(urls: [URL], to destinationURL: URL) throws {
        guard !urls.isEmpty else { throw BookLandDocumentToolError.cannotOpenPDF }
        let output = PDFDocument()
        for url in urls {
            guard let document = PDFDocument(url: url) else { throw BookLandDocumentToolError.cannotOpenPDF }
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex),
                      let copiedPage = page.copy() as? PDFPage else { continue }
                output.insert(copiedPage, at: output.pageCount)
            }
        }
        guard output.pageCount > 0 else { throw BookLandDocumentToolError.cannotOpenPDF }
        try write(output, to: destinationURL)
    }

    static func convertPDFToDOCX(from url: URL, to destinationURL: URL) throws {
        guard let document = PDFDocument(url: url) else { throw BookLandDocumentToolError.cannotOpenPDF }
        let outputText = NSMutableAttributedString()

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            if pageIndex > 0 {
                outputText.append(NSAttributedString(string: "\n\nPage \(pageIndex + 1)\n\n"))
            }
            let pageString = page.string ?? page.attributedString?.string ?? ""
            let normalizedPageText = normalizedText(pageString)
            guard !normalizedPageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            outputText.append(NSAttributedString(string: normalizedPageText))
        }

        guard !outputText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BookLandDocumentToolError.noSelectableText
        }

        let temporaryRTF = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookLand-\(UUID().uuidString)")
            .appendingPathExtension("rtf")
        let range = NSRange(location: 0, length: outputText.length)
        let rtfData = try outputText.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        try rtfData.write(to: temporaryRTF, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporaryRTF) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "docx", "-output", destinationURL.path, temporaryRTF.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw BookLandDocumentToolError.conversionFailed(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "textutil returned an error"
            throw BookLandDocumentToolError.conversionFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw BookLandDocumentToolError.cannotWriteOutput(destinationURL.path)
        }
    }

    private static func write(_ document: PDFDocument, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        guard document.write(to: url) else { throw BookLandDocumentToolError.cannotWriteOutput(url.path) }
    }

    private static func normalizedText(_ value: String) -> String {
        let normalizedLineEndings = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00AD}", with: "")
        let lines = normalizedLineEndings.components(separatedBy: "\n")
        var paragraphs: [String] = []
        var current = ""

        func flush() {
            let paragraph = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty { paragraphs.append(paragraph) }
            current = ""
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flush()
                continue
            }

            // Keep obvious list and heading boundaries, but join ordinary PDF
            // visual lines so a wrapped sentence becomes one Word paragraph.
            let isBlockStart = line.hasPrefix("#") || line.hasPrefix("• ") || line.hasPrefix("- ") || line.hasPrefix("* ")
            if isBlockStart && !current.isEmpty { flush() }

            if current.isEmpty {
                current = line
            } else if current.hasSuffix("-") && line.first?.isLetter == true {
                current.removeLast()
                current.append(contentsOf: line)
            } else {
                current.append(" ")
                current.append(contentsOf: line)
            }
        }
        flush()
        return paragraphs.joined(separator: "\n\n")
    }

    static func parsePageRange(_ value: String, pageCount: Int) throws -> [Int] {
        var pages: [Int] = []
        for rawPart in value.split(separator: ",") {
            let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            if part.contains("-") {
                let bounds = part.split(separator: "-", maxSplits: 1).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                guard bounds.count == 2, bounds[0] <= bounds[1] else { throw BookLandDocumentToolError.invalidPageRange }
                pages.append(contentsOf: bounds[0]...bounds[1])
            } else if let page = Int(part) {
                pages.append(page)
            } else {
                throw BookLandDocumentToolError.invalidPageRange
            }
        }
        let uniquePages = pages.reduce(into: [Int]()) { result, page in
            if !result.contains(page) { result.append(page) }
        }
        guard !uniquePages.isEmpty, uniquePages.allSatisfy({ $0 >= 1 && $0 <= pageCount }) else {
            throw BookLandDocumentToolError.invalidPageRange
        }
        return uniquePages
    }
}

// BookLand - Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../../LICENSE.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sourceURL: URL?
    @State private var sourcePageCount = 0
    @State private var pageNumberText = "1"
    @State private var splitRangeText = "1"
    @State private var showCombine = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BookLand Tools")
                            .font(.largeTitle.weight(.semibold))
                        Text("Export, transform, and prepare PDF material for your research workflow.")
                            .foregroundStyle(.secondary)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Source PDF", systemImage: "doc.richtext")
                                    .font(.headline)
                                Spacer()
                                Button("Choose PDF…", action: chooseSourcePDF)
                            }
                            if let sourceURL {
                                Text(sourceURL.lastPathComponent)
                                    .font(.callout.weight(.medium))
                                Text(sourcePageCount > 0 ? "\(sourcePageCount) pages" : "PDF selected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Choose a PDF to enable page export, splitting, or DOCX conversion.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    toolCard(icon: "photo", title: "Export a page as JPG", description: "Render one PDF page as a high-resolution image for a slide, message, or research note.") {
                        HStack {
                            Text("Page")
                            TextField("1", text: $pageNumberText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 64)
                            Text(sourcePageCount > 0 ? "of \(sourcePageCount)" : "")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Save JPG…", action: exportPageAsJPG)
                                .disabled(sourceURL == nil || isWorking)
                        }
                    }

                    toolCard(icon: "rectangle.split.3x1", title: "Split pages into a new PDF", description: "Keep selected pages in their original order. Use ranges such as 1-3, 5, 8-10.") {
                        HStack {
                            TextField("1-3, 5", text: $splitRangeText)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 180)
                            Spacer()
                            Button("Save split PDF…", action: splitPDF)
                                .disabled(sourceURL == nil || isWorking)
                        }
                    }

                    toolCard(icon: "arrow.triangle.merge", title: "Combine PDF files", description: "Merge as many PDFs as you like into one document. Drag to reorder, with no loss of quality.") {
                        HStack {
                            Text("Add files together, drop them in, and reorder before saving.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Combine PDFs…") { showCombine = true }
                        }
                    }

                    toolCard(icon: "doc.badge.arrow.up", title: "Convert PDF text to DOCX", description: "Create an editable Word document from selectable PDF text. Page headings are added to keep the source structure visible.") {
                        HStack {
                            Text("This preserves text, not the exact visual layout of the PDF.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Save DOCX…", action: convertToDOCX)
                                .disabled(sourceURL == nil || isWorking)
                        }
                    }

                    if isWorking {
                        ProgressView("Working…")
                    }
                    if let statusMessage {
                        Label(statusMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .textSelection(.enabled)
                    }
                }
                .padding(24)
            }
            .frame(minWidth: 760, minHeight: 680)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCombine) { CombinePDFsView() }
            .alert("BookLand Tools", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func toolCard<Content: View>(icon: String, title: String, description: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                content()
            }
        }
    }

    private func chooseSourcePDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            sourceURL = url
            sourcePageCount = try BookLandDocumentTools.pageCount(for: url)
            pageNumberText = "1"
            splitRangeText = "1"
            clearStatus()
        } catch {
            showError(error)
        }
    }

    private func saveURL(defaultName: String, contentType: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func exportPageAsJPG() {
        guard let sourceURL, let page = Int(pageNumberText.trimmingCharacters(in: .whitespacesAndNewlines)), page >= 1, page <= sourcePageCount else {
            showError(BookLandDocumentToolError.invalidPage)
            return
        }
        let name = "\(sourceURL.deletingPathExtension().lastPathComponent)-page-\(page).jpg"
        guard let destination = saveURL(defaultName: name, contentType: .jpeg) else { return }
        perform {
            try BookLandDocumentTools.exportPageAsJPEG(from: sourceURL, pageNumber: page, to: destination)
            return "Saved page \(page) as \(destination.lastPathComponent)."
        }
    }

    private func splitPDF() {
        guard let sourceURL else { showError(BookLandDocumentToolError.cannotOpenPDF); return }
        do {
            let pages = try BookLandDocumentTools.parsePageRange(splitRangeText, pageCount: sourcePageCount)
            let name = "\(sourceURL.deletingPathExtension().lastPathComponent)-pages.pdf"
            guard let destination = saveURL(defaultName: name, contentType: .pdf) else { return }
            perform {
                try BookLandDocumentTools.splitPDF(from: sourceURL, pages: pages, to: destination)
                return "Saved \(pages.count) selected page\(pages.count == 1 ? "" : "s") as \(destination.lastPathComponent)."
            }
        } catch {
            showError(error)
        }
    }

    private func convertToDOCX() {
        guard let sourceURL else { showError(BookLandDocumentToolError.cannotOpenPDF); return }
        let name = "\(sourceURL.deletingPathExtension().lastPathComponent).docx"
        let docxType = UTType("org.openxmlformats.wordprocessingml.document") ?? UTType(filenameExtension: "docx")!
        guard let destination = saveURL(defaultName: name, contentType: docxType) else { return }
        perform {
            try BookLandDocumentTools.convertPDFToDOCX(from: sourceURL, to: destination)
            return "Saved editable text as \(destination.lastPathComponent)."
        }
    }

    private func perform(_ operation: () throws -> String) {
        isWorking = true
        clearStatus()
        do {
            statusMessage = try operation()
        } catch {
            showError(error)
        }
        isWorking = false
    }

    private func clearStatus() {
        statusMessage = nil
    }

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        statusMessage = nil
    }
}

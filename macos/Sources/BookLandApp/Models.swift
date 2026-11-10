// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../../LICENSE.

import Foundation

enum LibraryNoteKind: String, Codable, CaseIterable {
    case note
    case comment
    case highlight

    var label: String {
        switch self {
        case .note: return "Note"
        case .comment: return "Comment"
        case .highlight: return "Highlight"
        }
    }
}

struct LibraryNote: Identifiable, Codable, Hashable {
    let id: UUID
    let page: Int
    let text: String
    let kind: LibraryNoteKind
    let createdAt: Date
    /// Highlight colour name ("yellow", "green", "pink", "blue"); nil for notes and older highlights.
    var colorName: String?

    init(id: UUID = UUID(), page: Int, text: String, kind: LibraryNoteKind, createdAt: Date = .now, colorName: String? = nil) {
        self.id = id
        self.page = page
        self.text = text
        self.kind = kind
        self.createdAt = createdAt
        self.colorName = colorName
    }
}

struct LibraryBook: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var fileName: String
    var sourcePath: String
    var dateAdded: Date
    var lastPage: Int
    var notes: [LibraryNote]
    var tags: [String]
    var lastOpenedAt: Date?
    var lastReadAt: Date?
    var openCount: Int
    var readCount: Int
    /// Number of pages, once known (used for the progress bar).
    var pageCount: Int?
    /// Archived books are tucked away from the main list but keep their notes.
    var isArchived: Bool

    var isMarkdown: Bool {
        ["md", "markdown"].contains(fileName.lowercased().split(separator: ".").last.map(String.init) ?? "")
    }

    init(id: UUID = UUID(), title: String, fileName: String, sourcePath: String, dateAdded: Date = .now, lastPage: Int = 1, notes: [LibraryNote] = [], tags: [String] = [], lastOpenedAt: Date? = nil, lastReadAt: Date? = nil, openCount: Int = 0, readCount: Int = 0, pageCount: Int? = nil, isArchived: Bool = false) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.sourcePath = sourcePath
        self.dateAdded = dateAdded
        self.lastPage = lastPage
        self.notes = notes
        self.tags = tags
        self.lastOpenedAt = lastOpenedAt
        self.lastReadAt = lastReadAt
        self.openCount = openCount
        self.readCount = readCount
        self.pageCount = pageCount
        self.isArchived = isArchived
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, fileName, sourcePath, dateAdded, lastPage, notes
        case tags, lastOpenedAt, lastReadAt, openCount, readCount, pageCount, isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        fileName = try container.decode(String.self, forKey: .fileName)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        lastPage = try container.decodeIfPresent(Int.self, forKey: .lastPage) ?? 1
        notes = try container.decodeIfPresent([LibraryNote].self, forKey: .notes) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        lastReadAt = try container.decodeIfPresent(Date.self, forKey: .lastReadAt)
        openCount = try container.decodeIfPresent(Int.self, forKey: .openCount) ?? 0
        readCount = try container.decodeIfPresent(Int.self, forKey: .readCount) ?? 0
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

// MARK: - Reading progress and export

extension LibraryBook {
    /// 0...1, or nil when the length of the book is not known yet.
    var progress: Double? {
        guard !isMarkdown, let pageCount, pageCount > 0 else { return nil }
        return min(1, max(0, Double(lastPage) / Double(pageCount)))
    }

    var progressText: String? {
        guard !isMarkdown, let pageCount, pageCount > 0 else { return nil }
        return "Page \(min(lastPage, pageCount)) of \(pageCount)"
    }

    enum ReadingStatus: String {
        case reading = "Reading"
        case notStarted = "Not started"
        case finished = "Finished"
    }

    var status: ReadingStatus {
        if let pageCount, pageCount > 1, lastPage >= pageCount { return .finished }
        if readCount == 0 && lastPage <= 1 { return .notStarted }
        return .reading
    }

    var highlightCount: Int { notes.filter { $0.kind == .highlight }.count }
    var noteCount: Int { notes.filter { $0.kind != .highlight }.count }

    /// "3 highlights · 1 note", or nil when there is nothing.
    var notesSummary: String? {
        var parts: [String] = []
        if highlightCount > 0 { parts.append(highlightCount == 1 ? "1 highlight" : "\(highlightCount) highlights") }
        if noteCount > 0 { parts.append(noteCount == 1 ? "1 note" : "\(noteCount) notes") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// One passage ready to paste: the text, then where it came from.
    func citation(for note: LibraryNote) -> String {
        if note.kind == .highlight { return "“\(note.text)” — \(title), p. \(note.page)" }
        return "\(note.text)\n— \(title), p. \(note.page)"
    }

    /// Several passages as Markdown, in page order, headed by the book title.
    func notesMarkdown(_ chosen: [LibraryNote]? = nil) -> String {
        let list = (chosen ?? notes).sorted { $0.page < $1.page }
        var out = "# \(title)\n"
        for note in list {
            switch note.kind {
            case .highlight: out += "\n- p. \(note.page) — “\(note.text)”"
            case .comment: out += "\n- p. \(note.page) — (comment) \(note.text)"
            case .note: out += "\n- p. \(note.page) — \(note.text)"
            }
        }
        return out + "\n"
    }
}

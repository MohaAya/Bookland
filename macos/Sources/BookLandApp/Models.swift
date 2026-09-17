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

    init(id: UUID = UUID(), page: Int, text: String, kind: LibraryNoteKind, createdAt: Date = .now) {
        self.id = id
        self.page = page
        self.text = text
        self.kind = kind
        self.createdAt = createdAt
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

    var isMarkdown: Bool {
        ["md", "markdown"].contains(fileName.lowercased().split(separator: ".").last.map(String.init) ?? "")
    }

    init(id: UUID = UUID(), title: String, fileName: String, sourcePath: String, dateAdded: Date = .now, lastPage: Int = 1, notes: [LibraryNote] = [], tags: [String] = [], lastOpenedAt: Date? = nil, lastReadAt: Date? = nil, openCount: Int = 0, readCount: Int = 0) {
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, fileName, sourcePath, dateAdded, lastPage, notes
        case tags, lastOpenedAt, lastReadAt, openCount, readCount
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
    }
}

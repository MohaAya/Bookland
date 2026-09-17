// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../../LICENSE.

import SwiftUI

@main
struct BookLandApp: App {
    @StateObject private var store = LibraryStore()

    var body: some Scene {
        WindowGroup("BookLand") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About BookLand") {
                    NotificationCenter.default.post(name: .booklandAboutRequested, object: nil)
                }
            }
            CommandGroup(after: .newItem) {
                Button("Import PDF…") {
                    NotificationCenter.default.post(name: .booklandImportRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
                Button("BookLand Tools…") {
                    NotificationCenter.default.post(name: .booklandToolsRequested, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let booklandImportRequested = Notification.Name("booklandImportRequested")
    static let booklandToolsRequested = Notification.Name("booklandToolsRequested")
    static let booklandAboutRequested = Notification.Name("booklandAboutRequested")
}

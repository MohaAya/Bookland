// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../LICENSE.

import SwiftUI
import UIKit

@main
struct BookLandiOSApp: App {
    @StateObject private var store = IOSLibraryStore()
    @StateObject private var signing = IOSSigningMonitor()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environmentObject(store)
                .environmentObject(signing)
                .onOpenURL { url in
                    // Files, Mail, Telegram, Safari downloads, and any app's “Open in…” action.
                    store.prepareIncomingPDF(from: url)
                }
                .sheet(isPresented: Binding(
                    get: { store.pendingImportURL != nil },
                    set: { if !$0 { store.cancelPendingImport() } }
                )) {
                    IOSImportTitleSheet(title: $store.pendingImportTitle) {
                        store.completePendingImport()
                    }
                }
                .alert("Import failed", isPresented: Binding(get: { store.importError != nil }, set: { if !$0 { store.importError = nil } })) {
                    Button("OK") { store.importError = nil }
                } message: {
                    Text(store.importError ?? "")
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { signing.refresh() }
                }
        }
    }
}

struct IOSRootView: View {
    var body: some View {
        TabView {
            IOSLibraryHome()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
            IOSNotesView()
                .tabItem { Label("Notes", systemImage: "highlighter") }
            IOSCompareHome()
                .tabItem { Label("Compare", systemImage: "rectangle.split.2x1") }
            IOSSettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(IOSDesign.accent)
    }
}

extension Color {
    /// A colour that follows the system appearance.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

enum IOSDesign {
    static let accent = Color(light: Color(red: 0.12, green: 0.42, blue: 0.48), dark: Color(red: 0.38, green: 0.74, blue: 0.78))
    static let ink = Color(red: 0.08, green: 0.12, blue: 0.18)
    static let milky = Color(red: 0.96, green: 0.94, blue: 0.86)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

enum IOSReadingMode: String, CaseIterable, Identifiable {
    case pageTurn = "Page turn"
    case verticalScroll = "Vertical scroll"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .pageTurn: return "book.pages"
        case .verticalScroll: return "scroll"
        }
    }
}

enum IOSReaderTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case milky = "Milky paper"
    case sepia = "Sepia paper"
    case blue = "Blue grey"
    case sage = "Sage study"
    case sketchbook = "Sketchbook"
    case midnight = "Midnight navy"
    case graphite = "Graphite night"
    case nightAmber = "Amber night"

    var id: String { rawValue }

    /// `.system` follows light/dark mode; every other theme is fixed.
    func paperColor(_ scheme: ColorScheme) -> Color {
        switch self {
        case .system: return scheme == .dark ? Color(red: 0.12, green: 0.14, blue: 0.17) : .white
        case .milky: return IOSDesign.milky
        case .sepia: return Color(red: 0.92, green: 0.84, blue: 0.68)
        case .blue: return Color(red: 0.82, green: 0.90, blue: 0.98)
        case .sage: return Color(red: 0.87, green: 0.93, blue: 0.87)
        case .sketchbook: return Color(red: 0.95, green: 0.92, blue: 0.82)
        case .midnight: return Color(red: 0.055, green: 0.09, blue: 0.18)
        case .graphite: return Color(red: 0.12, green: 0.14, blue: 0.17)
        case .nightAmber: return Color(red: 0.20, green: 0.15, blue: 0.09)
        }
    }

    func isDark(_ scheme: ColorScheme) -> Bool {
        switch self {
        case .midnight, .graphite, .nightAmber: return true
        case .system: return scheme == .dark
        default: return false
        }
    }

    var isSketchy: Bool { self == .sketchbook }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .milky: return "sun.max"
        case .sepia: return "book.closed"
        case .blue: return "cloud"
        case .sage: return "leaf"
        case .sketchbook: return "pencil.and.scribble"
        case .midnight: return "moon.stars"
        case .graphite: return "circle.dotted"
        case .nightAmber: return "moon.haze"
        }
    }
}

struct IOSImportTitleSheet: View {
    @Binding var title: String
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Library title") {
                    TextField("Title", text: $title)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(onImport)
                }
                Section {
                    Text("The PDF is copied into BookLand, so it stays available even if the attachment disappears from the other app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Import", action: onImport).fontWeight(.semibold) }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}

import SwiftUI

@main
struct StickiesApp: App {
    @State private var store = NoteStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        mainScene

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(store)
                .frame(width: 480)
        }
        #endif
    }

    private var mainScene: some Scene {
        let window = WindowGroup {
            RootView()
                .environment(store)
        }
        // Coming back to the app is the moment a user most expects to see
        // whatever another device wrote while it was closed.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reload() }
        }
        // Also picked up by iPad hardware keyboards, not just the Mac menu bar.
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Sticky") { store.createNote() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!store.isFolderConfigured)
            }
            CommandGroup(after: .newItem) {
                Button("Refresh from Folder") { store.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!store.isFolderConfigured)
            }
        }

        #if os(macOS)
        return window.defaultSize(width: 960, height: 640)
        #else
        return window
        #endif
    }
}

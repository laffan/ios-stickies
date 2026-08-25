import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(NoteStore.self) private var store

    @State private var selection: Note.ID?
    @State private var isChoosingFolder = false
    @State private var isShowingSettings = false

    var body: some View {
        Group {
            if store.isFolderConfigured {
                library
            } else {
                WelcomeView { isChoosingFolder = true }
            }
        }
        .fileImporter(
            isPresented: $isChoosingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderSelection(result)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private var library: some View {
        @Bindable var store = store

        return NavigationSplitView {
            NoteListView(selection: $selection)
                .navigationTitle("Stickies")
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
                .searchable(text: $store.searchText, prompt: "Search stickies")
                .toolbar { sidebarToolbar }
        } detail: {
            if selection != nil {
                NoteEditorView(selection: $selection)
            } else {
                ContentUnavailableView(
                    "No Sticky Selected",
                    systemImage: "note.text",
                    description: Text("Pick a sticky from the list, or create a new one.")
                )
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(onDone: { isShowingSettings = false })
        }
        .onChange(of: store.notes) { _, notes in
            // Keep a valid selection when the file behind it disappears —
            // a delete from another device, or a rename in Finder.
            if let selection, !notes.contains(where: { $0.id == selection }) {
                self.selection = notes.first?.id
            }
        }
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                if let note = store.createNote() {
                    selection = note.id
                }
            } label: {
                Label("New Sticky", systemImage: "square.and.pencil")
            }
        }

        ToolbarItem {
            Menu {
                Picker("Sort By", selection: Binding(
                    get: { store.sortOrder },
                    set: { store.setSortOrder($0) }
                )) {
                    ForEach(NoteSortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(.inline)

                Divider()

                Button {
                    store.reload()
                } label: {
                    Label("Refresh from Folder", systemImage: "arrow.clockwise")
                }

                Button {
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
        }
    }

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            store.chooseFolder(url)
            selection = nil
        case .failure(let error):
            store.lastError = error.localizedDescription
        }
    }
}

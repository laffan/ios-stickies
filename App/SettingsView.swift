import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(NoteStore.self) private var store
    @State private var isChoosingFolder = false
    @State private var isConfirmingForget = false

    /// Supplied when Settings is shown as a sheet; the macOS Settings scene
    /// has its own window chrome and doesn't need a Done button.
    var onDone: (() -> Void)?

    var body: some View {
        NavigationStack {
            content
        }
    }

    private var content: some View {
        Form {
            folderSection
            displaySection
            widgetSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .fileImporter(
            isPresented: $isChoosingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                store.chooseFolder(url)
            }
        }
        .confirmationDialog(
            "Stop using this folder?",
            isPresented: $isConfirmingForget,
            titleVisibility: .visible
        ) {
            Button("Forget Folder", role: .destructive) { store.forgetFolder() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your note files stay exactly where they are. Stickies just stops reading them, and widgets go blank until you pick a folder again.")
        }
    }

    // MARK: - Sections

    private var folderSection: some View {
        Section {
            LabeledContent("Folder") {
                Text(store.folderName ?? "Not chosen")
                    .foregroundStyle(store.isFolderConfigured ? .primary : .secondary)
            }

            if let path = store.folderPath {
                LabeledContent("Location") {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.head)
                        .multilineTextAlignment(.trailing)
                }
            }

            LabeledContent("Stickies") {
                Text("\(store.notes.count)")
                    .monospacedDigit()
            }

            if store.folderUnavailable {
                Label(
                    "The folder can't be reached right now. If it lives in iCloud Drive, check you're signed in on this device.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .font(.callout)
            }

            Button("Choose a Different Folder…") { isChoosingFolder = true }

            if store.isFolderConfigured {
                Button("Forget Folder", role: .destructive) { isConfirmingForget = true }
            }
        } header: {
            Text("Notes Folder")
        } footer: {
            Text("Each sticky is a markdown file in this folder. Point it at iCloud Drive, Dropbox or Google Drive and every device that opens the same folder shows the same stickies.")
        }
    }

    private var displaySection: some View {
        Section("Sticky List") {
            Picker("Sort by", selection: Binding(
                get: { store.sortOrder },
                set: { store.setSortOrder($0) }
            )) {
                ForEach(NoteSortOrder.allCases) { order in
                    Text(order.displayName).tag(order)
                }
            }

            LabeledContent("Character limit") {
                Text("\(Note.characterLimit)")
                    .monospacedDigit()
            }
        }
    }

    private var widgetSection: some View {
        Section {
            NavigationLink {
                WidgetHelpView()
            } label: {
                Label("How to add widgets", systemImage: "rectangle.stack.badge.plus")
            }

            LabeledContent("App Group") {
                Label(
                    AppGroup.isConfigured ? "Ready" : "Not available",
                    systemImage: AppGroup.isConfigured ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(AppGroup.isConfigured ? Color.green : Color.red)
                .labelStyle(.titleAndIcon)
            }
        } header: {
            Text("Widgets")
        } footer: {
            if !AppGroup.isConfigured {
                Text("Widgets share data with the app through the App Group “\(AppGroup.identifier)”. Until that's set up in your Apple Developer account and both targets' entitlements, widgets will come up empty.")
            } else {
                Text("Widgets refresh when you edit a sticky here, and periodically otherwise. A change made on another device shows up the next time the widget refreshes.")
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text(Self.versionString)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Formatting") {
                Text("Markdown")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// Plain, specific instructions — widget setup is the part of this app that
/// happens outside the app.
struct WidgetHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section(
                    title: "Single Sticky",
                    detail: "One note, filling the widget. Available in small, medium and large.",
                    systemImage: "note.text"
                )
                section(
                    title: "Two Stickies",
                    detail: "Two notes stacked with a gap between them, at a smaller text size. Handy for a to-do list above a reminder.",
                    systemImage: "square.stack"
                )
                #if os(iOS)
                section(
                    title: "Lock Screen",
                    detail: "A strip above or below the clock that fits in as much of one sticky's text as it can. Colour is dropped there — the system renders Lock Screen widgets in a single tint.",
                    systemImage: "lock.rectangle.on.rectangle"
                )
                #endif

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Adding one").font(.headline)
                    #if os(iOS)
                    steps([
                        "Touch and hold the Home Screen, then tap ✚ in the corner.",
                        "Search for Stickies and pick the widget size you want.",
                        "Add it, then touch and hold it and choose Edit Widget.",
                        "Tap Sticky and choose which note it should show."
                    ])
                    Text("For the Lock Screen: touch and hold the Lock Screen, tap Customise, choose the widget area, and add Stickies there.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    #else
                    steps([
                        "Click the date and time in the menu bar to open Notification Centre.",
                        "Scroll to the bottom and click Edit Widgets.",
                        "Find Stickies and drag the size you want onto the desktop or Notification Centre.",
                        "Right-click the widget and choose Edit Widget to pick which note it shows."
                    ])
                    #endif
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("If a widget is blank").font(.headline)
                    Text("It means the widget can't find that note's file. That happens if the file was renamed or deleted, or if the folder is in a cloud service that hasn't downloaded it yet. Open Stickies once to refresh, or edit the widget and pick the note again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .navigationTitle("Widgets")
    }

    private func section(title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func steps(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.bold().monospacedDigit())
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.secondary.opacity(0.18)))
                    Text(text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

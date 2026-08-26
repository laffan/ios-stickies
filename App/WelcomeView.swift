import SwiftUI

/// First run. The folder choice is the one decision the app can't make for the
/// user, so it's the only thing on screen.
struct WelcomeView: View {
    var chooseFolder: () -> Void

    private let sampleNotes: [Note] = [
        Note(
            fileName: "Groceries.md",
            body: "# Groceries\n- oat milk\n- **good** bread\n- lemons",
            color: .yellow,
            created: .now,
            modified: .now
        ),
        Note(
            fileName: "Standup.md",
            body: "# Standup\nShipped the *sync* fix.\nNext: widget sizes.",
            color: .blue,
            created: .now,
            modified: .now
        )
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                stickyStack
                    .frame(height: 190)
                    .padding(.top, 24)

                VStack(spacing: 10) {
                    Text("Stickies")
                        .font(.largeTitle.bold())
                    Text("Notes as plain markdown files, on your Home Screen and Lock Screen.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 16) {
                    bullet(
                        "folder",
                        "Pick a folder",
                        "Every sticky is one `.md` file in the folder you choose. Edit them here or in any other editor."
                    )
                    bullet(
                        "icloud",
                        "Put it in the cloud",
                        "Choose a folder inside iCloud Drive, Dropbox or Google Drive and your stickies follow you to every device."
                    )
                    bullet(
                        "rectangle.stack",
                        "Pin them anywhere",
                        "Add a widget for one sticky, two stacked stickies, or a Lock Screen strip that shows as much as it can fit."
                    )
                }
                .frame(maxWidth: 460)

                Button(action: chooseFolder) {
                    Label("Choose Notes Folder…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: 300)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("You can change the folder later in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
    }

    private var stickyStack: some View {
        ZStack {
            StickyCard(note: sampleNotes[1], presentation: .sample)
                .frame(width: 150, height: 150)
                .rotationEffect(.degrees(-8))
                .offset(x: -58, y: 6)
            StickyCard(note: sampleNotes[0], presentation: .sample)
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(5))
                .offset(x: 52, y: -4)
        }
    }

    private func bullet(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(.init(detail))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

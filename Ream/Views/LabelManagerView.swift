import SwiftUI
import SwiftData

/// Rename and delete labels. Reached from Settings, not from the filing flow — this is
/// housekeeping, and putting it in the picker would clutter the moment that matters.
struct LabelManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ScanLabel.name) private var labels: [ScanLabel]

    @State private var renaming: ScanLabel?
    @State private var draftName = ""

    var body: some View {
        NavigationStack {
            Group {
                if labels.isEmpty {
                    ContentUnavailableView {
                        Label("No labels yet", systemImage: "tag")
                    } description: {
                        Text("Open a scan and tap Labels to file it under one.")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename label", isPresented: .constant(renaming != nil)) {
                TextField("Name", text: $draftName)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") { commitRename() }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(labels) { label in
                    HStack {
                        LabelChip(name: label.name,
                                  color: label.color,
                                  showsCount: label.documentCount)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        draftName = label.name
                        renaming = label
                    }
                    // Same reasoning as the picker: 10pt around a 24pt chip is a 44pt row,
                    // rather than a 44pt frame nested inside List's own padding.
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
                .onDelete(perform: delete)
            } footer: {
                Text("Deleting a label removes it from your scans. The scans themselves are never deleted.")
            }
        }
    }

    private func commitRename() {
        guard let renaming else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Guard the write so an unchanged name doesn't dirty the model and trigger a
        // pointless @Query re-evaluation across every view showing chips.
        if !trimmed.isEmpty, trimmed != renaming.name {
            renaming.name = trimmed
            try? context.save()
            LibraryManifest.rebuild(from: context)
        }
        self.renaming = nil
    }

    private func delete(at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                // `.nullify` on the relationship detaches this label from its documents.
                // The documents are untouched — see the delete-rule note on `ScanLabel`.
                context.delete(labels[index])
            }
        }
        try? context.save()
        LibraryManifest.rebuild(from: context)
    }
}

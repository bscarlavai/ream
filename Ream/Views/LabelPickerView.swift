import SwiftUI
import SwiftData

/// Assign labels to one document, and create new ones inline.
///
/// Creation lives here rather than behind a separate "new label" screen because the moment
/// you need a label is the moment you're filing something — making that a two-screen detour
/// is how a labelling feature goes unused.
struct LabelPickerView: View {
    @Bindable var document: ScannedDocument
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context

    @Query(sort: \ScanLabel.name) private var allLabels: [ScanLabel]

    @State private var draftName = ""
    @State private var draftColorIndex = 0

    private var assigned: Set<UUID> {
        Set((document.labels ?? []).map(\.id))
    }

    private var trimmedDraft: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !trimmedDraft.isEmpty
            && !allLabels.contains { $0.name.localizedCaseInsensitiveCompare(trimmedDraft) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("New Label") {
                    // The add control lives ON the field rather than in a row beneath it.
                    // As its own row it read as a fourth list item — a thing to browse, not
                    // a button to press — and nothing connected it to the text above.
                    // `.onSubmit` means the keyboard's return key does the same thing, which
                    // is how most people will actually finish typing a name.
                    HStack(spacing: Theme.Spacing.small) {
                        TextField("New label", text: $draftName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit { if canCreate { create() } }

                        Button {
                            create()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(canCreate
                                                 ? LabelColor.allCases[draftColorIndex].color(for: scheme)
                                                 : Theme.tertiaryText)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canCreate)
                        .accessibilityLabel("Add label")
                    }

                    colorPicker
                }

                if !allLabels.isEmpty {
                    Section("Labels") {
                        ForEach(allLabels) { label in
                            row(label)
                        }
                    }
                }
            }
            .navigationTitle("Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var colorPicker: some View {
        ChipRow {
            ForEach(Array(LabelColor.allCases.enumerated()), id: \.element) { index, option in
                Button {
                    draftColorIndex = index
                } label: {
                    Circle()
                        .fill(option.color(for: scheme))
                        .frame(width: 26, height: 26)
                        .overlay {
                            if index == draftColorIndex {
                                Circle()
                                    .strokeBorder(Theme.primaryText, lineWidth: 2)
                                    .padding(-3)
                            }
                        }
                        // The swatch is 26pt; the tap target has to be 44.
                        .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayName)
            }
        }
        .listRowInsets(EdgeInsets())
    }

    private func row(_ label: ScanLabel) -> some View {
        let isOn = assigned.contains(label.id)
        return Button {
            toggle(label, isOn: isOn)
        } label: {
            HStack {
                LabelChip(name: label.name, color: label.color)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(label.color.color(for: scheme))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Explicit insets instead of `.frame(minHeight: 44)`. A 44pt frame *plus* List's
        // own default row padding stacks on top of a 24pt chip and yields a ~66pt row that
        // reads as mostly empty space. 10pt above and below a 24pt chip is 44pt exactly —
        // the tap target is still met, by construction rather than by padding it twice.
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }

    // MARK: - Mutations

    private func create() {
        let label = ScanLabel(name: trimmedDraft, colorIndex: draftColorIndex)
        context.insert(label)
        // Attach immediately — the user typed this name while filing this document, so
        // making them tap it again afterwards is a step with no decision in it.
        withAnimation {
            document.labels = (document.labels ?? []) + [label]
        }
        draftName = ""
        try? context.save()
        LibraryManifest.rebuild(from: context)
    }

    private func toggle(_ label: ScanLabel, isOn: Bool) {
        withAnimation {
            var current = document.labels ?? []
            if isOn {
                current.removeAll { $0.id == label.id }
            } else {
                current.append(label)
            }
            document.labels = current
        }
        try? context.save()
        LibraryManifest.rebuild(from: context)
    }
}

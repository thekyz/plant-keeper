import SwiftUI

struct WateringDateSheetView: View {
    let draft: WateringDateDraft
    let onSave: (Date) -> Void
    let onCancel: () -> Void

    @State private var selectedDate: Date

    init(
        draft: WateringDateDraft,
        onSave: @escaping (Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedDate = State(initialValue: draft.initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Watering date",
                    selection: $selectedDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
            .navigationTitle(draft.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.confirmTitle) {
                        onSave(selectedDate)
                    }
                }
            }
        }
    }
}

struct WateringLogsSheetView: View {
    let plantName: String
    let plantID: UUID
    let wateringLogs: [Date]
    let onSaveDraft: (WateringDateDraft, Date) -> Void
    let onDeleteLog: (Int) -> Void
    let onClose: () -> Void

    @State private var activeDateDraft: WateringDateDraft?

    var body: some View {
        NavigationStack {
            Group {
                if wateringLogs.isEmpty {
                    ContentUnavailableView("No watering logs", systemImage: "drop")
                } else {
                    List(Array(wateringLogs.enumerated()), id: \.offset) { index, timestamp in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Self.absoluteFormatter.string(from: timestamp))
                                    .font(.body)
                                Text(Self.relativeFormatter.localizedString(for: timestamp, relativeTo: Date()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                activeDateDraft = WateringDateDraft(
                                    plantID: plantID,
                                    plantName: plantName,
                                    mode: .edit(sortedLogIndex: index),
                                    initialDate: timestamp
                                )
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit watering log")

                            Button(role: .destructive) {
                                onDeleteLog(index)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete watering log")
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .trailing) {
                            Button {
                                activeDateDraft = WateringDateDraft(
                                    plantID: plantID,
                                    plantName: plantName,
                                    mode: .edit(sortedLogIndex: index),
                                    initialDate: timestamp
                                )
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                onDeleteLog(index)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("\(plantName) Logs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onClose()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Date") {
                        activeDateDraft = WateringDateDraft(
                            plantID: plantID,
                            plantName: plantName,
                            mode: .add,
                            initialDate: Date()
                        )
                    }
                }
            }
        }
        .sheet(item: $activeDateDraft) { draft in
            WateringDateSheetView(
                draft: draft,
                onSave: { selectedDate in
                    activeDateDraft = nil
                    onSaveDraft(draft, selectedDate)
                },
                onCancel: {
                    activeDateDraft = nil
                }
            )
        }
    }

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

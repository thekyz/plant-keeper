import SwiftUI

struct PlantListView: View {
    @ObservedObject var viewModel: PlantListViewModel

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                List {
                    ForEach(viewModel.rows) { row in
                        PlantRowView(
                            row: row,
                            onWatered: {
                                Task { await viewModel.markWatered(plantID: row.id) }
                            },
                            onCheck: {
                                viewModel.requestCheck(plantID: row.id)
                            },
                            onSnooze: {
                                viewModel.requestSnooze(plantID: row.id)
                            },
                            onAction: { action in
                                Task { await viewModel.handleOverflowAction(action, plantID: row.id) }
                            }
                        )
                    }
                }
                .listStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                #if os(iOS)
                Button {
                    viewModel.startNewPlantDraft()
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.blue, in: Circle())
                        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 12)
                .accessibilityLabel("Add plant")
                #endif
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 12) {
                    Text("Plants")
                        .font(.title.weight(.bold))
                        .lineLimit(1)
                    Spacer()
                    SettingsButton(action: {
                        Task { await viewModel.presentSettings() }
                    }, compact: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
            }
            #endif
            .toolbar {
                #if !os(iOS)
                ToolbarItem {
                    SettingsButton {
                        Task { await viewModel.presentSettings() }
                    }
                }
                ToolbarItem {
                    Button {
                        viewModel.startNewPlantDraft()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                #endif
            }
            .task {
                await viewModel.loadPlants()
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $viewModel.isPresentingAddPlant) {
                AddPlantFlowView(viewModel: viewModel)
            }
            .fullScreenCover(isPresented: $viewModel.isPresentingSettings) {
                SettingsView(viewModel: viewModel)
            }
            #else
            .sheet(isPresented: $viewModel.isPresentingAddPlant) {
                AddPlantFlowView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.isPresentingSettings) {
                SettingsView(viewModel: viewModel)
            }
            #endif
            .sheet(item: $viewModel.activeSheet) { sheet in
                switch sheet {
                case let .wateringDate(draft):
                    WateringDateSheetView(
                        draft: draft,
                        onSave: { selectedDate in
                            Task { await viewModel.saveWateringDate(from: draft, selectedDate: selectedDate) }
                        },
                        onCancel: {
                            viewModel.activeSheet = nil
                        }
                    )
                case let .check(draft):
                    CheckInSheetView(
                        plantName: draft.plantName,
                        onMarkGood: {
                            Task { await viewModel.confirmCheckAllGood(from: draft) }
                        },
                        onSaveNote: { note, photoData in
                            Task { await viewModel.saveCheckObservation(from: draft, note: note, photoData: photoData) }
                        },
                        onCancel: {
                            viewModel.activeSheet = nil
                        }
                    )
                case let .wateringLogs(draft):
                    WateringLogsSheetView(
                        plantName: draft.plantName,
                        plantID: draft.plantID,
                        wateringLogs: row(for: draft.plantID)?.wateringLogs ?? [],
                        onSaveDraft: { dateDraft, selectedDate in
                            Task { await viewModel.saveWateringDate(from: dateDraft, selectedDate: selectedDate) }
                        },
                        onDeleteLog: { sortedLogIndex in
                            Task { await viewModel.deleteWateringLog(plantID: draft.plantID, sortedLogIndex: sortedLogIndex) }
                        },
                        onClose: {
                            viewModel.activeSheet = nil
                        }
                    )
                }
            }
            .alert(
                "Snooze for a day?",
                isPresented: Binding(
                    get: { viewModel.activeSnoozeDraft != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.activeSnoozeDraft = nil
                        }
                    }
                ),
                presenting: viewModel.activeSnoozeDraft
            ) { draft in
                Button("Cancel", role: .cancel) {
                    viewModel.activeSnoozeDraft = nil
                }
                Button("Confirm") {
                    Task { await viewModel.confirmSnooze(from: draft) }
                }
            } message: { draft in
                Text("Snooze watering for \(draft.plantName) by one day.")
            }
            .alert("Error", isPresented: Binding(get: {
                viewModel.errorMessage != nil
            }, set: { newValue in
                if !newValue { viewModel.errorMessage = nil }
            })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
        }
    }

    private func row(for plantID: UUID) -> PlantRowViewModel? {
        viewModel.rows.first(where: { $0.id == plantID })
    }
}

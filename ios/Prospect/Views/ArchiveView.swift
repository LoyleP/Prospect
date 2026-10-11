// Views/ArchiveView.swift
// Archived (soft-deleted) prospects across the organization. Members who can edit may restore them.
import SwiftUI

struct ArchiveView: View {
    @State private var viewModel = ArchiveViewModel()
    @Environment(AppState.self) private var appState

    var body: some View {
        List(viewModel.prospects) { prospect in
            ProspectRow(prospect: prospect)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if appState.canEditProspects {
                    Button {
                        Task { await viewModel.restore(prospect) }
                    } label: {
                        Label("Restaurer", systemImage: "arrow.uturn.left")
                    }
                    .tint(Color.success)
                    }
                }
                .themedRowBackground()
        }
        .themedListBackground()
        .contentMargins(.top, 16, for: .scrollContent)
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if viewModel.isLoading && viewModel.prospects.isEmpty {
                ProgressView()
            } else if !viewModel.isLoading && viewModel.prospects.isEmpty {
                ContentUnavailableView(
                    "Aucun prospect archivé",
                    systemImage: "archivebox",
                    description: Text("Les prospects archivés apparaissent ici. Glissez vers la droite pour restaurer.")
                )
            }
        }
        .alert("Erreur", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }
}

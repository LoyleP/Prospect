// Views/ArchiveView.swift
// Archived (soft-deleted) prospects across the organization. Anyone who can edit may restore.
import SwiftUI

struct ArchiveView: View {
    @State private var viewModel = ArchiveViewModel()
    @State private var toast: Toast?
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            ScreenHeading(label: "Archive", title: "Archive.")
                .listRowInsets(EdgeInsets(top: Space.l, leading: Space.gutter, bottom: Space.s, trailing: Space.gutter))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if viewModel.isLoading && viewModel.prospects.isEmpty {
                ForEach(0..<5, id: \.self) { _ in SkeletonRow().registerRow() }
            } else if viewModel.prospects.isEmpty {
                EmptyStateView(
                    title: "Archive vide.",
                    message: "Glissez un prospect vers la droite pour le restaurer."
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.prospects) { prospect in
                    ProspectRow(prospect: prospect)
                        .registerRow()
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if appState.canEditProspects {
                                Button {
                                    Haptics.success()
                                    Task {
                                        await viewModel.restore(prospect)
                                        toast = Toast(message: "Prospect restauré", style: .success)
                                    }
                                } label: {
                                    Label("Restaurer", systemImage: "arrow.uturn.left")
                                }
                                .tint(Color.success)
                            }
                        }
                }
            }

            Color.clear.frame(height: 90)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .toolbar(.hidden, for: .navigationBar)
        .toast($toast)
        .alert("Erreur", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task { await viewModel.load() }
        .onChange(of: appState.selectedTab) { _, tab in if tab == .archive { Task { await viewModel.load() } } }
        .refreshable { await viewModel.load() }
    }
}

// Views/ObjectivesView.swift
// Admin-only page to set objectives for the current event.
import SwiftUI

struct ObjectivesView: View {
    @State private var viewModel: ObjectivesViewModel
    @Environment(AppState.self) private var appState

    init(session: SessionSummary) {
        _viewModel = State(initialValue: ObjectivesViewModel(session: session))
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Pré-inscrits") {
                        Text("\(viewModel.preRegistered)")
                            .font(.geistMonoHeadline)
                    }
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.preRegistered) },
                                set: { viewModel.preRegistered = Int($0) }
                            ),
                            in: 0...500,
                            step: 5
                        )
                        Stepper("", value: $viewModel.preRegistered, in: 0...500)
                            .labelsHidden()
                    }
                }
                .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Objectif bas (%)") {
                        Text("\(viewModel.rdvTargetLow)%")
                            .font(.geistMonoHeadline)
                    }
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.rdvTargetLow) },
                                set: { viewModel.rdvTargetLow = Int($0) }
                            ),
                            in: 0...100,
                            step: 5
                        )
                        Stepper("", value: $viewModel.rdvTargetLow, in: 0...100)
                            .labelsHidden()
                    }
                }
                .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Objectif haut (%)") {
                        Text("\(viewModel.rdvTargetHigh)%")
                            .font(.geistMonoHeadline)
                    }
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.rdvTargetHigh) },
                                set: { viewModel.rdvTargetHigh = Int($0) }
                            ),
                            in: 0...100,
                            step: 5
                        )
                        Stepper("", value: $viewModel.rdvTargetHigh, in: 0...100)
                            .labelsHidden()
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("L'objectif bas et haut définissent la cible de taux de closing RDV affichée dans le tableau de bord. Laisser à 0 pour ne pas afficher de cible.")
            }
            .themedRowBackground()

            Section {
                if appState.programs.isEmpty {
                    Text("Aucun programme défini pour l'organisation.")
                        .foregroundStyle(.secondary)
                }
                ForEach(appState.programs) { f in
                    HStack {
                        Circle().fill(f.swiftUIColor).frame(width: 8, height: 8)
                        Text(f.name)
                            .font(.geistSubheadline)
                        Spacer()
                        TextField("0", value: Binding(
                            get: { viewModel.objective(for: f) },
                            set: { viewModel.setObjective($0, for: f) }
                        ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.geistMonoHeadline)
                        .frame(width: 80)
                    }
                }
            } header: {
                Text("Objectifs par programme")
            } footer: {
                Text("Nombre de prospects ciblé par programme. Laisser à 0 si non défini.")
            }
            .themedRowBackground()

            Section {
                Button {
                    Task { await viewModel.save() }
                } label: {
                    if viewModel.isSaving {
                        ProgressView().tint(.white).frame(maxWidth: .infinity)
                    } else {
                        Text("Enregistrer")
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(viewModel.isSaving || !viewModel.hasChanges)
                .listRowBackground(Color.accent.opacity(viewModel.hasChanges ? 1 : 0.35))
            }
        }
        .themedListBackground()
        .themedNavigationBar()
        .contentMargins(.top, 16, for: .scrollContent)
        .navigationTitle("Objectifs")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Erreur", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Sauvegardé", isPresented: $viewModel.saveSuccess) {
            Button("OK") { viewModel.saveSuccess = false }
        } message: {
            Text("Les objectifs ont été mis à jour.")
        }
    }
}

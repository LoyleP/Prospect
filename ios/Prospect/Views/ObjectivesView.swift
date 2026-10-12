// Views/ObjectivesView.swift
// Admin-only: the expected turnout, the RDV-rate target and a count per program for one event.
import SwiftUI

struct ObjectivesView: View {
    @State private var viewModel: ObjectivesViewModel
    @State private var toast: Toast?
    @Environment(AppState.self) private var appState

    init(session: SessionSummary) {
        _viewModel = State(initialValue: ObjectivesViewModel(session: session))
    }

    var body: some View {
        @Bindable var vm = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                ScreenHeading(label: vm.session.name, title: "Objectifs.")

                NumberedSection(number: "01", title: "Présence attendue") {
                    row("Pré-inscrits", nil) {
                        QuantityControl(value: $vm.preRegistered, range: 0...5000, step: 5)
                    }
                }

                NumberedSection(number: "02", title: "Cible du taux de RDV") {
                    VStack(alignment: .leading, spacing: Space.l) {
                        row("Objectif bas", nil) { QuantityControl(value: $vm.rdvTargetLow, range: 0...100, step: 5, suffix: " %") }
                        row("Objectif haut", nil) { QuantityControl(value: $vm.rdvTargetHigh, range: 0...100, step: 5, suffix: " %") }
                    }
                }

                NumberedSection(number: "03", title: "Par programme") {
                    VStack(spacing: 0) {
                        if appState.programs.isEmpty {
                            Text("Aucun programme.")
                                .font(.textSub).foregroundStyle(Color.inkSecondary)
                        }
                        ForEach(appState.programs) { program in
                            HStack(spacing: Space.m) {
                                RoundedRectangle(cornerRadius: 2).fill(program.swiftUIColor).frame(width: 10, height: 10)
                                Text(program.name).font(.textSub.weight(.semibold)).foregroundStyle(Color.inkPrimary).lineLimit(1)
                                Spacer(minLength: Space.s)
                                QuantityControl(
                                    value: Binding(get: { vm.objective(for: program) }, set: { vm.setObjective($0, for: program) }),
                                    range: 0...5000, step: 5
                                )
                            }
                            .padding(.vertical, Space.s)
                            Rule()
                        }
                    }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .background(PaperBackground())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                Task {
                    await viewModel.save()
                    if viewModel.saveSuccess { toast = Toast(message: "Objectifs enregistrés", style: .success); viewModel.saveSuccess = false }
                }
            } label: {
                ZStack {
                    Text("Enregistrer").opacity(vm.isSaving ? 0 : 1)
                    if vm.isSaving { ProgressView().tint(Color.onInk) }
                }
            }
            .buttonStyle(.primary)
            .disabled(vm.isSaving || !vm.hasChanges)
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            .background(Color.surfaceBackground.opacity(0.96).ignoresSafeArea(edges: .bottom))
        }
        .toast($toast)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Erreur", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private func row<Control: View>(_ title: String, _ hint: String?, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.textHeadline).foregroundStyle(Color.inkPrimary)
                if let hint { Text(hint).font(.textFootnote).foregroundStyle(Color.inkTertiary) }
            }
            Spacer(minLength: Space.s)
            control()
        }
    }
}

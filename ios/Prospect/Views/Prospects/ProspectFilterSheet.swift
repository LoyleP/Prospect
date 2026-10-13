// Views/Prospects/ProspectFilterSheet.swift
// Every filter in one sheet, with a live result count on the apply button.
import SwiftUI

struct ProspectFilterSheet: View {
    var viewModel: ProspectListViewModel
    let programs: [Program]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack {
                    Text(L("Filters"))
                        .font(.displayS)
                        .foregroundStyle(Color.inkPrimary)
                    Spacer()
                    if viewModel.hasActiveFilters {
                        Button(L("Reset")) { Haptics.tap(); withAnimation(.curve()) { viewModel.clearFilters() } }
                            .font(.textSub.weight(.medium))
                            .foregroundStyle(Color.inkTertiary)
                            .frame(minHeight: 44)
                    }
                }

                // One grouped block of rows; each opens a native multi-choice menu.
                VStack(spacing: 0) {
                    filterRow(L("Status"), value: summary(viewModel.filterStatuts.map(\.shortLabel))) {
                        ForEach(Statut.allCases) { st in
                            check(st.shortLabel, isOn: viewModel.filterStatuts.contains(st)) {
                                viewModel.filterStatuts.toggle(member: st, isOn: !viewModel.filterStatuts.contains(st))
                            }
                        }
                    }
                    if !programs.isEmpty {
                        Rule().padding(.leading, Space.l)
                        filterRow(L("Program"), value: summary(programs.filter { viewModel.filterPrograms.contains($0.id) }.map(\.name))) {
                            ForEach(programs) { p in
                                check(p.name, isOn: viewModel.filterPrograms.contains(p.id)) {
                                    viewModel.filterPrograms.toggle(member: p.id, isOn: !viewModel.filterPrograms.contains(p.id))
                                }
                            }
                        }
                    }
                    Rule().padding(.leading, Space.l)
                    filterRow(L("Level"), value: summary(viewModel.filterNiveaux.map(\.rawValue))) {
                        ForEach(NiveauActuel.allCases) { n in
                            check(n.rawValue, isOn: viewModel.filterNiveaux.contains(n)) {
                                viewModel.filterNiveaux.toggle(member: n, isOn: !viewModel.filterNiveaux.contains(n))
                            }
                        }
                    }
                    if viewModel.agentNames.count > 1 {
                        Rule().padding(.leading, Space.l)
                        filterRow(L("Recorded by"), value: summary(Array(viewModel.filterAgents))) {
                            ForEach(viewModel.agentNames, id: \.self) { name in
                                check(name, isOn: viewModel.filterAgents.contains(name)) {
                                    viewModel.filterAgents.toggle(member: name, isOn: !viewModel.filterAgents.contains(name))
                                }
                            }
                        }
                    }
                }
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.l)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                dismiss()
            } label: {
                let n = viewModel.filteredProspects.count
                Text(n == 0 ? L("No results") : L("Show \(n) prospects"))
                    .contentTransition(.numericText())
            }
            .buttonStyle(.primary)
            .animation(.curve(), value: viewModel.filteredProspects.count)
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            .background(Color.surfaceBackground.opacity(0.96).ignoresSafeArea(edges: .bottom))
        }
        .presentationDragIndicator(.visible)
    }

    private func summary(_ names: [String]) -> String {
        switch names.count {
        case 0: return L("All")
        case 1: return names[0]
        default: return L("\(names.count) selected")
        }
    }

    private func check(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            if isOn { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private func filterRow<Items: View>(_ title: String, value: String, @ViewBuilder items: () -> Items) -> some View {
        Menu {
            items()
        } label: {
            HStack(spacing: Space.s) {
                Text(title)
                    .font(.textBody)
                    .foregroundStyle(Color.inkPrimary)
                Spacer(minLength: Space.m)
                Text(value)
                    .font(.textBody)
                    .foregroundStyle(value == L("All") ? Color.inkTertiary : Color.accent)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(.horizontal, Space.l)
            .frame(minHeight: 55)
            .contentShape(Rectangle())
        }
    }
}

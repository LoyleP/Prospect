// Views/DesignSystem/CodeTicket.swift
// An access code presented as an admission ticket: the code large on top, torn-off actions below.
import SwiftUI

struct CodeTicket: View {
    let title: String
    let detail: String
    let code: String
    let shareText: String
    var onCopy: () -> Void
    var onRegenerate: () -> Void

    var body: some View {
        TicketStack {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(title)
                    .font(.textSub.weight(.medium))
                    .foregroundStyle(Color.inkTertiary)
                Text(code)
                    .font(.numeral(44))
                    .tracking(6)
                    .foregroundStyle(Color.inkPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .accessibilityLabel("Code : \(code.map(String.init).joined(separator: " "))")
                if !detail.isEmpty {
                    Text(detail)
                        .font(.textFootnote)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.l)
            .padding(.top, Space.l)
            .padding(.bottom, Space.s)
        } stub: {
            HStack(spacing: 0) {
                action("Copier", "doc.on.doc", onCopy)
                ShareLink(item: shareText) {
                    stubLabel("Partager", "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                action("Renouveler", "arrow.triangle.2.circlepath", onRegenerate)
            }
            .padding(.horizontal, Space.s)
            .padding(.bottom, Space.xs)
        }
    }

    private func action(_ title: String, _ icon: String, _ run: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            run()
        } label: { stubLabel(title, icon) }
        .buttonStyle(.plain)
    }

    private func stubLabel(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
            Text(title).font(.textCaption.weight(.semibold))
        }
        .foregroundStyle(Color.inkPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: 55)
        .contentShape(Rectangle())
    }
}

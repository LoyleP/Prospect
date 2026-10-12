// Views/DesignSystem/Toast.swift
// A solid ink bar that slides in from the top, then leaves on its own.
import SwiftUI

struct Toast: Equatable, Identifiable {
    enum Style { case success, info, error }

    let id = UUID()
    var message: String
    var style: Style = .success

    var marker: Color {
        switch style {
        case .success: return .success
        case .info:    return .onInk.opacity(0.7)
        case .error:   return .error
        }
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(toast.marker).frame(width: 8, height: 8)
                        Text(toast.message)
                            .font(.textSub.weight(.semibold))
                            .foregroundStyle(Color.onInk)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.inkPrimary, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(toast.id)
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(2.2))
                        withAnimation(.curve(0.25)) { self.toast = nil }
                    }
                    .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .animation(.curve(0.4), value: toast)
            .sensoryFeedback(trigger: toast) { _, new in
                guard let new else { return nil }
                switch new.style {
                case .success: return .success
                case .error:   return .error
                case .info:    return .impact(weight: .light)
                }
            }
    }
}

extension View {
    /// Shows `toast` at the top of this view; set it to nil to dismiss early.
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}

//
//  ErrorPresentation.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//

import SwiftUI

struct ErrorPresentationModifier: ViewModifier {
    let center: ErrorCenter
    @State private var hostID = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { center.registerHost(hostID) }
            .onDisappear { center.unregisterHost(hostID) }
            .alert(
                center.presented?.error.title ?? "Something Went Wrong",
                isPresented: alertBinding,
                presenting: center.presented
            ) { item in
                if let recovery = item.recovery {
                    Button(recovery.title, role: recovery.role == .destructive ? .destructive : nil) {
                        recovery.handler()
                    }
                }
                Button(item.recovery == nil ? "OK" : "Not Now", role: .cancel) {}
            } message: { item in
                Text(item.error.fullMessage)
            }
            .overlay(alignment: .top) {
                if center.isActiveHost(hostID), let toast = center.toast {
                    ToastView(error: toast.error) { center.dismissToast() }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: center.toast?.id)
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { center.presented != nil && center.isActiveHost(hostID) },
            set: { isPresented in
                if !isPresented { center.dismissPresented() }
            }
        )
    }
}

struct ToastView: View {
    let error: AppError
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(AppTheme.copper)
                .font(.title3)
            Text(error.message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.beige)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.beige.opacity(0.7))
                    .padding(6)
            }
            .accessibilityLabel("Dismiss message")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.deeperTeal.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.copper.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func errorPresentation(_ center: ErrorCenter) -> some View {
        modifier(ErrorPresentationModifier(center: center))
    }
}

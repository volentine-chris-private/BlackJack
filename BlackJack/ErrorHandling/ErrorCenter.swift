//
//  ErrorCenter.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//

import Foundation
import Observation
import OSLog

struct RecoveryOption {
    enum Role { case normal, destructive }

    let title: String
    var role: Role = .normal
    let handler: @MainActor () -> Void
}

struct PresentedError: Identifiable {
    let id = UUID()
    let error: AppError
    let recovery: RecoveryOption?
}

struct ErrorLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let error: AppError
    let context: String
}

@Observable
@MainActor
final class ErrorCenter {
    private(set) var presented: PresentedError?
    private(set) var toast: PresentedError?
    private(set) var history: [ErrorLogEntry] = []
    private(set) var hostStack: [UUID] = []

    @ObservationIgnored private var alertQueue: [PresentedError] = []
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var queueTask: Task<Void, Never>?

    private let maxHistory = 100
    private let toastDuration: UInt64 = 3_200_000_000

    // MARK: Reporting

    func report(
        _ error: Error,
        context: String = "",
        recovery: RecoveryOption? = nil,
        file: String = #fileID,
        line: Int = #line
    ) {
        if error is CancellationError {
            AppLogger.app.debug("Cancellation ignored (\(context, privacy: .public))")
            return
        }

        let appError = AppError.wrap(error)
        record(appError, context: context)
        log(appError, context: context, file: file, line: line)

        let item = PresentedError(error: appError, recovery: recovery)
        switch appError.severity {
        case .info:
            break
        case .warning:
            showToast(item)
        case .error, .critical:
            enqueueAlert(item)
        }
    }

    func report<T>(_ result: Result<T, AppError>, context: String = "") {
        if case .failure(let error) = result { report(error, context: context) }
    }

    // MARK: Alerts

    func dismissPresented() {
        presented = nil
        guard !alertQueue.isEmpty else { return }
        let next = alertQueue.removeFirst()
        queueTask?.cancel()
        queueTask = Task { [weak self] in
            // Give SwiftUI time to finish dismissing the previous alert
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.presented = next
        }
    }

    private func enqueueAlert(_ item: PresentedError) {
        if presented == nil {
            presented = item
            return
        }
        let isDuplicate = presented?.error == item.error || alertQueue.contains { $0.error == item.error }
        if !isDuplicate { alertQueue.append(item) }
    }

    // MARK: Toasts

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    private func showToast(_ item: PresentedError) {
        toast = item
        toastTask?.cancel()
        let id = item.id
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.toastDuration ?? 3_000_000_000)
            guard !Task.isCancelled, self?.toast?.id == id else { return }
            self?.toast = nil
        }
    }

    // MARK: Hosts

    func registerHost(_ id: UUID) {
        hostStack.removeAll { $0 == id }
        hostStack.append(id)
    }

    func unregisterHost(_ id: UUID) {
        hostStack.removeAll { $0 == id }
    }

    func isActiveHost(_ id: UUID) -> Bool {
        hostStack.last == id
    }

    // MARK: Logging

    private func record(_ error: AppError, context: String) {
        history.append(ErrorLogEntry(date: Date(), error: error, context: context))
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
    }

    private func log(_ error: AppError, context: String, file: String, line: Int) {
        let text = "[\(error.code)] \(error.message) - \(context) @ \(file):\(line)"
        switch error.severity {
        case .info: AppLogger.app.info("\(text, privacy: .public)")
        case .warning: AppLogger.app.notice("\(text, privacy: .public)")
        case .error: AppLogger.app.error("\(text, privacy: .public)")
        case .critical: AppLogger.app.critical("\(text, privacy: .public)")
        }
    }
}

//
//  NetworkMonitor.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation
import Network
import os

final class NetworkMonitor: @unchecked Sendable {
    enum Status: Sendable, Equatable {
        case unknown
        case satisfied
        case unsatisfied
    }

    private let monitor: NWPathMonitor
    private let state = OSAllocatedUnfairLock(initialState: Status.unknown)
    private let expensive = OSAllocatedUnfairLock(initialState: false)
    private let queue = DispatchQueue(
        label: Bundle.main.bundleIdentifier ?? AppConfig.bundleIdBackup,
        qos: .utility)

    init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let newStatus: Status
            switch path.status {
            case .satisfied: newStatus = .satisfied
            case .unsatisfied: newStatus = .unsatisfied
            case .requiresConnection: newStatus = .unknown
            @unknown default: newStatus = .unknown
            }
            let isExpensive = path.isExpensive
            self.state.withLock { $0 = newStatus }
            self.expensive.withLock { $0 = isExpensive }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    var status: Status { state.withLock { $0 } }

    var isConnected: Bool { status != .unsatisfied }

    /// True on cellular or a personal hotspot
    var isExpensive: Bool { expensive.withLock { $0 } }
}

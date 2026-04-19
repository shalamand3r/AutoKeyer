import Combine
import Foundation

/// SwiftUI-friendly wrapper around the shared permission state; in a non-bundled host, accessibility stays `false` and never updates.
@MainActor
public final class PermissionsObserver: ObservableObject {
    @Published public private(set) var accessibility: Bool = false

    public init() {
        guard let center = AskForPermission.sharedCenter() else { return }
        let state = center.statusState
        accessibility = state.isAccessibilityGranted
        state.$isAccessibilityGranted.assign(to: &$accessibility)
    }

    public func status(for kind: PermissionKind) -> Bool {
        switch kind {
        case .accessibility: return accessibility
        case .screenRecording, .inputMonitoring, .fullDiskAccess, .developerTools, .appManagement:
            return false
        }
    }
}

extension AskForPermission {
    /// Emits the current authorization state for `kind` plus every change
    /// until the consumer cancels. Finishes immediately with a single
    /// `false` when `isAvailable` is `false`.
    public static func statusUpdates(for kind: PermissionKind) -> AsyncStream<Bool> {
        AsyncStream { continuation in
            guard let center = AskForPermission.sharedCenter() else {
                continuation.yield(false)
                continuation.finish()
                return
            }
            let publisher = center.statusState.publisher(for: kind)
            let task = Task { @MainActor in
                for await value in publisher.values {
                    continuation.yield(value)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

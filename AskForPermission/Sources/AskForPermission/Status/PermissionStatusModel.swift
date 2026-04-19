import ApplicationServices
import Combine

@MainActor
final class PermissionStatusModel: ObservableObject {
    @Published private(set) var isAccessibilityGranted: Bool = false
    @Published var activePermissionRequest: PermissionKind?
    @Published var inProgressPermission: PermissionKind?

    private var timer: Timer?

    init() {
        refresh()
        startPolling()
    }

    deinit {
        timer?.invalidate()
    }

    func isGranted(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .accessibility: return isAccessibilityGranted
        case .screenRecording, .inputMonitoring, .fullDiskAccess, .developerTools, .appManagement:
            return false
        }
    }

    func refresh() {
        let ax = AXIsProcessTrusted()
        if ax != isAccessibilityGranted { isAccessibilityGranted = ax }
    }

    func publisher(for kind: PermissionKind) -> AnyPublisher<Bool, Never> {
        switch kind {
        case .accessibility: return $isAccessibilityGranted.eraseToAnyPublisher()
        case .screenRecording, .inputMonitoring, .fullDiskAccess, .developerTools, .appManagement:
            return Just(false).eraseToAnyPublisher()
        }
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

}

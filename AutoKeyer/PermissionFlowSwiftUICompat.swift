import SwiftUI
import AppKit
import AskForPermission

// local wrapper so we don't depend on the package's SwiftUI modifier being visible to sourcekit
extension View {
    func autoKeyerRequestsPermission(
        _ kind: PermissionKind,
        onResult: @escaping (PermissionRequestResult) -> Void = { _ in }
    ) -> some View {
        modifier(AutoKeyerRequestsPermissionModifier(kind: kind, onResult: onResult))
    }
}

private struct AutoKeyerRequestsPermissionModifier: ViewModifier {
    let kind: PermissionKind
    let onResult: (PermissionRequestResult) -> Void

    @State private var anchorView: NSView?
    @State private var isRunning = false

    func body(content: Content) -> some View {
        content
            .background(AutoKeyerPermissionAnchorView(anchorView: $anchorView))
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard !isRunning else { return }
                    guard let anchorView else {
                        onResult(.unavailable(PermissionRequestError(
                            code: .missingHostApplicationBundle,
                            message: "autoKeyerRequestsPermission requires a host NSView."
                        )))
                        return
                    }

                    isRunning = true
                    Task { @MainActor in
                        let result = await AskForPermission.request(kind, from: anchorView)
                        isRunning = false
                        onResult(result)
                    }
                }
            )
    }
}

private struct AutoKeyerPermissionAnchorView: NSViewRepresentable {
    @Binding var anchorView: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        DispatchQueue.main.async { anchorView = view }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { anchorView = nsView }
    }
}


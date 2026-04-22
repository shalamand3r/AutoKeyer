import AppKit
import Combine
import SwiftUI

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        // keep it looking "focused" even when our panel isn't key
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

@MainActor
final class FlightReplicantModel: ObservableObject {
    @Published var sourceImage: NSImage?
    @Published var targetImage: NSImage?
    @Published var progress: CGFloat = 0
    @Published var blurRadius: CGFloat = 0
    @Published var cornerRadius: CGFloat = 12
    @Published var shadowOpacity: CGFloat = 0
    @Published var contentSize: CGSize = .zero
}

struct FlightReplicantContentView: View {
    @ObservedObject var model: FlightReplicantModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let showTransitionChrome = model.blurRadius > 0.01 || model.progress < 0.999

        ZStack {
            // During the morph we blur the replicant as a whole. If the
            // crossfading snapshots contain any transparency (especially
            // around rounded corners and strokes), the blur can "pull in"
            // whatever is behind the replicant and the surface reads like it
            // changes material at the end. Give the in-flight surface its own
            // consistent backdrop that matches the final panel chrome.
            if showTransitionChrome {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    .overlay(
                        RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.10 : 0.06))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
                            .strokeBorder(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.11)
                                    : Color.white.opacity(0.35),
                                lineWidth: 1.5
                            )
                    )
            }

            // No `.aspectRatio(...)` — both images are stretched to fill the
            // replicant's rect so a row-sized source snapshot grows smoothly
            // into the full panel-sized target snapshot without letterboxing.
            ZStack {
                if let src = model.sourceImage {
                    Image(nsImage: src)
                        .resizable()
                        .interpolation(.high)
                        .opacity(1 - model.progress)
                }
                if let tgt = model.targetImage {
                    Image(nsImage: tgt)
                        .resizable()
                        .interpolation(.high)
                        .opacity(model.progress)
                }
            }
            // Composite the image stack as a single unit *before* blurring, so
            // the blur applies uniformly to the rasterized result.
            // `.compositingGroup()` is the lightweight path here — unlike
            // `.drawingGroup()`, it doesn't allocate a Metal surface that can
            // produce a yellow "render failed" placeholder on macOS 26 when the
            // content's color space / size exceeds the group's limits.
            .compositingGroup()
            .blur(radius: model.blurRadius)
        }
        .frame(width: model.contentSize.width, height: model.contentSize.height)
        .clipShape(RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
final class FlightReplicantWindow: NSPanel {
    // Padding around the content inside the window so shadows/blur don't clip.
    static let chromeInset: CGFloat = 40

    let model = FlightReplicantModel()
    private let hostingView: NSHostingView<FlightReplicantContentView>

    init() {
        self.hostingView = NSHostingView(rootView: FlightReplicantContentView(model: model))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        // `.canJoinAllSpaces` is what keeps the overlay visible across Stage
        // Manager transitions — when Settings activates, Stage Manager moves
        // our app's normal windows off-screen, and without this flag the
        // replicant gets hidden with them. `.transient` is omitted because
        // Stage Manager treats transient windows as part of the owning app's
        // Stage and pulls them aside with it.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        // Match the docked guide panel's shadow style during flight.
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true

        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setSourceImage(_ image: NSImage?) { model.sourceImage = image }
    func setTargetImage(_ image: NSImage?) { model.targetImage = image }

    /// Positions the replicant so that the logical content rect lives at
    /// `contentFrame`, expanded by `chromeInset` on every side so that blur
    /// halos and drop shadows have room to render outside the content.
    func apply(
        frame contentFrame: NSRect,
        cornerRadius: CGFloat,
        progress: CGFloat,
        shadowOpacity: CGFloat,
        blurRadius: CGFloat
    ) {
        let inset = Self.chromeInset
        let windowFrame = NSRect(
            x: contentFrame.minX - inset,
            y: contentFrame.minY - inset,
            width: contentFrame.width + inset * 2,
            height: contentFrame.height + inset * 2
        )
        setFrame(windowFrame, display: false)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.cornerRadius = cornerRadius
            model.progress = progress
            model.shadowOpacity = shadowOpacity
            model.blurRadius = blurRadius
            model.contentSize = contentFrame.size
        }
    }
}

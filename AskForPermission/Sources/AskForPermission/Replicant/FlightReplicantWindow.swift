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
            // consistent backdrop that doesn't re-sample whatever is behind
            // the replicant while it's flying (desktop/wallpaper can read
            // darker/bluer than the final docked state).
            if showTransitionChrome {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous))
            }

            // No `.aspectRatio(...)` — both images are stretched to fill the
            // replicant's rect so a row-sized source snapshot grows smoothly
            // into the full panel-sized target snapshot without letterboxing.
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
        .frame(width: model.contentSize.width, height: model.contentSize.height)
        .clipShape(RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous))
        // Blur the whole replicant surface (backdrop + snapshots) as one unit.
        .compositingGroup()
        .blur(radius: model.blurRadius)
        // Keep the flight shadow subtle so it doesn't read like the surface
        // changes when handing off to the docked panel.
        .shadow(
            color: .black.opacity((colorScheme == .dark ? 0.35 : 0.18) * model.shadowOpacity),
            radius: 22,
            x: 0,
            y: -2
        )
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
        // Use SwiftUI shadow in the content so we can tune it to match the
        // docked panel without the window-level shadow reading too heavy.
        hasShadow = false
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

#if DEBUG
@MainActor
struct FlightReplicantContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FlightReplicantContentView(model: makeModel(progress: 0.5, blurRadius: 10))
                .previewDisplayName("Flight Replicant (Mid)")

            FlightReplicantContentView(model: makeModel(progress: 1.0, blurRadius: 0))
                .previewDisplayName("Flight Replicant (Done)")
        }
        .frame(width: 420, height: 220)
        .padding(24)
    }

    private static func makeModel(progress: CGFloat, blurRadius: CGFloat) -> FlightReplicantModel {
        let model = FlightReplicantModel()
        model.progress = progress
        model.blurRadius = blurRadius
        model.cornerRadius = 22
        model.shadowOpacity = 1
        model.contentSize = CGSize(width: 340, height: 120)

        model.sourceImage = makeSampleImage(size: model.contentSize, title: "source")
        model.targetImage = makeSampleImage(size: model.contentSize, title: "target")
        return model
    }

    private static func makeSampleImage(size: CGSize, title: String) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 22, yRadius: 22).fill()

        let badgeRect = NSRect(x: 18, y: size.height / 2 - 16, width: 32, height: 32)
        NSColor.systemOrange.setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 8, yRadius: 8).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        NSString(string: "\(title) row").draw(at: NSPoint(x: 64, y: size.height / 2 - 10), withAttributes: attrs)

        image.unlockFocus()
        return image
    }
}
#endif

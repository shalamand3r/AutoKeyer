// ContentView.swift
// AutoKeyer

import SwiftUI
import AskForPermission
import CoreGraphics

private extension Color {
    static var autoKeyerAccent: Color { Color(nsColor: NSColor.controlAccentColor) }
    static var autoKeyerRandomOrange: Color { Color.orange }
}

struct PopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct RollingTimeText: View {
    let seconds: Double
    let font: Font
    let color: Color

    private var roundedSeconds: Int { max(0, Int(seconds.rounded())) }
    private var minutes: Int { roundedSeconds / 60 }
    private var leftoverSeconds: Int { roundedSeconds % 60 }

    var body: some View {
        if #available(macOS 14.0, *) {
            if roundedSeconds < 60 {
                HStack(spacing: 0) {
                    Text(roundedSeconds, format: .number)
                        .contentTransition(.numericText(value: Double(roundedSeconds)))
                        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: roundedSeconds)
                    Text("s")
                }
                .font(font)
                .foregroundColor(color)
                .animation(.spring(response: 0.28, dampingFraction: 0.88), value: roundedSeconds)
            } else {
                HStack(spacing: 0) {
                    Text(minutes, format: .number)
                        .contentTransition(.numericText(value: Double(minutes)))
                        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: minutes)
                    Text("m ")
                    Text(leftoverSeconds, format: .number)
                        .contentTransition(.numericText(value: Double(leftoverSeconds)))
                        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: leftoverSeconds)
                    Text("s")
                }
                .font(font)
                .foregroundColor(color)
                .animation(.spring(response: 0.28, dampingFraction: 0.88), value: minutes * 100 + leftoverSeconds)
            }
        } else {
            // fallback for older macos (no wheel anim)
            let fallback = roundedSeconds < 60 ? "\(roundedSeconds)s" : "\(minutes)m \(leftoverSeconds)s"
            Text(fallback)
                .font(font)
                .foregroundColor(color)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var tintColor: Color
    var isDisabled: Bool
    var onChanged: (Double) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let trackColor = colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.08)

        Slider(value: $value, in: range)
            .tint(tintColor)
            .disabled(isDisabled)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(trackColor)
                    .frame(height: 5)
            )
            .onChange(of: value) { newValue in
                onChanged(newValue)
            }
    }
}

private struct SettingsRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden()
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

struct ContentView: View {
    @ObservedObject var manager: AutoKeyerManager
    @State private var showFluctuationSettings = false
    @State private var hasHaptickedAtEdge = false
    @State private var lastHapticStep: Int = 15
    @State private var isHoveringUpdateBadge = false
    @State private var updatePulse = false
    @State private var isStartingPermissionFlow = false
    @State private var showPermissionCompletePlaceholder = false
    @GestureState private var isPressingPermissionCTA = false
    private let fullTitle = "AutoKeyer"

    private var appVersionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v" + (short ?? "?")
    }

    private var latestVersionText: String {
        guard let latestTag = manager.latestReleaseTag else { return appVersionText }
        return "v\(latestTag)"
    }

    private var titleVersionText: String {
        guard manager.hasUpdateAvailable, isHoveringUpdateBadge else { return appVersionText }
        return "\(appVersionText) → \(latestVersionText)"
    }

    private var delayDisplayText: String {
        manager.isRandomMode ? "RANDOM" : String(format: "%.2fs", manager.baseDelay)
    }

    var body: some View {
        VStack(spacing: 0) {
            if manager.showPermissionAlert {
                permissionView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                headerSection
                mainInterface
            }
        }
        .frame(width: 300, height: 430)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.showPermissionAlert)
    }

    var headerSection: some View {
        HStack(spacing: 6) {
            Text(fullTitle)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
            Text(titleVersionText)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            if manager.hasUpdateAvailable, let updateURL = manager.latestReleaseURL {
                Button {
                    NSWorkspace.shared.open(updateURL)
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                        .opacity(updatePulse ? 0.55 : 1.0)
                }
                .help("New version available!")
                .buttonStyle(PopButtonStyle())
                .onHover { hovering in
                    isHoveringUpdateBadge = hovering
                }
            }
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showFluctuationSettings.toggle()
                }
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(showFluctuationSettings ? .autoKeyerAccent : .secondary.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .background(showFluctuationSettings ? Color.autoKeyerAccent.opacity(0.15) : Color.clear)
                    .cornerRadius(8)
            }
            .buttonStyle(PopButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .layoutPriority(1)
        .onChange(of: manager.hasUpdateAvailable) { hasUpdateAvailable in
            if hasUpdateAvailable {
                updatePulse = true
            } else {
                updatePulse = false
            }
        }
        .onAppear {
            updatePulse = manager.hasUpdateAvailable
        }
        .task(id: manager.hasUpdateAvailable) {
            guard manager.hasUpdateAvailable else {
                updatePulse = false
                return
            }

            while !Task.isCancelled && manager.hasUpdateAvailable {
                try? await Task.sleep(nanoseconds: 1_450_000_000)
                guard manager.hasUpdateAvailable, !Task.isCancelled else { break }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.9)) {
                        updatePulse.toggle()
                    }
                }
            }
        }
    }
    
    var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsRow(
                title: "Keystroke Variation",
                subtitle: "Adds variation to typing delay",
                isOn: $manager.enableFluctuation,
                isDisabled: manager.isRandomMode || (manager.isTyping && !manager.isPaused)
            )

            Divider().opacity(0.4)

            SettingsRow(
                title: "Show Time Remaining",
                subtitle: "Displays value in menu bar",
                isOn: $manager.showMenuBarTimer
            )
        }
        .padding(16)
        .background(Color.autoKeyerAccent.opacity(0.15))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.autoKeyerAccent.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .layoutPriority(1)
    }

    var mainInterface: some View {
        VStack(spacing: 0) {
            if showFluctuationSettings {
                settingsSection
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
            }

            VStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        Label("Keystroke Delay", systemImage: "timer")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        if manager.isRandomMode {
                            Text(delayDisplayText)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.autoKeyerRandomOrange)
                                .frame(width: 60, height: 14, alignment: .trailing)
                                .transition(.opacity)
                        } else {
                            if #available(macOS 14.0, *) {
                                HStack(spacing: 0) {
                                    Text(manager.baseDelay, format: .number.precision(.fractionLength(2)))
                                        .contentTransition(.numericText(value: manager.baseDelay))
                                    Text("s")
                                }
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                                .animation(.spring(response: 0.28, dampingFraction: 0.88), value: manager.baseDelay)
                                .frame(width: 60, height: 14, alignment: .trailing)
                                .transition(.opacity)
                            } else {
                                Text(delayDisplayText)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .frame(width: 60, height: 14, alignment: .trailing)
                                    .transition(.opacity)
                            }
                        }
                    }
                    
                    CustomSlider(
                        value: $manager.baseDelay,
                        range: 0.01...0.51,
                        tintColor: manager.isRandomMode ? .autoKeyerRandomOrange : .autoKeyerAccent,
                        isDisabled: manager.isTyping && !manager.isPaused
                    ) { newValue in
                        let currentStep = Int(newValue * 100)
                        if currentStep != lastHapticStep && currentStep > 1 && currentStep < 51 {
                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                            lastHapticStep = currentStep
                        }

                        if newValue <= 0.01 || newValue >= 0.51 {
                            if !hasHaptickedAtEdge {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                                hasHaptickedAtEdge = true
                            }
                        } else {
                            hasHaptickedAtEdge = false
                        }
                    }
                }

                .padding(15)
                .background(manager.isRandomMode ? Color.autoKeyerRandomOrange.opacity(0.15) : Color.primary.opacity(0.04))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(manager.isRandomMode ? Color.autoKeyerRandomOrange.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1))
                .animation(.easeInOut(duration: 0.3), value: manager.isRandomMode)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .layoutPriority(1)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Clipboard", systemImage: "doc.on.clipboard")
                        .font(.caption.bold()).foregroundColor(.secondary)
                    
                    if manager.clipboardImage == nil && !manager.clipboardText.isEmpty {
                        if manager.isTyping {
                            Text(manager.remainingTime)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(nsColor: NSColor.controlAccentColor))
                                .frame(height: 12)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.primary.opacity(0.05)).cornerRadius(4)
                        } else {
                            HStack(spacing: 0) {
                                Text("~")
                                RollingTimeText(
                                    seconds: manager.estimatedSecondsRemaining,
                                    font: .system(size: 10, weight: .bold, design: .monospaced),
                                    color: .secondary
                                )
                            }
                            .frame(height: 12)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05)).cornerRadius(4)
                        }
                    }
                    Spacer()
                    Button { manager.readClipboard() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(PopButtonStyle())
                    .opacity(0.6)
                    .disabled(manager.isTyping && !manager.isPaused)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.1))
                    if let image = manager.clipboardImage {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(6)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    } else {
                        ScrollView {
                            Group {
                                if manager.clipboardText.isEmpty {
                                    Text("Clipboard is empty...")
                                        .foregroundColor(.secondary)
                                } else {
                                    let typedPart = String(manager.clipboardText.prefix(manager.currentIndex))
                                    let remainingPart = String(manager.clipboardText.dropFirst(manager.currentIndex))
                                    (Text(typedPart).foregroundColor(Color(nsColor: NSColor.controlAccentColor)) + Text(remainingPart))
                                }
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.clipboardImage != nil)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            VStack(spacing: 12) {
                ZStack {
                    if manager.isPaused {
                        HStack(spacing: 12) {
                            Button(action: { manager.stopProcess() }) {
                                Label("STOP", systemImage: "stop.fill")
                                    .font(.headline).frame(maxWidth: .infinity).frame(height: 44)
                                    .background(Color.red.gradient)
                                    .foregroundColor(.white).cornerRadius(12)
                            }
                            .buttonStyle(PopButtonStyle())

                            Button(action: { manager.resumeProcess() }) {
                                Label("RESUME", systemImage: "play.fill")
                                    .font(.headline).frame(maxWidth: .infinity).frame(height: 44)
                                    .background(Color.green.gradient)
                                    .foregroundColor(.white).cornerRadius(12)
                            }
                            .buttonStyle(PopButtonStyle())
                        }
                        .transition(.opacity)
                    } else {
                        let isDisabled = manager.isTyping || manager.clipboardText.isEmpty || manager.clipboardImage != nil
                        Button(action: { manager.checkAndStart() }) {
                            HStack {
                                Image(systemName: "keyboard.fill")
                                Text(manager.isTyping ? "TYPING..." : (manager.clipboardImage != nil ? "IMAGES NOT SUPPORTED" : "START TYPING"))
                            }
                            .font(.headline).frame(maxWidth: .infinity).frame(height: 44)
                            .background(isDisabled ? Color.gray.gradient : Color(nsColor: NSColor.controlAccentColor).gradient)
                            .foregroundColor(.white).cornerRadius(12)
                            .shadow(color: Color(nsColor: NSColor.controlAccentColor).opacity(isDisabled ? 0 : 0.3), radius: 5, y: 3)
                        }
                        .buttonStyle(PopButtonStyle())
                        .disabled(isDisabled)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: manager.isPaused)

                HStack(spacing: 4) {
                    Text("Hold **⌃ Control** or right click")
                    Image(systemName: "keyboard.fill")
                    Text("to abort")
                    Text("•")
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(PopButtonStyle()).underline()
                }
                .font(.system(size: 10)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .layoutPriority(1)
        }
    }

    var permissionView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            ZStack {
                Circle().fill(Color.autoKeyerAccent.opacity(0.05))
                    .frame(width: 110, height: 110)
                Circle().fill(Color.autoKeyerAccent.opacity(0.075))
                    .frame(width: 80, height: 80)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 47.5))
                    .foregroundStyle(Color.autoKeyerAccent.gradient)
                    .shadow(color: Color.autoKeyerAccent.opacity(0.4), radius: 8, y: 4)
            }
            .padding(.bottom, 20)

            VStack(spacing: 10) {
                Text("Missing Permissions")
                    .font(.system(.title2, design: .rounded).bold())

                Text("In order to simulate keystrokes, enable AutoKeyer in System Settings → Privacy & Security → Accessibility")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            VStack(spacing: 12) {
                ZStack {
                    Text("COMPLETE IN SYSTEM SETTINGS")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundColor(.secondary.opacity(0.9))
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    Color.secondary.opacity(0.55),
                                    style: StrokeStyle(lineWidth: 1.3, dash: [6, 4])
                                )
                        )
                        .opacity(showPermissionCompletePlaceholder ? 1 : 0)

                    Label("Open System Settings", systemImage: "gearshape.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(nsColor: NSColor.controlAccentColor).gradient)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: Color(nsColor: NSColor.controlAccentColor).opacity(0.3), radius: 5, y: 3)
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .opacity(showPermissionCompletePlaceholder ? 0 : 1)
                }
                .animation(.easeInOut(duration: 0.18), value: showPermissionCompletePlaceholder)
                .scaleEffect(isPressingPermissionCTA && !showPermissionCompletePlaceholder ? 0.96 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressingPermissionCTA)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .requestsPermission(.accessibility) { _ in
                    NotificationCenter.default.post(name: .permissionFlowActiveChanged, object: false)
                    isStartingPermissionFlow = false
                    showPermissionCompletePlaceholder = false
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isPressingPermissionCTA) { _, state, _ in
                            state = true
                        }
                )
                .simultaneousGesture(TapGesture().onEnded {
                    guard !isStartingPermissionFlow else { return }
                    isStartingPermissionFlow = true
                    NotificationCenter.default.post(name: .permissionFlowActiveChanged, object: true)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showPermissionCompletePlaceholder = true
                        }
                    }

                    Task {
                        // wait until system settings is actually on screen, then close the popover
                        let didOpen = await waitForSystemSettingsWindow(timeoutSeconds: 10.0)
                        guard didOpen else {
                            await MainActor.run {
                                NotificationCenter.default.post(name: .permissionFlowActiveChanged, object: false)
                                isStartingPermissionFlow = false
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    showPermissionCompletePlaceholder = false
                                }
                            }
                            return
                        }

                        try? await Task.sleep(nanoseconds: 900_000_000)
                        await MainActor.run {
                            NotificationCenter.default.post(name: NSNotification.Name("ClosePopover"), object: nil)
                            NotificationCenter.default.post(name: .permissionFlowActiveChanged, object: false)
                            isStartingPermissionFlow = false
                            showPermissionCompletePlaceholder = false
                        }
                    }
                })
                .prepareForPermissionsFlow()
                .allowsHitTesting(!showPermissionCompletePlaceholder)

                Button(action: { manager.showPermissionAlert = false }) {
                    Text("Go Back")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
                .buttonStyle(PopButtonStyle())
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // reset if we come back here
            isStartingPermissionFlow = false
            showPermissionCompletePlaceholder = false
        }
    }

    private func waitForSystemSettingsWindow(timeoutSeconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if systemSettingsIsVisible() { return true }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return false
    }

    private func systemSettingsIsVisible() -> Bool {
        let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let candidateOwnerNames = ["System Settings", "System Preferences"]
        return windowInfoList.contains { info in
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  candidateOwnerNames.contains(ownerName) else {
                return false
            }
            return (info[kCGWindowLayer as String] as? Int ?? 0) == 0
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#Preview {
    ContentView(manager: AutoKeyerManager())
}

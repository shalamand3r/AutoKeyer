// ContentView.swift
// AutoKeyer

import SwiftUI

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
            .animation(.easeInOut(duration: 0.3), value: tintColor)
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

struct ContentView: View {
    @ObservedObject var manager: AutoKeyerManager
    @State private var showFluctuationHelp = false
    @State private var hasHaptickedAtEdge = false
    @State private var lastHapticStep: Int = 15
    private let fullTitle = "AutoKeyer"

    private var appVersionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v" + (short ?? "?")
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
        .frame(width: 300, height: 480)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.showPermissionAlert)
    }

    var headerSection: some View {
        HStack {
            Text(fullTitle)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .frame(height: 24, alignment: .leading)
            Spacer()
            Text(appVersionText)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .opacity(0.4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    var mainInterface: some View {
        VStack(spacing: 0) {
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
                                .foregroundColor(.orange)
                                .frame(width: 60, height: 14, alignment: .trailing)
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
                            } else {
                                Text(delayDisplayText)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .frame(width: 60, height: 14, alignment: .trailing)
                            }
                        }
                    }
                    
                    CustomSlider(
                        value: $manager.baseDelay,
                        range: 0.01...0.51,
                        tintColor: manager.isRandomMode ? .orange : .blue,
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

                Divider().opacity(0.2)

                HStack {
                    Toggle("Fluctuations", isOn: $manager.enableFluctuation)
                        .toggleStyle(.switch)
                        .disabled(manager.isRandomMode || (manager.isTyping && !manager.isPaused))
                    Spacer()
                    Button { showFluctuationHelp.toggle() } label: {
                        Image(systemName: "questionmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showFluctuationHelp, arrowEdge: .trailing) {
                        Text("Adds random variation to each stroke for a more human feel.")
                            .font(.caption).frame(width: 160).padding(10)
                    }
                }
            }
            .padding(15)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Clipboard", systemImage: "doc.on.clipboard")
                        .font(.caption.bold()).foregroundColor(.secondary)
                    
                    if manager.clipboardImage == nil && !manager.clipboardText.isEmpty {
                        if manager.isTyping {
                            Text(manager.remainingTime)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
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
                    }.buttonStyle(PopButtonStyle()).opacity(0.6).disabled(manager.isTyping && !manager.isPaused)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.2))
                    if let image = manager.clipboardImage {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(8)
                    } else {
                        ScrollView {
                            Group {
                                if manager.clipboardText.isEmpty {
                                    Text("Clipboard is empty...")
                                        .foregroundColor(.secondary)
                                } else {
                                    let typedPart = String(manager.clipboardText.prefix(manager.currentIndex))
                                    let remainingPart = String(manager.clipboardText.dropFirst(manager.currentIndex))
                                    (Text(typedPart).foregroundColor(.blue) + Text(remainingPart))
                                }
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            VStack(spacing: 12) {
                Toggle("Show remaining time in menu bar", isOn: $manager.showMenuBarTimer)
                    .font(.system(size: 11, weight: .medium))
                    .toggleStyle(.checkbox)
                    .foregroundColor(.secondary)
                    .fixedSize()
                
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
                            .background(isDisabled ? Color.gray.gradient : Color.blue.gradient)
                            .foregroundColor(.white).cornerRadius(12)
                            .shadow(color: .blue.opacity(isDisabled ? 0 : 0.3), radius: 5, y: 3)
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
        }
    }

    var permissionView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            ZStack {
                Circle().fill(Color.orange.opacity(0.06))
                    .frame(width: 110, height: 110)
                Circle().fill(Color.orange.opacity(0.10))
                    .frame(width: 80, height: 80)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.orange.gradient)
                    .shadow(color: .orange.opacity(0.4), radius: 8, y: 4)
            }
            .padding(.bottom, 8)

            VStack(spacing: 8) {
                Text("Accessibility Required")
                    .font(.system(.title2, design: .rounded).bold())

                Text("AutoKeyer needs permission to simulate keystrokes. Enable it in System Settings to continue.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                Button(action: { manager.openSettings() }) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                        Text("Open System Settings")
                    }
                    .font(.headline).frame(maxWidth: .infinity).frame(height: 48)
                    .background(Color.blue.gradient)
                    .foregroundColor(.white).cornerRadius(12)
                    .shadow(color: .blue.opacity(0.3), radius: 5, y: 3)
                }.buttonStyle(PopButtonStyle())

                Button(action: { manager.showPermissionAlert = false }) {
                    Text("Cancel")
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 48)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundColor(.primary).cornerRadius(12)
                }.buttonStyle(PopButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

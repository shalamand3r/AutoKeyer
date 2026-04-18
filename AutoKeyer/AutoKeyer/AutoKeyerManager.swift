// AutoKeyerManager.swift
// AutoKeyer

import SwiftUI
import ApplicationServices
import Combine

class AutoKeyerManager: ObservableObject {
    static let shared = AutoKeyerManager()
    
    var cancellables = Set<AnyCancellable>()
    private var remainingTimeTimer: Timer?
    private var accessibilityCheckTimer: Timer?
    
    @Published var clipboardText: String = ""
    @Published var clipboardImage: NSImage? = nil
    private var clipboardCharacters: [Character] = []
    
    private var userEnabledFluctuations: Bool = false
    @Published var baseDelay: Double = 0.15 {
        didSet {
            if isRandomMode {
                if enableFluctuation {
                    userEnabledFluctuations = true
                    enableFluctuation = false
                }
            } else {
                if userEnabledFluctuations {
                    enableFluctuation = true
                    userEnabledFluctuations = false
                }
            }
            updateRemainingTimeIfPaused()
        }
    }
    
    @Published var enableFluctuation: Bool = false
    @Published var showMenuBarTimer: Bool = true
    @Published var isTyping: Bool = false
    @Published var isPaused: Bool = false
    @Published var showPermissionAlert: Bool = false
    @Published var remainingTime: String = "0s"
    @Published var currentIndex: Int = 0
    
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var typingTask: Task<Void, Never>?
    private var globalEventMonitor: Any?

    var isRandomMode: Bool { baseDelay >= 0.50 }

    private var expectedSecondsPerChar: Double {
        if isRandomMode {
            return 0.3755
        }

        return max(0.001, baseDelay + (enableFluctuation ? 0.05 : 0))
    }

    var estimatedSecondsRemaining: Double {
        guard !clipboardText.isEmpty && clipboardImage == nil else { return 0 }
        let count = max(0, clipboardCharacters.count - currentIndex)
        return Double(count) * expectedSecondsPerChar
    }

    var estimatedTime: String {
        guard !clipboardText.isEmpty && clipboardImage == nil else { return "0s" }
        return formatTime(estimatedSecondsRemaining)
    }

    private func formatTime(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", max(0, seconds))
        } else {
            return String(format: "%dm %ds", Int(seconds) / 60, Int(seconds) % 60)
        }
    }

    private func updateRemainingTimeIfPaused() {
        if isPaused { remainingTime = estimatedTime }
    }

    init() {
        readClipboard()
        setupClipboardMonitoring()
        setupGlobalAbortMonitor()
        setupRemainingTimeAutoUpdate()
        setupAccessibilityRecheck()
    }

    private func setupRemainingTimeAutoUpdate() {
        remainingTimeTimer?.invalidate()
        remainingTimeTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            if self.isTyping || self.isPaused {
                self.remainingTime = self.estimatedTime
            }
        }
    }

    private func setupAccessibilityRecheck() {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if self.isTyping {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
                let isTrusted = AXIsProcessTrustedWithOptions(options)
                if !isTrusted {
                    self.stopProcess()
                    self.showPermissionAlert = true
                }
            }
        }
    }

    func readClipboard() {
        let pb = NSPasteboard.general
        
        if let image = NSImage(pasteboard: pb) {
            if isTyping { stopProcess() }
            self.clipboardImage = image
            self.clipboardText = ""
            self.clipboardCharacters = []
            return
        }
        
        self.clipboardImage = nil
        if let newText = pb.string(forType: .string) {
            if clipboardText != newText {
                if isTyping { stopProcess() }
                clipboardText = newText
                clipboardCharacters = Array(newText)
                currentIndex = 0
            }
        } else {
            if isTyping { stopProcess() }
            clipboardText = ""
            clipboardCharacters = []
            currentIndex = 0
        }
    }

    private func setupClipboardMonitoring() {
        // checking the clipboard constantly (apple won't just tell us when it changes)
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            if NSPasteboard.general.changeCount != self.lastChangeCount {
                self.lastChangeCount = NSPasteboard.general.changeCount
                self.readClipboard()
            }
        }
    }

    func checkAndStart() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        
        if isTrusted {
            if isTyping {
                withAnimation { isPaused = true }
            } else {
                startTypingProcess()
            }
        } else {
            self.isTyping = false
            self.showPermissionAlert = true
        }
    }

    func stopProcess() {
        typingTask?.cancel()
        withAnimation(.easeInOut) {
            isTyping = false
            isPaused = false
            currentIndex = 0
            remainingTime = "0s"
        }
    }

    func resumeProcess() {
        withAnimation(.easeInOut) { isPaused = false }
        NotificationCenter.default.post(name: NSNotification.Name("ClosePopover"), object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.hide(nil) }
    }

    // start typing the clipboard content, with a little delay to let the user get their hands off the keyboard after clicking "start" (ok github copilot suggestion LOL)
    private func startTypingProcess() {
        if clipboardText.isEmpty { return }
        isTyping = true
        isPaused = false
        currentIndex = 0
        
        NotificationCenter.default.post(name: NSNotification.Name("ClosePopover"), object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.hide(nil) }
        
        typingTask?.cancel()
        typingTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if self.isTyping { await self.typeClipboardContent() }
        }
    }

    private func typeClipboardContent() async {
        while !Task.isCancelled {
            let state = await MainActor.run { () -> (isTyping: Bool, isPaused: Bool, isActive: Bool, char: String?, base: Double, fluct: Bool, random: Bool) in
                if !self.isTyping { return (false, false, false, nil, 0, false, false) }
                
                // don't type into self ui
                if self.isPaused || NSApp.isActive { return (true, true, true, "WAIT", 0, false, false) }
                
                if self.currentIndex < self.clipboardCharacters.count {
                    let char = String(self.clipboardCharacters[self.currentIndex])
                    self.remainingTime = self.estimatedTime
                    return (true, false, false, char, self.baseDelay, self.enableFluctuation, self.isRandomMode)
                }
                return (false, false, false, nil, 0, false, false)
            }

            if !state.isTyping || state.char == nil { break }
            
            if state.char == "WAIT" {
                try? await Task.sleep(nanoseconds: 100_000_000)
                continue
            }

            self.typeString(state.char!)
            
            let delay = state.random ? Double.random(in: 0.001...0.75) : state.base
            var finalDelay = delay
            if state.fluct && !state.random {
                finalDelay += Double.random(in: -0.15...0.25)
            }
            
            let sleepNanos = UInt64(max(0.001, finalDelay) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: sleepNanos)
            } catch {
                break
            }

            await MainActor.run { self.currentIndex += 1 }
        }

        if Task.isCancelled { return }
        await MainActor.run { self.stopProcess() }
    }

    private func typeString(_ string: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16Chars = Array(string.utf16)
        guard let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        
        eventDown.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        eventUp.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        
        eventDown.post(tap: .cghidEventTap)
        eventUp.post(tap: .cghidEventTap)
    }

    private func setupGlobalAbortMonitor() {
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            if event.modifierFlags.contains(.control) {
                DispatchQueue.main.async { self.stopProcess() }
            }
        }
    }

    func openSettings() {
        // try to trigger the system-level accessibility prompt first (does this even work????)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        NotificationCenter.default.post(name: NSNotification.Name("ClosePopover"), object: nil)
        NSApp.hide(nil)
        self.showPermissionAlert = false
    }
}

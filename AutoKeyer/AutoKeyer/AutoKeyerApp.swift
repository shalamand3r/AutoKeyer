// AutoKeyerApp.swift
// AutoKeyer

import SwiftUI
import Combine

@main
struct AutoKeyerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var manager = AutoKeyerManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 480)
        popover.behavior = .transient
        popover.animates = true
        // bridge swiftui to appkit popover
        popover.contentViewController = NSHostingController(rootView: ContentView(manager: manager))
        self.popover = popover

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusBarItem.button {
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(handleMenuBarClick)
            updateIcon()
        }

        Publishers.CombineLatest4(manager.$isTyping, manager.$isPaused, manager.$remainingTime, manager.$showMenuBarTimer)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                self?.updateIcon()
            }
            .store(in: &manager.cancellables)

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ClosePopover"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.popover.performClose(nil)
        }

        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.togglePopover()
            }
        }
    }

    @objc func handleMenuBarClick() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
        
        if isRightClick {
            if manager.isPaused {
                manager.resumeProcess()
            } else if manager.isTyping {
                manager.stopProcess()
            } else {
                manager.checkAndStart()
            }
        } else {
            if manager.isTyping && !manager.isPaused {
                withAnimation(.spring()) {
                    manager.isPaused = true
                }
            }
            togglePopover()
        }
    }

    func updateIcon() {
        guard let button = statusBarItem.button else { return }
        
        let iconName: String
        if manager.isTyping && manager.isPaused {
            iconName = "pause.fill"
        } else if manager.isTyping {
            iconName = "keyboard.fill"
        } else {
            iconName = "keyboard"
        }
        
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "AutoKeyer")
        
        if manager.isTyping && manager.showMenuBarTimer {
            button.title = " " + (manager.isPaused ? "PAUSED" : manager.remainingTime)
        } else {
            button.title = ""
        }
    }

    func togglePopover() {
        if let button = statusBarItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                NSApp.unhide(nil)
                NSApp.activate(ignoringOtherApps: true)
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
}

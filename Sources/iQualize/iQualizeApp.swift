import AppKit
import CoreGraphics
import Foundation

@available(macOS 14.2, *)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    private var audioEngine: AudioEngine!
    private var presetStore: PresetStore!
    private var wasRunningBeforeSleep = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check screen/audio capture permission — CATap requires it
        let hasAccess = CGPreflightScreenCaptureAccess()
        if !hasAccess {
            CGRequestScreenCaptureAccess()
        }

        setupMainMenu()

        audioEngine = AudioEngine()
        presetStore = PresetStore()
        menuBarController = MenuBarController(audioEngine: audioEngine, presetStore: presetStore)

        // Sleep/wake handling
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleSleep()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWake()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            menuBarController?.openEQWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        audioEngine.stop()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About iQualize", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit iQualize", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (Undo/Redo)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func handleSleep() {
        wasRunningBeforeSleep = audioEngine.isRunning
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    private func handleWake() {
        if wasRunningBeforeSleep {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.audioEngine.setEnabled(true)
            }
        }
    }
}

// MARK: - Entry Point

@main
struct iQualizeMain {
    // Strong reference — NSApplication.delegate is weak, so without this
    // Swift can deallocate the AppDelegate (and the entire menu bar icon).
    nonisolated(unsafe) static var appDelegate: AnyObject?

    static func main() {
        if #available(macOS 14.2, *) {
            let app = NSApplication.shared
            let launchState = iQualizeState.load()
            app.setActivationPolicy(launchState.hideFromDock ? .accessory : .regular)
            let delegate = AppDelegate()
            appDelegate = delegate
            app.delegate = delegate
            app.run()
        } else {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let alert = NSAlert()
            alert.messageText = "iQualize requires macOS 14.2 or newer"
            alert.informativeText = "Core Audio Taps are only available on macOS 14.2+."
            alert.runModal()
        }
    }
}

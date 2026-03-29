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

    func applicationWillTerminate(_ notification: Notification) {
        audioEngine.stop()
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
            app.setActivationPolicy(.accessory)
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

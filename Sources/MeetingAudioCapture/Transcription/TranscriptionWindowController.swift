import AppKit
import SwiftUI

@MainActor
final class TranscriptionWindowController {
    private var window: NSWindow?

    func show(session: TranscriptionSession, language: AppLanguage) {
        let viewModel = TranscriptionViewModel(session: session, language: language)
        let hostingController = NSHostingController(rootView: TranscriptionView(model: viewModel))
        let title = AppLocalizer.text(.transcription, language: language)

        if let window {
            window.contentViewController = hostingController
            window.title = title
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentViewController: hostingController)
        window.title = title
        window.setContentSize(NSSize(width: 760, height: 560))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

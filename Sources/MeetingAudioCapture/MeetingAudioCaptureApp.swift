import AppKit
import SwiftUI

@main
struct MeetingAudioCaptureApp: App {
    var body: some Scene {
        MenuBarExtra("MeetingAudioCapture", systemImage: "waveform") {
            Text("MeetingAudioCapture")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

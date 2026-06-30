import AppKit
import SwiftUI

@main
struct MeetingAudioCaptureApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            RecorderMenuView(model: model)
        } label: {
            Label("MeetingAudioCapture", systemImage: model.menuBarIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.isActive ? .red : .primary)
        }
        .menuBarExtraStyle(.window)
    }
}

import AppKit
import SwiftUI

@main
struct MeetingAudioCaptureApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            RecorderMenuView(model: model)
        } label: {
            MenuBarIndicatorLabel(indicator: model.menuBarIndicator)
                .accessibilityLabel("MeetingAudioCapture")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarIndicatorLabel: View {
    let indicator: MenuBarIndicator

    var body: some View {
        Image(nsImage: MenuBarIndicatorImageRenderer.image(for: indicator))
    }
}

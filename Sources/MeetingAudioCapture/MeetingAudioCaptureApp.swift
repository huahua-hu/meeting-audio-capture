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
        HStack(spacing: 2) {
            Image(systemName: indicator.symbolName)
                .symbolRenderingMode(.hierarchical)
            switch indicator.badge {
            case .dot:
                Circle()
                    .fill(.secondary)
                    .frame(width: 5, height: 5)
            case .pause:
                Image(systemName: "pause.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.secondary)
            case .none, .warning:
                EmptyView()
            }
        }
    }
}

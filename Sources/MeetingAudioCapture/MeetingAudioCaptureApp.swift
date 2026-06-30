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
        ZStack(alignment: .topTrailing) {
            Image(systemName: indicator.symbolName)
                .symbolRenderingMode(.hierarchical)
            switch indicator.badge {
            case .dot:
                Circle()
                    .fill(.secondary)
                    .frame(width: 4, height: 4)
                    .offset(x: 2, y: -1)
            case .pause:
                Image(systemName: "pause.fill")
                    .font(.system(size: 5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .offset(x: 4, y: -1)
            case .none, .warning:
                EmptyView()
            }
        }
    }
}

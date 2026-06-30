import SwiftUI

struct AudioLevelView: View {
    let label: String
    let level: AudioLevel
    let tint: Color

    private var normalized: Double {
        guard level.peakDBFS.isFinite else { return 0 }
        return Double(min(1, max(0, (level.peakDBFS + 60) / 60)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(level.peakDBFS.isFinite ? "\(Int(level.peakDBFS.rounded())) dBFS" : "No signal")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: normalized)
                .tint(tint)
                .accessibilityLabel(label)
                .accessibilityValue(level.peakDBFS.isFinite ? "\(Int(level.peakDBFS.rounded())) decibels full scale" : "No signal")
        }
    }
}

import AVFAudio
import Foundation

struct RealtimePCMEncoder {
    private var pending: [Float] = []

    mutating func encode(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let channels = buffer.floatChannelData else { return Data() }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        pending.reserveCapacity(pending.count + frameCount)
        for frame in 0..<frameCount {
            var sample: Float = 0
            for channel in 0..<channelCount { sample += channels[channel][frame] }
            pending.append(sample / Float(channelCount))
        }

        let outputCount = pending.count / 3
        var output = Data(capacity: outputCount * MemoryLayout<Int16>.size)
        for index in 0..<outputCount {
            let base = index * 3
            let averaged = (pending[base] + pending[base + 1] + pending[base + 2]) / 3
            var value = Int16(max(-1, min(1, averaged)) * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { output.append(contentsOf: $0) }
        }
        pending.removeFirst(outputCount * 3)
        return output
    }
}

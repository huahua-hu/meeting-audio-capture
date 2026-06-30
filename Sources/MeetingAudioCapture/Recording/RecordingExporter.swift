import AVFoundation
import Foundation

struct RecordingExportResult: Equatable, Sendable {
    let systemSucceeded: Bool
    let microphoneSucceeded: Bool
    let mixSucceeded: Bool
}

struct RecordingExporter: Sendable {
    func export(files: RecordingFiles) async -> RecordingExportResult {
        let systemSucceeded = await exportTrack(
            source: files.systemTemporaryCAF,
            destination: files.systemM4A
        )
        let microphoneSucceeded = await exportTrack(
            source: files.microphoneTemporaryCAF,
            destination: files.microphoneM4A
        )
        let mixSucceeded: Bool
        if systemSucceeded, microphoneSucceeded {
            mixSucceeded = await exportMix(
                system: files.systemM4A,
                microphone: files.microphoneM4A,
                destination: files.mixedM4A
            )
        } else {
            mixSucceeded = false
        }

        if systemSucceeded { try? FileManager.default.removeItem(at: files.systemTemporaryCAF) }
        if microphoneSucceeded { try? FileManager.default.removeItem(at: files.microphoneTemporaryCAF) }
        return RecordingExportResult(
            systemSucceeded: systemSucceeded,
            microphoneSucceeded: microphoneSucceeded,
            mixSucceeded: mixSucceeded
        )
    }

    private func exportTrack(source: URL, destination: URL) async -> Bool {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else { return false }
        do {
            try await session.export(to: destination, as: .m4a)
            return true
        } catch {
            return false
        }
    }

    private func exportMix(system: URL, microphone: URL, destination: URL) async -> Bool {
        do {
            try? FileManager.default.removeItem(at: destination)
            let composition = AVMutableComposition()
            let systemAsset = AVURLAsset(url: system)
            let microphoneAsset = AVURLAsset(url: microphone)
            guard let systemSource = try await systemAsset.loadTracks(withMediaType: .audio).first,
                  let microphoneSource = try await microphoneAsset.loadTracks(withMediaType: .audio).first,
                  let systemTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ),
                  let microphoneTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else { return false }

            let systemDuration = try await systemAsset.load(.duration)
            let microphoneDuration = try await microphoneAsset.load(.duration)
            try systemTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: systemDuration),
                of: systemSource,
                at: .zero
            )
            try microphoneTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: microphoneDuration),
                of: microphoneSource,
                at: .zero
            )

            let systemParameters = AVMutableAudioMixInputParameters(track: systemTrack)
            systemParameters.setVolume(1, at: .zero)
            let microphoneParameters = AVMutableAudioMixInputParameters(track: microphoneTrack)
            microphoneParameters.setVolume(1, at: .zero)
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = [systemParameters, microphoneParameters]

            guard let session = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetAppleM4A
            ) else { return false }
            session.audioMix = audioMix
            try await session.export(to: destination, as: .m4a)
            return true
        } catch {
            return false
        }
    }
}

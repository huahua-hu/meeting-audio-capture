# Audio Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build first-version transcription for recordings created by MeetingAudioCapture, labeling preserved system audio as Interviewer and preserved microphone audio as Me.

**Architecture:** Keep capture unchanged and add a focused transcription feature area. Pure model, path-resolution, merge, and Markdown rendering logic is tested independently; Speech framework access is isolated behind a protocol so the app can use `SFSpeechRecognizer` while tests use deterministic fakes. The menu bar panel only opens a separate SwiftUI transcription window and does not own transcription state.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest, Apple Speech framework, Foundation file APIs.

## Global Constraints

- First version only supports recordings produced by this app.
- Do not import arbitrary audio files.
- Do not perform speaker diarization on mixed audio.
- Do not translate text.
- Do not summarize transcripts.
- Do not add real-time transcription while recording.
- Do not add manual speaker relabeling.
- Use current app language as the recognition locale: English UI -> `en-US`, Simplified Chinese UI -> `zh-CN`.
- Do not add a separate per-recording recognition language selector.
- Save transcript Markdown next to the `.m4a` as `<recording-name>-transcript.md`.
- Preserve the existing `Scripts/create-dmg.sh` worktree change; do not include it in commits for this feature unless explicitly requested.

---

## File Structure

- Create `Sources/MeetingAudioCapture/Transcription/TranscriptionModels.swift`: speaker, segment, result, and error model types.
- Create `Sources/MeetingAudioCapture/Transcription/TranscriptionSession.swift`: resolve app-owned diagnostics paths from an exported `.m4a`.
- Create `Sources/MeetingAudioCapture/Transcription/TranscriptFormatter.swift`: timestamp and Markdown/body rendering.
- Create `Sources/MeetingAudioCapture/Transcription/TranscriptionService.swift`: recognition protocol, Apple Speech implementation, authorization, two-track orchestration, and segment merge.
- Create `Sources/MeetingAudioCapture/Transcription/TranscriptionViewModel.swift`: observable UI state, start/retry, copy, save.
- Create `Sources/MeetingAudioCapture/Views/TranscriptionView.swift`: standalone transcript UI.
- Create `Sources/MeetingAudioCapture/Transcription/TranscriptionWindowController.swift`: AppKit owner for the separate SwiftUI window.
- Modify `Sources/MeetingAudioCapture/AppModel.swift`: retain a window controller and expose a narrow open action.
- Modify `Sources/MeetingAudioCapture/Views/RecorderMenuView.swift`: show transcription action when a completed recording exists.
- Modify `Sources/MeetingAudioCapture/Localization/AppLocalization.swift`: localized strings for transcription UI and errors.
- Modify `Config/Info.plist`: add `NSSpeechRecognitionUsageDescription`.
- Create tests:
  - `Tests/MeetingAudioCaptureTests/TranscriptionSessionTests.swift`
  - `Tests/MeetingAudioCaptureTests/TranscriptFormatterTests.swift`
  - `Tests/MeetingAudioCaptureTests/TranscriptionServiceTests.swift`
  - `Tests/MeetingAudioCaptureTests/TranscriptionViewModelTests.swift`

---

### Task 1: Transcription Session and Models

**Files:**
- Create: `Sources/MeetingAudioCapture/Transcription/TranscriptionModels.swift`
- Create: `Sources/MeetingAudioCapture/Transcription/TranscriptionSession.swift`
- Test: `Tests/MeetingAudioCaptureTests/TranscriptionSessionTests.swift`

**Interfaces:**
- Produces: `enum TranscriptionSpeaker: String, CaseIterable, Sendable`
- Produces: `struct TranscriptionSegment: Equatable, Sendable`
- Produces: `struct TranscriptionResult: Equatable, Sendable`
- Produces: `enum TranscriptionError: Error, Equatable, LocalizedError, Sendable`
- Produces: `struct TranscriptionSession: Equatable, Sendable`
- Produces: `static func TranscriptionSession.resolve(outputFile:fileManager:) throws -> TranscriptionSession`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MeetingAudioCaptureTests/TranscriptionSessionTests.swift`:

```swift
@testable import MeetingAudioCapture
import Foundation
import XCTest

final class TranscriptionSessionTests: XCTestCase {
    func testResolvesDiagnosticsTracksFromOutputFile() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appending(path: "Meeting-20260706-091500.m4a")
        let diagnostics = root.appending(path: ".diagnostics/Meeting-20260706-091500", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: diagnostics, withIntermediateDirectories: true)
        try Data("m4a".utf8).write(to: output)
        try Data("system".utf8).write(to: diagnostics.appending(path: "system.caf"))
        try Data("microphone".utf8).write(to: diagnostics.appending(path: "microphone.caf"))

        let session = try TranscriptionSession.resolve(outputFile: output)

        XCTAssertEqual(session.outputFile, output)
        XCTAssertEqual(session.recordingName, "Meeting-20260706-091500")
        XCTAssertEqual(session.diagnosticsDirectory, diagnostics)
        XCTAssertEqual(session.systemAudioFile, diagnostics.appending(path: "system.caf"))
        XCTAssertEqual(session.microphoneAudioFile, diagnostics.appending(path: "microphone.caf"))
    }

    func testThrowsWhenDiagnosticsDirectoryIsMissing() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appending(path: "Meeting-20260706-091500.m4a")
        try Data("m4a".utf8).write(to: output)

        XCTAssertThrowsError(try TranscriptionSession.resolve(outputFile: output)) { error in
            XCTAssertEqual(error as? TranscriptionError, .missingDiagnostics)
        }
    }

    func testThrowsWhenTrackFileIsMissing() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appending(path: "Meeting-20260706-091500.m4a")
        let diagnostics = root.appending(path: ".diagnostics/Meeting-20260706-091500", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: diagnostics, withIntermediateDirectories: true)
        try Data("m4a".utf8).write(to: output)
        try Data("system".utf8).write(to: diagnostics.appending(path: "system.caf"))

        XCTAssertThrowsError(try TranscriptionSession.resolve(outputFile: output)) { error in
            XCTAssertEqual(error as? TranscriptionError, .missingTrack("microphone.caf"))
        }
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TranscriptionSessionTests`

Expected: FAIL with errors for missing `TranscriptionSession` and `TranscriptionError`.

- [ ] **Step 3: Implement models and session resolution**

Create `Sources/MeetingAudioCapture/Transcription/TranscriptionModels.swift`:

```swift
import Foundation

enum TranscriptionSpeaker: String, CaseIterable, Sendable {
    case interviewer
    case me
}

struct TranscriptionSegment: Equatable, Sendable {
    let startTime: TimeInterval
    let speaker: TranscriptionSpeaker
    let text: String
}

struct TranscriptionResult: Equatable, Sendable {
    let session: TranscriptionSession
    let segments: [TranscriptionSegment]
    let warnings: [TranscriptionError]
}

enum TranscriptionError: Error, Equatable, LocalizedError, Sendable {
    case missingDiagnostics
    case missingTrack(String)
    case speechNotAuthorized
    case recognizerUnavailable(String)
    case recognitionFailed(TranscriptionSpeaker, String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDiagnostics:
            return "The recording diagnostics folder is missing."
        case let .missingTrack(filename):
            return "The recording diagnostics track is missing: \(filename)."
        case .speechNotAuthorized:
            return "Speech recognition permission is required."
        case let .recognizerUnavailable(locale):
            return "Speech recognition is unavailable for \(locale)."
        case let .recognitionFailed(speaker, details):
            return "Recognition failed for \(speaker.rawValue): \(details)"
        case let .saveFailed(details):
            return "Unable to save transcript: \(details)"
        }
    }
}
```

Create `Sources/MeetingAudioCapture/Transcription/TranscriptionSession.swift`:

```swift
import Foundation

struct TranscriptionSession: Equatable, Sendable {
    let outputFile: URL
    let recordingName: String
    let diagnosticsDirectory: URL
    let systemAudioFile: URL
    let microphoneAudioFile: URL

    static func resolve(
        outputFile: URL,
        fileManager: FileManager = .default
    ) throws -> TranscriptionSession {
        let recordingName = outputFile.deletingPathExtension().lastPathComponent
        let diagnosticsDirectory = outputFile
            .deletingLastPathComponent()
            .appending(path: ".diagnostics/\(recordingName)", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: diagnosticsDirectory.path) else {
            throw TranscriptionError.missingDiagnostics
        }

        let systemAudioFile = diagnosticsDirectory.appending(path: "system.caf")
        guard fileManager.fileExists(atPath: systemAudioFile.path) else {
            throw TranscriptionError.missingTrack("system.caf")
        }

        let microphoneAudioFile = diagnosticsDirectory.appending(path: "microphone.caf")
        guard fileManager.fileExists(atPath: microphoneAudioFile.path) else {
            throw TranscriptionError.missingTrack("microphone.caf")
        }

        return TranscriptionSession(
            outputFile: outputFile,
            recordingName: recordingName,
            diagnosticsDirectory: diagnosticsDirectory,
            systemAudioFile: systemAudioFile,
            microphoneAudioFile: microphoneAudioFile
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TranscriptionSessionTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingAudioCapture/Transcription/TranscriptionModels.swift Sources/MeetingAudioCapture/Transcription/TranscriptionSession.swift Tests/MeetingAudioCaptureTests/TranscriptionSessionTests.swift
git commit -m "feat: resolve transcription sessions"
```

---

### Task 2: Transcript Formatting

**Files:**
- Create: `Sources/MeetingAudioCapture/Transcription/TranscriptFormatter.swift`
- Test: `Tests/MeetingAudioCaptureTests/TranscriptFormatterTests.swift`

**Interfaces:**
- Consumes: `TranscriptionSession`, `TranscriptionSegment`, `TranscriptionSpeaker`, `TranscriptionResult`
- Produces: `struct TranscriptFormatter`
- Produces: `static func timestamp(_ seconds: TimeInterval) -> String`
- Produces: `static func speakerLabel(_ speaker: TranscriptionSpeaker) -> String`
- Produces: `static func markdown(for result: TranscriptionResult) -> String`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MeetingAudioCaptureTests/TranscriptFormatterTests.swift`:

```swift
@testable import MeetingAudioCapture
import Foundation
import XCTest

final class TranscriptFormatterTests: XCTestCase {
    func testFormatsTimestamp() {
        XCTAssertEqual(TranscriptFormatter.timestamp(3.2), "00:00:03")
        XCTAssertEqual(TranscriptFormatter.timestamp(62.9), "00:01:02")
        XCTAssertEqual(TranscriptFormatter.timestamp(3_726.1), "01:02:06")
    }

    func testFormatsMarkdownTranscript() {
        let output = URL(fileURLWithPath: "/tmp/Meeting-20260706-091500.m4a")
        let diagnostics = URL(fileURLWithPath: "/tmp/.diagnostics/Meeting-20260706-091500", isDirectory: true)
        let session = TranscriptionSession(
            outputFile: output,
            recordingName: "Meeting-20260706-091500",
            diagnosticsDirectory: diagnostics,
            systemAudioFile: diagnostics.appending(path: "system.caf"),
            microphoneAudioFile: diagnostics.appending(path: "microphone.caf")
        )
        let result = TranscriptionResult(
            session: session,
            segments: [
                TranscriptionSegment(startTime: 3, speaker: .interviewer, text: "Tell me about yourself."),
                TranscriptionSegment(startTime: 12, speaker: .me, text: "I build macOS tools.")
            ],
            warnings: []
        )

        XCTAssertEqual(
            TranscriptFormatter.markdown(for: result),
            """
            # Meeting Transcript

            Source: Meeting-20260706-091500.m4a

            [00:00:03] Interviewer: Tell me about yourself.
            [00:00:12] Me: I build macOS tools.
            """
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TranscriptFormatterTests`

Expected: FAIL with missing `TranscriptFormatter`.

- [ ] **Step 3: Implement formatter**

Create `Sources/MeetingAudioCapture/Transcription/TranscriptFormatter.swift`:

```swift
import Foundation

struct TranscriptFormatter {
    static func timestamp(_ seconds: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = wholeSeconds / 3_600
        let minutes = (wholeSeconds % 3_600) / 60
        let remainingSeconds = wholeSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    static func speakerLabel(_ speaker: TranscriptionSpeaker) -> String {
        switch speaker {
        case .interviewer:
            return "Interviewer"
        case .me:
            return "Me"
        }
    }

    static func markdown(for result: TranscriptionResult) -> String {
        let lines = result.segments.map {
            "[\(timestamp($0.startTime))] \(speakerLabel($0.speaker)): \($0.text)"
        }
        return """
        # Meeting Transcript

        Source: \(result.session.outputFile.lastPathComponent)

        \(lines.joined(separator: "\n"))
        """
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TranscriptFormatterTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingAudioCapture/Transcription/TranscriptFormatter.swift Tests/MeetingAudioCaptureTests/TranscriptFormatterTests.swift
git commit -m "feat: format transcription markdown"
```

---

### Task 3: Recognition Protocol and Service Merge

**Files:**
- Create: `Sources/MeetingAudioCapture/Transcription/TranscriptionService.swift`
- Test: `Tests/MeetingAudioCaptureTests/TranscriptionServiceTests.swift`

**Interfaces:**
- Consumes: `TranscriptionSession`, `TranscriptionSegment`, `TranscriptionResult`, `TranscriptionError`
- Produces: `protocol SpeechRecognizing: Sendable`
- Produces: `func recognize(url: URL, localeIdentifier: String) async throws -> [RecognizedSpeechSegment]`
- Produces: `struct RecognizedSpeechSegment: Equatable, Sendable`
- Produces: `struct TranscriptionService: Sendable`
- Produces: `func transcribe(session: TranscriptionSession, localeIdentifier: String) async throws -> TranscriptionResult`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MeetingAudioCaptureTests/TranscriptionServiceTests.swift`:

```swift
@testable import MeetingAudioCapture
import Foundation
import XCTest

final class TranscriptionServiceTests: XCTestCase {
    func testTranscribesBothTracksAndMergesByTimestamp() async throws {
        let session = makeSession()
        let recognizer = FakeSpeechRecognizer(results: [
            session.systemAudioFile: [
                RecognizedSpeechSegment(startTime: 4, text: "Question two"),
                RecognizedSpeechSegment(startTime: 1, text: "Question one")
            ],
            session.microphoneAudioFile: [
                RecognizedSpeechSegment(startTime: 2, text: "Answer one")
            ]
        ])
        let service = TranscriptionService(recognizer: recognizer)

        let result = try await service.transcribe(session: session, localeIdentifier: "en-US")

        XCTAssertEqual(
            result.segments,
            [
                TranscriptionSegment(startTime: 1, speaker: .interviewer, text: "Question one"),
                TranscriptionSegment(startTime: 2, speaker: .me, text: "Answer one"),
                TranscriptionSegment(startTime: 4, speaker: .interviewer, text: "Question two")
            ]
        )
        XCTAssertEqual(result.warnings, [])
    }

    func testReturnsSuccessfulTrackWithWarningWhenOneTrackFails() async throws {
        let session = makeSession()
        let recognizer = FakeSpeechRecognizer(
            results: [
                session.microphoneAudioFile: [
                    RecognizedSpeechSegment(startTime: 2, text: "Answer one")
                ]
            ],
            failures: [
                session.systemAudioFile: TranscriptionError.recognitionFailed(.interviewer, "network unavailable")
            ]
        )
        let service = TranscriptionService(recognizer: recognizer)

        let result = try await service.transcribe(session: session, localeIdentifier: "en-US")

        XCTAssertEqual(result.segments, [
            TranscriptionSegment(startTime: 2, speaker: .me, text: "Answer one")
        ])
        XCTAssertEqual(result.warnings, [.recognitionFailed(.interviewer, "network unavailable")])
    }

    func testThrowsWhenBothTracksFail() async {
        let session = makeSession()
        let recognizer = FakeSpeechRecognizer(failures: [
            session.systemAudioFile: TranscriptionError.recognitionFailed(.interviewer, "system failed"),
            session.microphoneAudioFile: TranscriptionError.recognitionFailed(.me, "microphone failed")
        ])
        let service = TranscriptionService(recognizer: recognizer)

        do {
            _ = try await service.transcribe(session: session, localeIdentifier: "en-US")
            XCTFail("Expected transcription to fail")
        } catch {
            XCTAssertEqual(error as? TranscriptionError, .recognitionFailed(.interviewer, "system failed"))
        }
    }

    private func makeSession() -> TranscriptionSession {
        let diagnostics = URL(fileURLWithPath: "/tmp/.diagnostics/Meeting-20260706-091500", isDirectory: true)
        return TranscriptionSession(
            outputFile: URL(fileURLWithPath: "/tmp/Meeting-20260706-091500.m4a"),
            recordingName: "Meeting-20260706-091500",
            diagnosticsDirectory: diagnostics,
            systemAudioFile: diagnostics.appending(path: "system.caf"),
            microphoneAudioFile: diagnostics.appending(path: "microphone.caf")
        )
    }
}

private struct FakeSpeechRecognizer: SpeechRecognizing {
    let results: [URL: [RecognizedSpeechSegment]]
    let failures: [URL: Error]

    init(
        results: [URL: [RecognizedSpeechSegment]] = [:],
        failures: [URL: Error] = [:]
    ) {
        self.results = results
        self.failures = failures
    }

    func recognize(url: URL, localeIdentifier _: String) async throws -> [RecognizedSpeechSegment] {
        if let failure = failures[url] {
            throw failure
        }
        return results[url] ?? []
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TranscriptionServiceTests`

Expected: FAIL with missing `TranscriptionService`, `SpeechRecognizing`, and `RecognizedSpeechSegment`.

- [ ] **Step 3: Implement protocol and merge service**

Create `Sources/MeetingAudioCapture/Transcription/TranscriptionService.swift`:

```swift
import Foundation

struct RecognizedSpeechSegment: Equatable, Sendable {
    let startTime: TimeInterval
    let text: String
}

protocol SpeechRecognizing: Sendable {
    func recognize(url: URL, localeIdentifier: String) async throws -> [RecognizedSpeechSegment]
}

struct TranscriptionService: Sendable {
    private let recognizer: any SpeechRecognizing

    init(recognizer: any SpeechRecognizing = AppleSpeechRecognizer()) {
        self.recognizer = recognizer
    }

    func transcribe(
        session: TranscriptionSession,
        localeIdentifier: String
    ) async throws -> TranscriptionResult {
        async let system = recognize(
            url: session.systemAudioFile,
            speaker: TranscriptionSpeaker.interviewer,
            localeIdentifier: localeIdentifier
        )
        async let microphone = recognize(
            url: session.microphoneAudioFile,
            speaker: TranscriptionSpeaker.me,
            localeIdentifier: localeIdentifier
        )

        let trackResults = await [system, microphone]
        var segments: [TranscriptionSegment] = []
        var warnings: [TranscriptionError] = []

        for trackResult in trackResults {
            switch trackResult {
            case let .success(trackSegments):
                segments.append(contentsOf: trackSegments)
            case let .failure(error):
                warnings.append(error)
            }
        }

        if segments.isEmpty, let firstWarning = warnings.first {
            throw firstWarning
        }

        return TranscriptionResult(
            session: session,
            segments: segments.sorted { $0.startTime < $1.startTime },
            warnings: warnings
        )
    }

    private func recognize(
        url: URL,
        speaker: TranscriptionSpeaker,
        localeIdentifier: String
    ) async -> Result<[TranscriptionSegment], TranscriptionError> {
        do {
            let recognized = try await recognizer.recognize(url: url, localeIdentifier: localeIdentifier)
            return .success(recognized.map {
                TranscriptionSegment(startTime: $0.startTime, speaker: speaker, text: $0.text)
            })
        } catch let error as TranscriptionError {
            return .failure(error)
        } catch {
            return .failure(.recognitionFailed(speaker, error.localizedDescription))
        }
    }
}
```

Add a temporary compiling stub at the bottom of the same file; Task 4 replaces it:

```swift
struct AppleSpeechRecognizer: SpeechRecognizing {
    func recognize(url _: URL, localeIdentifier: String) async throws -> [RecognizedSpeechSegment] {
        throw TranscriptionError.recognizerUnavailable(localeIdentifier)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TranscriptionServiceTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingAudioCapture/Transcription/TranscriptionService.swift Tests/MeetingAudioCaptureTests/TranscriptionServiceTests.swift
git commit -m "feat: merge two-track transcriptions"
```

---

### Task 4: Apple Speech Recognizer and App Permission Text

**Files:**
- Modify: `Sources/MeetingAudioCapture/Transcription/TranscriptionService.swift`
- Modify: `Config/Info.plist`
- Test: `Tests/MeetingAudioCaptureTests/BundleConfigurationTests.swift`

**Interfaces:**
- Consumes: `SpeechRecognizing`, `RecognizedSpeechSegment`, `TranscriptionError`
- Produces: real `AppleSpeechRecognizer` using `SFSpeechRecognizer` and `SFSpeechURLRecognitionRequest`

- [ ] **Step 1: Add failing bundle configuration test**

Modify `Tests/MeetingAudioCaptureTests/BundleConfigurationTests.swift` by adding:

```swift
func testSpeechRecognitionUsageDescriptionIsPresent() throws {
    let data = try Data(contentsOf: projectRoot.appending(path: "Config/Info.plist"))
    let plist = try XCTUnwrap(
        PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
    let value = try XCTUnwrap(plist["NSSpeechRecognitionUsageDescription"] as? String)
    XCTAssertFalse(value.isEmpty)
    XCTAssertTrue(value.contains("transcribe"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BundleConfigurationTests/testSpeechRecognitionUsageDescriptionIsPresent`

Expected: FAIL because `NSSpeechRecognitionUsageDescription` is not present.

- [ ] **Step 3: Add Info.plist key**

Modify `Config/Info.plist` inside `<dict>`:

```xml
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>MeetingAudioCapture uses speech recognition to transcribe local recordings you choose to process.</string>
```

- [ ] **Step 4: Replace the AppleSpeechRecognizer stub**

Modify `Sources/MeetingAudioCapture/Transcription/TranscriptionService.swift` imports:

```swift
import Foundation
import Speech
```

Replace the temporary `AppleSpeechRecognizer` stub with:

```swift
struct AppleSpeechRecognizer: SpeechRecognizing {
    func recognize(url: URL, localeIdentifier: String) async throws -> [RecognizedSpeechSegment] {
        let status = await requestAuthorization()
        guard status == .authorized else {
            throw TranscriptionError.speechNotAuthorized
        }

        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable(localeIdentifier)
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = false
        }

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            recognizer.recognitionTask(with: request) { result, error in
                if let error, !didResume {
                    didResume = true
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal, !didResume else { return }
                didResume = true
                let segments = result.bestTranscription.segments.map {
                    RecognizedSpeechSegment(startTime: $0.timestamp, text: $0.substring)
                }
                continuation.resume(returning: segments)
            }
        }
    }

    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
```

- [ ] **Step 5: Run relevant tests**

Run: `swift test --filter BundleConfigurationTests/testSpeechRecognitionUsageDescriptionIsPresent`

Expected: PASS.

Run: `swift test --filter TranscriptionServiceTests`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Config/Info.plist Sources/MeetingAudioCapture/Transcription/TranscriptionService.swift Tests/MeetingAudioCaptureTests/BundleConfigurationTests.swift
git commit -m "feat: add apple speech recognizer"
```

---

### Task 5: View Model Save, Copy, and State

**Files:**
- Create: `Sources/MeetingAudioCapture/Transcription/TranscriptionViewModel.swift`
- Test: `Tests/MeetingAudioCaptureTests/TranscriptionViewModelTests.swift`

**Interfaces:**
- Consumes: `TranscriptionService`, `TranscriptionSession`, `TranscriptFormatter`
- Produces: `@MainActor final class TranscriptionViewModel: ObservableObject`
- Produces: `enum TranscriptionViewState: Equatable`
- Produces: `func start()`
- Produces: `func saveTranscript()`
- Produces: `var transcriptText: String`

- [ ] **Step 1: Write failing tests**

Create `Tests/MeetingAudioCaptureTests/TranscriptionViewModelTests.swift`:

```swift
@testable import MeetingAudioCapture
import Foundation
import XCTest

@MainActor
final class TranscriptionViewModelTests: XCTestCase {
    func testStartPublishesCompletedResult() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = makeSession(root: root)
        let service = TranscriptionService(recognizer: FakeSpeechRecognizer(results: [
            session.systemAudioFile: [RecognizedSpeechSegment(startTime: 1, text: "Question")],
            session.microphoneAudioFile: [RecognizedSpeechSegment(startTime: 2, text: "Answer")]
        ]))
        let model = TranscriptionViewModel(
            session: session,
            language: .english,
            service: service
        )

        await model.start()

        XCTAssertEqual(model.state, .completed)
        XCTAssertTrue(model.transcriptText.contains("Interviewer: Question"))
        XCTAssertTrue(model.transcriptText.contains("Me: Answer"))
    }

    func testSaveTranscriptWritesMarkdownNextToRecording() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = makeSession(root: root)
        let service = TranscriptionService(recognizer: FakeSpeechRecognizer(results: [
            session.systemAudioFile: [RecognizedSpeechSegment(startTime: 1, text: "Question")]
        ]))
        let model = TranscriptionViewModel(session: session, language: .english, service: service)
        await model.start()

        try model.saveTranscript()

        let output = root.appending(path: "Meeting-20260706-091500-transcript.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(try String(contentsOf: output).contains("Question"))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeSession(root: URL) -> TranscriptionSession {
        let diagnostics = root.appending(path: ".diagnostics/Meeting-20260706-091500", directoryHint: .isDirectory)
        return TranscriptionSession(
            outputFile: root.appending(path: "Meeting-20260706-091500.m4a"),
            recordingName: "Meeting-20260706-091500",
            diagnosticsDirectory: diagnostics,
            systemAudioFile: diagnostics.appending(path: "system.caf"),
            microphoneAudioFile: diagnostics.appending(path: "microphone.caf")
        )
    }
}

private struct FakeSpeechRecognizer: SpeechRecognizing {
    let results: [URL: [RecognizedSpeechSegment]]

    func recognize(url: URL, localeIdentifier _: String) async throws -> [RecognizedSpeechSegment] {
        results[url] ?? []
    }
}
```

If `FakeSpeechRecognizer` conflicts with Task 3's private test helper because the whole test module compiles together, rename this helper to `ViewModelFakeSpeechRecognizer`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TranscriptionViewModelTests`

Expected: FAIL with missing `TranscriptionViewModel` and `TranscriptionViewState`.

- [ ] **Step 3: Implement view model**

Create `Sources/MeetingAudioCapture/Transcription/TranscriptionViewModel.swift`:

```swift
import AppKit
import Foundation

enum TranscriptionViewState: Equatable {
    case idle
    case transcribing
    case completed
    case failed(String)
}

@MainActor
final class TranscriptionViewModel: ObservableObject {
    let session: TranscriptionSession
    @Published private(set) var state: TranscriptionViewState = .idle
    @Published private(set) var result: TranscriptionResult?
    @Published private(set) var warningMessages: [String] = []

    private let language: AppLanguage
    private let service: TranscriptionService

    init(
        session: TranscriptionSession,
        language: AppLanguage,
        service: TranscriptionService = TranscriptionService()
    ) {
        self.session = session
        self.language = language
        self.service = service
    }

    var transcriptText: String {
        guard let result else { return "" }
        return TranscriptFormatter.markdown(for: result)
    }

    func start() async {
        state = .transcribing
        warningMessages = []
        do {
            let nextResult = try await service.transcribe(
                session: session,
                localeIdentifier: localeIdentifier
            )
            result = nextResult
            warningMessages = nextResult.warnings.compactMap(\.errorDescription)
            state = .completed
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptText, forType: .string)
    }

    func saveTranscript() throws {
        let destination = session.outputFile
            .deletingLastPathComponent()
            .appending(path: "\(session.recordingName)-transcript.md")
        do {
            try transcriptText.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            throw TranscriptionError.saveFailed(error.localizedDescription)
        }
    }

    private var localeIdentifier: String {
        switch language {
        case .english:
            return "en-US"
        case .simplifiedChinese:
            return "zh-CN"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TranscriptionViewModelTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingAudioCapture/Transcription/TranscriptionViewModel.swift Tests/MeetingAudioCaptureTests/TranscriptionViewModelTests.swift
git commit -m "feat: manage transcription state"
```

---

### Task 6: Localized UI Strings

**Files:**
- Modify: `Sources/MeetingAudioCapture/Localization/AppLocalization.swift`
- Test: `Tests/MeetingAudioCaptureTests/AppLocalizationTests.swift`

**Interfaces:**
- Consumes: `AppTextKey`, `AppLocalizer`
- Produces new text keys used by Task 7 UI.

- [ ] **Step 1: Add representative failing test assertions**

Modify `Tests/MeetingAudioCaptureTests/AppLocalizationTests.swift` in `testRepresentativeEnglishAndChineseTranslations()`:

```swift
XCTAssertEqual(AppLocalizer.text(.transcribe, language: .english), "Transcribe")
XCTAssertEqual(AppLocalizer.text(.transcribe, language: .simplifiedChinese), "转写")
XCTAssertEqual(AppLocalizer.text(.interviewer, language: .english), "Interviewer")
XCTAssertEqual(AppLocalizer.text(.interviewer, language: .simplifiedChinese), "面试官")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppLocalizationTests`

Expected: FAIL because `.transcribe` and `.interviewer` do not exist.

- [ ] **Step 3: Add localization keys and strings**

Modify `AppTextKey`:

```swift
case transcribe
case transcription
case startTranscription
case retryTranscription
case copyTranscript
case saveTranscript
case transcriptionReady
case transcribing
case interviewer
case me
case transcriptionWarnings
case noTranscript
```

Add English translations:

```swift
.transcribe: "Transcribe",
.transcription: "Transcription",
.startTranscription: "Start Transcription",
.retryTranscription: "Retry",
.copyTranscript: "Copy",
.saveTranscript: "Save",
.transcriptionReady: "Ready to transcribe",
.transcribing: "Transcribing…",
.interviewer: "Interviewer",
.me: "Me",
.transcriptionWarnings: "Warnings",
.noTranscript: "No transcript yet",
```

Add Simplified Chinese translations:

```swift
.transcribe: "转写",
.transcription: "转写",
.startTranscription: "开始转写",
.retryTranscription: "重试",
.copyTranscript: "复制",
.saveTranscript: "保存",
.transcriptionReady: "准备转写",
.transcribing: "正在转写…",
.interviewer: "面试官",
.me: "我",
.transcriptionWarnings: "警告",
.noTranscript: "暂无转写内容",
```

- [ ] **Step 4: Run localization tests**

Run: `swift test --filter AppLocalizationTests`

Expected: PASS, including `testEveryKeyHasEnglishAndChineseText`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingAudioCapture/Localization/AppLocalization.swift Tests/MeetingAudioCaptureTests/AppLocalizationTests.swift
git commit -m "feat: localize transcription UI"
```

---

### Task 7: Standalone Transcription Window and Menu Entry

**Files:**
- Create: `Sources/MeetingAudioCapture/Views/TranscriptionView.swift`
- Create: `Sources/MeetingAudioCapture/Transcription/TranscriptionWindowController.swift`
- Modify: `Sources/MeetingAudioCapture/AppModel.swift`
- Modify: `Sources/MeetingAudioCapture/Views/RecorderMenuView.swift`

**Interfaces:**
- Consumes: `TranscriptionSession.resolve(outputFile:)`
- Consumes: `TranscriptionViewModel`
- Produces: `final class TranscriptionWindowController`
- Produces: `func show(session: TranscriptionSession, language: AppLanguage)`
- Produces: `AppModel.openTranscriptionForLastRecording()`
- Produces: `AppModel.canOpenTranscription`

- [ ] **Step 1: Implement window controller**

Create `Sources/MeetingAudioCapture/Transcription/TranscriptionWindowController.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class TranscriptionWindowController {
    private var window: NSWindow?

    func show(session: TranscriptionSession, language: AppLanguage) {
        let viewModel = TranscriptionViewModel(session: session, language: language)
        let view = TranscriptionView(model: viewModel)
        let hostingController = NSHostingController(rootView: view)

        if let window {
            window.contentViewController = hostingController
            window.title = "Transcription"
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Transcription"
        window.setContentSize(NSSize(width: 760, height: 560))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
```

- [ ] **Step 2: Implement SwiftUI view**

Create `Sources/MeetingAudioCapture/Views/TranscriptionView.swift`:

```swift
import SwiftUI

struct TranscriptionView: View {
    @ObservedObject var model: TranscriptionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Divider()
            controls
        }
        .padding(18)
        .frame(minWidth: 640, minHeight: 460)
        .task {
            if model.state == .idle {
                await model.start()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.session.recordingName)
                .font(.title3)
            Text(statusText)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            Text("Ready to transcribe")
                .foregroundStyle(.secondary)
        case .transcribing:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing…")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        case .completed:
            if !model.warningMessages.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Warnings")
                        .font(.headline)
                    ForEach(model.warningMessages, id: \.self) { warning in
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            ScrollView {
                Text(model.transcriptText.isEmpty ? "No transcript yet" : model.transcriptText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .failed(message):
            Text(message)
                .foregroundStyle(.red)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private var controls: some View {
        HStack {
            Button(retryTitle) {
                Task { await model.start() }
            }
            .disabled(model.state == .transcribing)

            Spacer()

            Button("Copy") {
                model.copyTranscript()
            }
            .disabled(model.transcriptText.isEmpty)

            Button("Save") {
                try? model.saveTranscript()
            }
            .disabled(model.transcriptText.isEmpty)
        }
    }

    private var statusText: String {
        switch model.state {
        case .idle:
            return "Ready to transcribe"
        case .transcribing:
            return "Transcribing…"
        case .completed:
            return "Transcription"
        case .failed:
            return "Failed"
        }
    }

    private var retryTitle: String {
        switch model.state {
        case .idle:
            return "Start Transcription"
        default:
            return "Retry"
        }
    }
}
```

This step intentionally uses hard-coded English strings for first compile. Task 8 replaces them with localized strings from `AppLocalizer`.

- [ ] **Step 3: Wire AppModel**

Modify `Sources/MeetingAudioCapture/AppModel.swift`:

Add property:

```swift
private let transcriptionWindowController = TranscriptionWindowController()
```

Add computed property:

```swift
var canOpenTranscription: Bool {
    guard let outputFile = snapshot.outputFile else { return false }
    return (try? TranscriptionSession.resolve(outputFile: outputFile)) != nil
}
```

Add method:

```swift
func openTranscriptionForLastRecording() {
    guard let outputFile = snapshot.outputFile else { return }
    do {
        let session = try TranscriptionSession.resolve(outputFile: outputFile)
        transcriptionWindowController.show(session: session, language: language)
    } catch {
        displayError = .system(error.localizedDescription)
    }
}
```

- [ ] **Step 4: Add menu button**

Modify `Sources/MeetingAudioCapture/Views/RecorderMenuView.swift` in the `HStack` containing `openFolder`:

```swift
if model.canOpenTranscription {
    Button(model.text(.transcribe)) { model.openTranscriptionForLastRecording() }
}
if model.snapshot.outputFile != nil {
    Button(model.text(.openFolder)) { model.revealOutputFile() }
}
```

- [ ] **Step 5: Build**

Run: `swift build`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/MeetingAudioCapture/Views/TranscriptionView.swift Sources/MeetingAudioCapture/Transcription/TranscriptionWindowController.swift Sources/MeetingAudioCapture/AppModel.swift Sources/MeetingAudioCapture/Views/RecorderMenuView.swift
git commit -m "feat: open transcription window"
```

---

### Task 8: Localize Transcription View and Speaker Labels

**Files:**
- Modify: `Sources/MeetingAudioCapture/Transcription/TranscriptFormatter.swift`
- Modify: `Sources/MeetingAudioCapture/Transcription/TranscriptionViewModel.swift`
- Modify: `Sources/MeetingAudioCapture/Views/TranscriptionView.swift`
- Test: `Tests/MeetingAudioCaptureTests/TranscriptFormatterTests.swift`

**Interfaces:**
- Consumes: `AppLocalizer`, `AppTextKey`, `AppLanguage`
- Produces: `TranscriptFormatter.markdown(for:language:)`

- [ ] **Step 1: Add failing localized formatter test**

Modify `Tests/MeetingAudioCaptureTests/TranscriptFormatterTests.swift` by adding:

```swift
func testFormatsChineseSpeakerLabels() {
    let output = URL(fileURLWithPath: "/tmp/Meeting-20260706-091500.m4a")
    let diagnostics = URL(fileURLWithPath: "/tmp/.diagnostics/Meeting-20260706-091500", isDirectory: true)
    let session = TranscriptionSession(
        outputFile: output,
        recordingName: "Meeting-20260706-091500",
        diagnosticsDirectory: diagnostics,
        systemAudioFile: diagnostics.appending(path: "system.caf"),
        microphoneAudioFile: diagnostics.appending(path: "microphone.caf")
    )
    let result = TranscriptionResult(
        session: session,
        segments: [
            TranscriptionSegment(startTime: 3, speaker: .interviewer, text: "你好"),
            TranscriptionSegment(startTime: 12, speaker: .me, text: "你好")
        ],
        warnings: []
    )

    let markdown = TranscriptFormatter.markdown(for: result, language: .simplifiedChinese)

    XCTAssertTrue(markdown.contains("面试官: 你好"))
    XCTAssertTrue(markdown.contains("我: 你好"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TranscriptFormatterTests/testFormatsChineseSpeakerLabels`

Expected: FAIL because `markdown(for:language:)` does not exist.

- [ ] **Step 3: Update formatter**

Modify `TranscriptFormatter`:

```swift
static func speakerLabel(_ speaker: TranscriptionSpeaker, language: AppLanguage = .english) -> String {
    switch speaker {
    case .interviewer:
        return AppLocalizer.text(.interviewer, language: language)
    case .me:
        return AppLocalizer.text(.me, language: language)
    }
}

static func markdown(for result: TranscriptionResult, language: AppLanguage = .english) -> String {
    let lines = result.segments.map {
        "[\(timestamp($0.startTime))] \(speakerLabel($0.speaker, language: language)): \($0.text)"
    }
    return """
    # Meeting Transcript

    Source: \(result.session.outputFile.lastPathComponent)

    \(lines.joined(separator: "\n"))
    """
}
```

- [ ] **Step 4: Update view model**

Modify `TranscriptionViewModel.transcriptText`:

```swift
var transcriptText: String {
    guard let result else { return "" }
    return TranscriptFormatter.markdown(for: result, language: language)
}
```

Add helper:

```swift
func text(_ key: AppTextKey) -> String {
    AppLocalizer.text(key, language: language)
}
```

- [ ] **Step 5: Replace hard-coded UI strings**

In `TranscriptionView`, replace:

- `"Ready to transcribe"` with `model.text(.transcriptionReady)`
- `"Transcribing…"` with `model.text(.transcribing)`
- `"Warnings"` with `model.text(.transcriptionWarnings)`
- `"No transcript yet"` with `model.text(.noTranscript)`
- `"Copy"` with `model.text(.copyTranscript)`
- `"Save"` with `model.text(.saveTranscript)`
- `"Start Transcription"` with `model.text(.startTranscription)`
- `"Retry"` with `model.text(.retryTranscription)`
- `"Transcription"` with `model.text(.transcription)`
- `"Failed"` with `model.text(.failed)`

- [ ] **Step 6: Run tests and build**

Run: `swift test --filter TranscriptFormatterTests`

Expected: PASS.

Run: `swift build`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/MeetingAudioCapture/Transcription/TranscriptFormatter.swift Sources/MeetingAudioCapture/Transcription/TranscriptionViewModel.swift Sources/MeetingAudioCapture/Views/TranscriptionView.swift Tests/MeetingAudioCaptureTests/TranscriptFormatterTests.swift
git commit -m "feat: localize transcript output"
```

---

### Task 9: Final Verification

**Files:**
- No new files.
- Verify the full feature branch.

**Interfaces:**
- Consumes all previous tasks.
- Produces verified branch ready for user review.

- [ ] **Step 1: Run full test suite**

Run: `swift test`

Expected: PASS.

- [ ] **Step 2: Build the app**

Run: `swift build`

Expected: PASS.

- [ ] **Step 3: Confirm git status only contains expected changes**

Run: `git status --short --branch`

Expected:

```text
## feature/audio-transcription
 M Scripts/create-dmg.sh
```

The `Scripts/create-dmg.sh` change predates this feature and must remain uncommitted.

- [ ] **Step 4: Manual smoke test**

Run the app from Xcode or SwiftPM, record a short sample, stop recording, click Transcribe, grant speech permission if prompted, and verify:

- A standalone transcription window opens.
- It labels system audio as Interviewer.
- It labels microphone audio as Me.
- Copy places Markdown text on the pasteboard.
- Save writes `<recording-name>-transcript.md` next to the `.m4a`.

- [ ] **Step 5: Commit any final fixes**

If Step 1 or Step 2 required fixes:

```bash
git add Sources Tests Config
git commit -m "fix: stabilize audio transcription"
```

If no fixes were needed, do not create an empty commit.

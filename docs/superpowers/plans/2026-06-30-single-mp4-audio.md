# Single MP4 Audio Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce one timestamped MP4 per recording with a default mixed AAC track plus separately identifiable system and microphone AAC tracks, while moving source files to system temporary storage and making the menu bar recording indicator less intrusive.

**Architecture:** `RecordingFiles` will model a private temporary session and a collision-safe public destination. `RecordingExporter` will create three temporary AAC assets, losslessly multiplex them into an MP4 with an `AVAssetWriterInputGroup` whose default input is `Mixed`, validate the result, move it to the destination, and delete temporary data. `RecordingCoordinator` will expose only the final output file, while a focused presentation type will drive the monochrome menu bar indicator.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation (`AVAssetExportSession`, `AVAssetReader`, `AVAssetWriter`, `AVAssetWriterInputGroup`), XCTest, macOS 15+

## Global Constraints

- Keep the deployment floor at macOS 15.0 and add no third-party dependencies.
- Emit exactly one user-visible file named `Meeting-YYYYMMDD-HHmmss.mp4`, adding `-2`, `-3`, and so on on collision.
- The MP4 contains AAC tracks titled `Mixed`, `System Audio`, and `Microphone`; only `Mixed` is enabled by default.
- Preserve the existing 48 kHz pause/resume timeline and boundary-click fix.
- Do not create `metadata.json` or user-visible M4A files.
- Use `FileManager.default.temporaryDirectory`; never hard-code `/tmp`.
- Do not add in-app track extraction, video, cloud behavior, codecs, or filename settings.
- Normal recording states use no red color and no animation.

---

### Task 1: Private Session Paths and Cleanup

**Files:**
- Modify: `Sources/MeetingAudioCapture/Recording/RecordingFiles.swift`
- Modify: `Tests/MeetingAudioCaptureTests/RecordingFilesTests.swift`

**Interfaces:**
- Produces: `RecordingFiles.create(in:temporaryRoot:now:timeZone:id:fileManager:) throws -> RecordingFiles`
- Produces: `RecordingFiles.nextOutputURL(fileManager:) -> URL`
- Produces: `RecordingFiles.removeTemporarySession(fileManager:) throws`
- Produces: `RecordingFiles.removeStaleSessions(temporaryRoot:fileManager:) throws`
- Fields: `sessionDirectory`, `systemTemporaryCAF`, `microphoneTemporaryCAF`, `systemTemporaryM4A`, `microphoneTemporaryM4A`, `mixedTemporaryM4A`, `temporaryMP4`, `outputDirectory`, `filenameStem`

- [ ] **Step 1: Replace the layout tests with failing private-session tests**

Create fixtures with separate `outputRoot` and `temporaryRoot`, then assert:

```swift
let files = try RecordingFiles.create(
    in: outputRoot,
    temporaryRoot: temporaryRoot,
    now: now,
    timeZone: TimeZone(secondsFromGMT: 8 * 3600)!,
    id: "ABCD"
)
XCTAssertEqual(files.sessionDirectory, temporaryRoot.appending(path: "MeetingAudioCapture/ABCD"))
XCTAssertEqual(files.filenameStem, "Meeting-20260630-120102")
XCTAssertTrue(FileManager.default.fileExists(atPath: files.sessionDirectory.path))
XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outputRoot.path), [])
```

Add collision assertions for `Meeting-...mp4`, `Meeting-...-2.mp4`, and a cleanup test proving only children of the app-owned temporary container are removed.

- [ ] **Step 2: Run the focused tests and verify failure**

Run: `swift test --filter RecordingFilesTests`

Expected: compilation failures because the new fields and parameters do not exist.

- [ ] **Step 3: Implement the private session model**

Replace public M4A/metadata fields with private intermediates. Build the timestamp using `en_US_POSIX`, Gregorian calendar, and the injected time zone. Create only:

```swift
temporaryRoot/
  MeetingAudioCapture/
    <id>/
      system.caf
      microphone.caf
      system.m4a
      microphone.m4a
      mixed.m4a
      output.mp4
```

Implement collision selection without creating a placeholder:

```swift
func nextOutputURL(fileManager: FileManager = .default) -> URL {
    var suffix = 1
    while true {
        let name = suffix == 1 ? filenameStem : "\(filenameStem)-\(suffix)"
        let candidate = outputDirectory.appending(path: "\(name).mp4")
        if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        suffix += 1
    }
}
```

`removeStaleSessions` must enumerate and delete only the `MeetingAudioCapture` container's direct children, then remove the empty container.

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter RecordingFilesTests`

Expected: all `RecordingFilesTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingAudioCapture/Recording/RecordingFiles.swift Tests/MeetingAudioCaptureTests/RecordingFilesTests.swift
git commit -m "refactor: move recording sessions to temporary storage"
```

### Task 2: Three-Track MP4 Exporter

**Files:**
- Modify: `Sources/MeetingAudioCapture/Recording/RecordingExporter.swift`
- Modify: `Tests/MeetingAudioCaptureTests/RecordingExporterTests.swift`

**Interfaces:**
- Produces: `protocol RecordingExporting: Sendable { func export(files: RecordingFiles) async throws -> URL }`
- Produces: `struct RecordingExporter: RecordingExporting`
- Consumes: all temporary URLs and `nextOutputURL(fileManager:)` from Task 1

- [ ] **Step 1: Write the failing exporter contract test**

Write one-second 48 kHz fixtures (`0.1` stereo system, `0.2` mono microphone), call `try await RecordingExporter().export(files:)`, and assert:

```swift
XCTAssertEqual(outputURL.pathExtension, "mp4")
XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
XCTAssertFalse(FileManager.default.fileExists(atPath: files.sessionDirectory.path))
let asset = AVURLAsset(url: outputURL)
let tracks = try await asset.loadTracks(withMediaType: .audio)
XCTAssertEqual(tracks.count, 3)
XCTAssertEqual(tracks.filter(\.isEnabled).count, 1)
```

Load each track's `.commonMetadata`, resolve `.commonIdentifierTitle`, and assert the set is exactly `Mixed`, `System Audio`, and `Microphone`, with `Mixed` enabled. Assert all durations are within 0.05 seconds of one second.

Add a failure test with a missing microphone CAF and assert export throws, no output MP4 exists, and the session directory remains available.

- [ ] **Step 2: Run the focused tests and verify failure**

Run: `swift test --filter RecordingExporterTests`

Expected: compilation failure because `export` does not throw or return a URL.

- [ ] **Step 3: Export three temporary AAC assets**

Keep the existing `AVAssetExportPresetAppleM4A` track exports and mixed composition, but write them only to the session URLs. Throw a typed `RecordingExportError` instead of returning Boolean flags. The mixed composition keeps system volume at `1`, microphone volume at `1`, and exports one stereo AAC track.

- [ ] **Step 4: Multiplex AAC tracks into MP4 without another encode**

For each temporary M4A, create an `AVAssetReaderTrackOutput` with `outputSettings: nil` and an `AVAssetWriterInput` with `outputSettings: nil`, using the source track's first format description as `sourceFormatHint`. Apply title metadata:

```swift
let titleItem = AVMutableMetadataItem()
titleItem.identifier = .commonIdentifierTitle
titleItem.value = title as NSString
writerInput.metadata = [titleItem]
```

Add inputs in this order: mixed, system, microphone. Add an input group so players treat the tracks as alternatives and choose the mixed track:

```swift
let group = AVAssetWriterInputGroup(
    inputs: [mixed.input, system.input, microphone.input],
    defaultInput: mixed.input
)
guard writer.canAdd(group) else { throw RecordingExportError.unsupportedInputGroup }
writer.add(group)
```

Start the writer session at `.zero`, start all readers, and pump each reader on its own serial queue with `requestMediaDataWhenReady`. Mark each input finished at end-of-stream; fail if a reader or append fails. Call `finishWriting()` only after all three pumps finish.

- [ ] **Step 5: Validate, move, and clean up**

Load `output.mp4`, require exactly three audio tracks, exactly one enabled track, and the three expected titles. Choose `files.nextOutputURL()` immediately before moving, move the validated MP4 there, then remove the entire temporary session. If validation or move fails, throw and retain the session.

- [ ] **Step 6: Run focused tests**

Run: `swift test --filter RecordingExporterTests`

Expected: all `RecordingExporterTests` pass with one final MP4 and no successful-session temporary files.

- [ ] **Step 7: Commit**

```bash
git add Sources/MeetingAudioCapture/Recording/RecordingExporter.swift Tests/MeetingAudioCaptureTests/RecordingExporterTests.swift
git commit -m "feat: export recordings as three-track MP4"
```

### Task 3: Coordinator and Output Lifecycle

**Files:**
- Modify: `Sources/MeetingAudioCapture/Recording/RecordingCoordinator.swift`
- Modify: `Sources/MeetingAudioCapture/AppModel.swift`
- Modify: `Sources/MeetingAudioCapture/Views/RecorderMenuView.swift`
- Modify: `Tests/MeetingAudioCaptureTests/RecordingCoordinatorTests.swift`

**Interfaces:**
- Consumes: `any RecordingExporting` and `RecordingFiles.create(...)`
- Changes: `RecordingSnapshot.outputDirectory` to `RecordingSnapshot.outputFile`
- Produces: completed/failed snapshots containing the final MP4 URL only when export succeeds

- [ ] **Step 1: Write failing lifecycle tests**

Update the start test to assert `snapshot.outputFile == nil` while preparing. Add a fake `RecordingExporting` that records its input and returns a chosen MP4 URL. Add assertions that successful finalization publishes `.completed` with that URL and export failure publishes `.failed` with `One or more audio exports failed.`.

- [ ] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter RecordingCoordinatorTests`

Expected: compilation failures for `RecordingExporting` and `outputFile`.

- [ ] **Step 3: Remove metadata and integrate throwing export**

Delete `startedAt`, `microphoneName`, `RecordingMetadata`, and the private JSON encoder. Create the session with the selected destination as `outputDirectory`. During finalize:

```swift
do {
    outputFile = try await exporter.export(files: files)
    if error == nil {
        try stateMachine.transition(to: .completed)
        publish(state: .completed)
    }
} catch {
    try? stateMachine.transition(to: .failed(.init(message: "One or more audio exports failed.")))
    publish(state: stateMachine.state)
}
```

Keep a capture-originated failure state even if salvage export succeeds. Reset `outputFile` at each start. Publish no session directory to UI.

- [ ] **Step 4: Reveal the final file and clean stale sessions at launch**

Call `try? RecordingFiles.removeStaleSessions()` once during `AppModel` initialization before a session starts. Replace folder opening with:

```swift
func revealOutputFile() {
    guard let url = snapshot.outputFile else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
}
```

Keep localized button copy unless a focused wording change is required; its action must reveal the MP4.

- [ ] **Step 5: Run coordinator and localization tests**

Run: `swift test --filter RecordingCoordinatorTests`

Run: `swift test --filter AppLocalizationTests`

Expected: both suites pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/MeetingAudioCapture/Recording/RecordingCoordinator.swift Sources/MeetingAudioCapture/AppModel.swift Sources/MeetingAudioCapture/Views/RecorderMenuView.swift Tests/MeetingAudioCaptureTests/RecordingCoordinatorTests.swift
git commit -m "refactor: expose only finalized recording output"
```

### Task 4: Low-Intrusion Menu Bar Indicator

**Files:**
- Modify: `Sources/MeetingAudioCapture/Recording/RecordingPresentation.swift`
- Modify: `Sources/MeetingAudioCapture/AppModel.swift`
- Modify: `Sources/MeetingAudioCapture/MeetingAudioCaptureApp.swift`
- Modify: `Tests/MeetingAudioCaptureTests/RecordingPresentationTests.swift`

**Interfaces:**
- Produces: `MenuBarIndicator` with `symbolName` and `badge`
- Produces: `MenuBarIndicator.Badge` cases `none`, `dot`, `pause`, `warning`
- Produces: `RecordingPresentation.menuBarIndicator(_:)`

- [ ] **Step 1: Write failing state-mapping tests**

Assert idle/completed map to waveform with no badge; preparing/recording/stopping map to waveform with `.dot`; paused maps to waveform with `.pause`; failed maps to `exclamationmark.triangle` with `.warning`.

- [ ] **Step 2: Run the focused tests and verify failure**

Run: `swift test --filter RecordingPresentationTests`

Expected: compilation failure because `menuBarIndicator` does not exist.

- [ ] **Step 3: Implement presentation mapping and SwiftUI rendering**

Remove `AppModel.menuBarIcon` and active red styling. Render the base system image with a small top-trailing overlay:

```swift
ZStack(alignment: .topTrailing) {
    Image(systemName: indicator.symbolName)
    switch indicator.badge {
    case .dot:
        Circle().fill(.secondary).frame(width: 4, height: 4).offset(x: 2, y: -1)
    case .pause:
        Image(systemName: "pause.fill").font(.system(size: 5, weight: .bold)).foregroundStyle(.secondary)
            .offset(x: 4, y: -1)
    case .none, .warning:
        EmptyView()
    }
}
```

Use the system primary/secondary appearance only. Add no animation, timer, pulse, or red foreground style. Keep the explicit state label and elapsed time inside the open menu.

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter RecordingPresentationTests`

Expected: all presentation tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingAudioCapture/Recording/RecordingPresentation.swift Sources/MeetingAudioCapture/AppModel.swift Sources/MeetingAudioCapture/MeetingAudioCaptureApp.swift Tests/MeetingAudioCaptureTests/RecordingPresentationTests.swift
git commit -m "feat: soften menu bar recording indicator"
```

### Task 5: Documentation and End-to-End Verification

**Files:**
- Modify: `README.md`
- Modify: `README.en.md`
- Modify: `CONTRIBUTING.md` if its output contract references separate files

**Interfaces:**
- Documents the single MP4 format and three internal track names.

- [ ] **Step 1: Update user-facing documentation**

Replace the recording-directory tree with `Meeting-YYYYMMDD-HHmmss.mp4`. Explain that normal players use `Mixed`, while advanced tools can inspect `System Audio` and `Microphone`. State that temporary sources are deleted after successful export and that this version has no in-app split command.

- [ ] **Step 2: Run repository consistency searches**

Run: `rg -n "system\.m4a|microphone\.m4a|mixed\.m4a|metadata\.json|Recording-YYYY" README.md README.en.md CONTRIBUTING.md Sources Tests`

Expected: no obsolete public-output references; temporary filenames may appear only in implementation-specific code and tests.

- [ ] **Step 3: Run complete verification**

Run: `make clean && make test && make app`

Expected: all tests pass and `.build/MeetingAudioCapture.app` is created.

Run: `codesign --verify --deep --strict .build/MeetingAudioCapture.app`

Expected: exit status 0.

- [ ] **Step 4: Inspect a generated MP4 fixture**

Run the exporter integration test while preserving or printing its output fixture, then inspect it with AVFoundation or installed `ffprobe`: require container `mp4`, three AAC audio tracks, titles `Mixed`, `System Audio`, `Microphone`, and only `Mixed` enabled by default. Open the fixture in QuickTime Player and confirm both fixture signals are audible through the default mixed track.

- [ ] **Step 5: Commit documentation**

```bash
git add README.md README.en.md CONTRIBUTING.md
git commit -m "docs: describe single MP4 recording output"
```

- [ ] **Step 6: Review final history and publish**

Run: `git status --short --branch && git log --oneline -8`

Expected: clean worktree and intentional task-sized commits. Push `main` to `origin` only after all verification succeeds.

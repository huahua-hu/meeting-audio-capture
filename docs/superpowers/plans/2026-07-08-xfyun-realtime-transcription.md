# XFYun Real-Time Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stream system and microphone audio independently to XFYun during recording, persist finalized text continuously, and export an immediately available transcript.

**Architecture:** Keep recording authoritative and tee decoded PCM into a non-blocking live transcription pipeline. Store credentials only in Keychain, isolate signing/WebSocket parsing, and append finalized phrases to a recoverable JSONL journal rendered beside the final M4A.

**Tech Stack:** Swift 6, Security, CryptoKit, AVFAudio, Foundation WebSocket, SwiftUI, XCTest.

## Global Constraints

- Never store or log credential values outside macOS Keychain.
- Never block or fail local audio recording because of network behavior.
- Use one serial WebSocket per speaker track.
- Persist finalized phrases before displaying them as durable results.
- Keep changes local; do not push the branch.
- Preserve the unrelated `Scripts/create-dmg.sh` worktree change.

### Task 1: Credential Security

**Files:**
- Create: `Sources/MeetingAudioCapture/Realtime/XFYunCredentialStore.swift`
- Create: `Tests/MeetingAudioCaptureTests/XFYunCredentialStoreTests.swift`
- Modify: `Tests/MeetingAudioCaptureTests/BundleConfigurationTests.swift`

- [ ] Write Keychain CRUD tests using a unique test service.
- [ ] Implement generic-password add/update/read/delete with Security status errors.
- [ ] Add a repository scan test rejecting embedded XFYun credential defaults and the exposed values.
- [ ] Run focused tests and commit.

### Task 2: Authentication and Protocol Parsing

**Files:**
- Create: `Sources/MeetingAudioCapture/Realtime/XFYunAuthSigner.swift`
- Create: `Sources/MeetingAudioCapture/Realtime/XFYunProtocol.swift`
- Create: `Tests/MeetingAudioCaptureTests/XFYunAuthSignerTests.swift`
- Create: `Tests/MeetingAudioCaptureTests/XFYunProtocolTests.swift`

- [ ] Write fixed-timestamp signing tests and started/result/error parsing fixtures.
- [ ] Implement MD5 plus HMAC-SHA1 signing with CryptoKit and percent-safe query construction.
- [ ] Implement typed envelope and nested result decoding.
- [ ] Run focused tests and commit.

### Task 3: Real-Time PCM and Transcript Journal

**Files:**
- Create: `Sources/MeetingAudioCapture/Realtime/RealtimePCMEncoder.swift`
- Create: `Sources/MeetingAudioCapture/Realtime/TranscriptJournal.swift`
- Create: `Tests/MeetingAudioCaptureTests/RealtimePCMEncoderTests.swift`
- Create: `Tests/MeetingAudioCaptureTests/TranscriptJournalTests.swift`
- Modify: `Sources/MeetingAudioCapture/Recording/RecordingFiles.swift`

- [ ] Test stereo averaging, 48 kHz to 16 kHz conversion, Int16 output, journal append/recovery/order/render.
- [ ] Implement bounded PCM conversion and JSONL fsync per finalized phrase.
- [ ] Add journal paths to recording files and diagnostic preservation.
- [ ] Run focused tests and commit.

### Task 4: WebSocket and Dual-Track Coordinator

**Files:**
- Create: `Sources/MeetingAudioCapture/Realtime/XFYunRealtimeClient.swift`
- Create: `Sources/MeetingAudioCapture/Realtime/LiveTranscriptionCoordinator.swift`
- Create: `Tests/MeetingAudioCaptureTests/XFYunRealtimeClientTests.swift`
- Create: `Tests/MeetingAudioCaptureTests/LiveTranscriptionCoordinatorTests.swift`

- [ ] Define injectable WebSocket transport and fake transport tests.
- [ ] Test start/audio/end messages, final event persistence, one-track failure isolation, and bounded queue drops.
- [ ] Implement URLSession transport and two-track actor coordinator.
- [ ] Run focused tests and commit.

### Task 5: Recording, UI, and Export Integration

**Files:**
- Modify: `Sources/MeetingAudioCapture/Recording/RecordingCoordinator.swift`
- Modify: `Sources/MeetingAudioCapture/Recording/RecordingExporter.swift`
- Modify: `Sources/MeetingAudioCapture/AppModel.swift`
- Modify: `Sources/MeetingAudioCapture/Views/RecorderMenuView.swift`
- Create: `Sources/MeetingAudioCapture/Views/XFYunSettingsView.swift`
- Create: `Sources/MeetingAudioCapture/Realtime/XFYunSettingsWindowController.swift`
- Modify: `Sources/MeetingAudioCapture/Localization/AppLocalization.swift`
- Modify corresponding tests.

- [ ] Test recording remains successful when live transcription fails or queues are slow.
- [ ] Tee decoded PCM into the coordinator and finalize it before export cleanup.
- [ ] Render journal Markdown next to final output.
- [ ] Add Keychain settings window, configured status, and real-time toggle.
- [ ] Add localized connection/failure/status strings.
- [ ] Run focused tests and commit.

### Task 6: Verification and Deployment

- [ ] Run complete test suite and credential scans.
- [ ] Build and sign the release app.
- [ ] Replace `/Applications/MeetingAudioCapture.app` and launch it.
- [ ] Verify signature, installed binary, idle responsiveness, and branch status.
- [ ] Report that real-service validation remains pending until rotated credentials are entered locally.

# XFYun Real-Time Transcription Design

## Goal

Transcribe system audio and microphone audio independently while an interview is being recorded, persist finalized text continuously, and make the transcript immediately available when recording stops.

## Scope

- Personal-use feature on the local `feature/audio-transcription` branch.
- No remote push.
- Chinese real-time speech-to-text, not language translation.
- System audio is labeled `Interviewer`; microphone audio is labeled `Me`.
- Existing local recording and offline Apple Speech fallback remain available.

## Credential Security

- The exposed credential pair must be revoked before testing.
- The application never contains credential values in source, plist, defaults, logs, tests, fixtures, or documentation.
- `APPID` and `APP_KEY` are entered in a dedicated settings window and stored as separate macOS Keychain generic-password items.
- The UI shows only configured/not configured state. It never reads a key back into a visible text field.
- Users can replace or delete credentials.
- A repository test scans tracked text files for credential-like defaults and known secret patterns.
- No credentials are sent anywhere except the official XFYun WebSocket authentication request.

## User Experience

- Add `XFYun Settings` to the menu panel.
- Add a `Real-Time Transcription` toggle, enabled only when credentials are configured.
- Starting a recording with the toggle enabled opens the existing transcription window in live mode.
- Finalized interviewer and user paragraphs appear while recording.
- The window shows connection state per track and a non-blocking warning if one track disconnects.
- Stopping the recording finalizes both sessions, opens the completed transcript, and enables immediate copy/save.
- The transcript is automatically saved next to the final M4A as `<recording-name>-transcript.md`; the Save command remains available for another explicit write.

## Audio Pipeline

The existing capture and recording path remains authoritative. For each decoded PCM buffer in `RecordingCoordinator`:

1. Append the 48 kHz buffer to the existing local CAF writer.
2. Convert a copy to mono 16 kHz signed 16-bit little-endian PCM.
3. For system audio, average the two channels before resampling.
4. Enqueue the encoded bytes into the Interviewer stream.
5. Enqueue microphone bytes into the Me stream.

Audio capture never awaits network I/O. Each track has a bounded serial queue. If the queue is full, the session records a dropped interval instead of blocking recording.

## XFYun Transport

- Use `URLSessionWebSocketTask`; add no third-party networking dependency.
- Open one authenticated WebSocket per speaker track.
- Build authentication from Keychain values only at connection time.
- Send PCM in bounded frames at the service cadence.
- Parse started, partial, final, and error messages into typed models.
- Only finalized phrases are persisted. Partial text is display-only.
- Send the protocol end marker and wait for final responses during stop with a bounded timeout.

## Persistence

- Create a private transcript journal in the recording session directory.
- Append one JSON Lines record per finalized phrase: speaker, start time, end time, text, and source sequence.
- Flush each appended final record to disk.
- Rebuild live UI state from the journal so window recreation does not lose text.
- During recording export, render the journal to Markdown next to the final M4A.
- Preserve the journal in diagnostics when export or finalization fails.

## Failure Handling

- Missing credentials: recording continues; real-time transcription does not start.
- One-track WebSocket failure: the other track continues and the local audio remains complete.
- Temporary disconnect: reconnect once for future audio and record the uncovered time range.
- Queue overflow: record a warning with the dropped interval.
- App crash: finalized JSONL records remain recoverable.
- Stop timeout: save all finalized records immediately and close the network session.

## Components

- `XFYunCredentialStore`: Keychain CRUD.
- `XFYunAuthSigner`: timestamped WebSocket URL signing.
- `RealtimePCMEncoder`: channel mixing, resampling, and Int16 encoding.
- `XFYunRealtimeClient`: one typed WebSocket session.
- `LiveTranscriptionCoordinator`: owns two clients and merges events.
- `TranscriptJournal`: append, recover, and render finalized records.
- `RecordingCoordinator`: tees decoded audio into the live coordinator without blocking local recording.
- `AppModel` and views: settings, toggle, status, live transcript window, and immediate save.

## Testing

- Keychain tests use a unique test service and delete all test items afterward.
- Auth signing uses fixed timestamps and independent expected signatures.
- PCM tests verify 48 kHz stereo system mixing and mono microphone conversion to 16 kHz Int16.
- Protocol tests use a local fake WebSocket transport and fixture messages; real credentials are never needed in unit tests.
- Journal tests cover append, flush, recovery, ordering, and Markdown export.
- Recording integration tests verify local recording proceeds when network sending is slow or fails.
- A manual test with rotated credentials verifies both live tracks, immediate stop output, and saved Markdown.

## Non-Goals

- Sharing the owner's credentials with other users.
- Shipping credentials in the app bundle.
- Cross-language translation.
- Replacing the existing audio recording/export format.
- Uploading completed recordings to a backend.

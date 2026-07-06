# Audio Transcription Design

## Goal

Add a first version of transcription for recordings created by MeetingAudioCapture. The feature converts the app's preserved system and microphone audio tracks into a readable interview transcript, with the system track labeled as the interviewer and the microphone track labeled as me.

## Scope

This first version only supports recordings produced by this app. It does not import arbitrary audio files, does not perform speaker diarization on mixed audio, does not translate text, and does not summarize transcripts.

The feature depends on the existing diagnostics preservation flow. Each completed recording already preserves:

- `system.caf`
- `microphone.caf`
- `timeline.json`

These files are stored under `.diagnostics/<recording-name>/` beside the exported `.m4a`.

## User Experience

The menu bar panel remains focused on capture controls. After a recording completes, the panel shows an action to open transcription for the most recent recording.

Transcription opens in a separate SwiftUI window. The window contains:

- The selected recording name and status.
- A start or retry transcription action.
- Progress text while the two tracks are being processed.
- A transcript view with timestamped dialogue lines.
- Copy transcript and save transcript actions.

Dialogue labels are fixed for the first version:

- `system.caf` -> Interviewer
- `microphone.caf` -> Me

Chinese UI strings should follow the existing localization pattern.

## Architecture

Add a new transcription feature area under `Sources/MeetingAudioCapture/Transcription/`.

Core types:

- `TranscriptionSession`: Identifies an app-created recording and the matching diagnostics directory.
- `TranscriptionSpeaker`: Represents `interviewer` and `me`.
- `TranscriptionSegment`: Timestamp, speaker, and recognized text.
- `TranscriptionResult`: Recording URL plus ordered transcript segments.
- `TranscriptionService`: Runs Speech framework recognition on the two preserved CAF files and merges segments by timestamp.

UI types:

- `TranscriptionWindowController` or equivalent app-level window owner to manage the standalone window.
- `TranscriptionViewModel` for loading status, errors, and transcript state.
- `TranscriptionView` for the SwiftUI transcript surface.

The existing `AppModel` should expose a narrow action such as `openTranscriptionForLastRecording()`. It should not absorb transcription state beyond what is required to open the window.

## Data Flow

1. Recording completes and `RecordingExporter` preserves diagnostics for the exported `.m4a`.
2. `RecordingSnapshot.outputFile` points at the exported `.m4a`.
3. The menu bar panel enables a transcription action when the matching diagnostics directory exists.
4. The transcription window resolves:
   - `<destination>/.diagnostics/<recording-stem>/system.caf`
   - `<destination>/.diagnostics/<recording-stem>/microphone.caf`
5. `TranscriptionService` submits two `SFSpeechURLRecognitionRequest` jobs.
6. Results are mapped to speakers and merged by segment start time.
7. The UI displays the ordered transcript and enables copy/save.

## Speech Recognition

Use Apple's Speech framework for the first version. The implementation should request speech recognition authorization before transcription starts and show an actionable error when authorization is denied or unavailable.

The first version should use the current app language as the recognition locale:

- English UI -> `en-US`
- Simplified Chinese UI -> `zh-CN`

The first version does not add a separate per-recording recognition language selector.

If recognition fails for one track but succeeds for the other, the window should show the successful track and a visible warning for the failed track.

## Error Handling

The transcription window should handle these states:

- Missing diagnostics directory.
- Missing `system.caf` or `microphone.caf`.
- Speech recognition not authorized.
- Speech recognizer unavailable for the selected locale.
- Recognition failure for one or both tracks.
- Save transcript failure.

Errors should be user-facing and localized.

## Export Format

Saving writes a UTF-8 Markdown file next to the `.m4a` by default:

`<recording-name>-transcript.md`

Transcript format:

```markdown
# Meeting Transcript

Source: Meeting-YYYYMMDD-HHMMSS.m4a

[00:00:03] Interviewer: ...
[00:00:12] Me: ...
```

The copy action copies the same body text without requiring a file save.

## Testing

Unit tests should cover:

- Resolving diagnostics paths from an output `.m4a`.
- Mapping system and microphone tracks to the correct speakers.
- Merging transcript segments by timestamp.
- Rendering Markdown transcript output.
- Error handling for missing diagnostics files.

Speech framework calls should be behind a protocol so tests can use deterministic fake recognition results.

## Non-Goals

- Importing arbitrary audio files.
- Speaker diarization from a mixed audio track.
- Translation.
- Summarization.
- Real-time transcription while recording.
- Manual speaker relabeling.

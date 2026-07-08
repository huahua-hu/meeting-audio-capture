# Remove Post-Recording Transcription Design

## Goal

Remove the complete Apple Speech post-recording transcription workflow. The application will only support XFYun real-time transcription during recording.

## Remove

- The `Transcribe` button shown after a recording completes.
- The `Select Audio and Transcribe` button and file picker.
- AppModel state and actions used only by those buttons.
- The transcription window, view model, Apple Speech service, stereo extraction, session resolution, formatting, and segment assembly code.
- Localization strings and tests used only by post-recording transcription.
- `NSSpeechRecognitionUsageDescription` from the application Info.plist.

## Keep

- XFYun credentials in Keychain.
- Two independent real-time transcription connections for system audio and microphone audio.
- Incremental JSONL transcript persistence.
- Time-ordered, speaker-interleaved Markdown export next to the M4A.
- Diagnostic CAF and timeline files used for recording recovery and diagnostics.

## Transcript Time

- Each exported speaker turn uses the wall-clock time at which its first recognized word occurred.
- The display format is `[yyyy-MM-dd HH:mm:ss]` in the user's current time zone.
- The session start wall-clock date plus XFYun's relative phrase start time produces the displayed date.
- Relative phrase time remains the ordering key so operating-system clock adjustments cannot reorder a meeting.

## Verification

- Source scans contain no post-recording transcription UI or Apple Speech imports.
- The real-time transcript tests continue to pass.
- The complete Swift test suite passes after obsolete tests are removed.
- A release app builds, is installed in `/Applications`, passes code-sign verification, and launches.

# Existing M4A Transcription Design

## Goal

Allow users to select existing stereo M4A recordings exported by MeetingAudioCapture and open the transcription workflow without requiring preserved `.diagnostics` files.

## User Experience

- Add an always-visible `Select Audio and Transcribe` command to the menu bar panel.
- Present a file picker restricted to `.m4a` files.
- Open the existing standalone transcription window after selection.
- Keep the existing post-recording transcription command.
- Show actionable errors in the menu panel or transcription window when the file is unreadable, is not stereo, or preprocessing fails.

## Audio Contract

MeetingAudioCapture exports stereo M4A files with this stable channel layout:

- Left channel: system audio, labeled `Interviewer`.
- Right channel: microphone audio, labeled `Me`.

The import path supports this application-owned format only. It does not perform speaker diarization or infer channel ownership for arbitrary audio files.

## Architecture

`TranscriptionSession` supports two track sources:

1. Preserved diagnostics (`system.caf` and `microphone.caf`).
2. A stereo exported M4A requiring channel extraction.

`StereoChannelExtractor` reads the selected M4A in bounded PCM chunks and writes two temporary mono audio files. It never loads the complete recording into memory. `TranscriptionService` recognizes the two prepared tracks and removes temporary files after completion or failure.

Long recordings are divided into bounded-duration chunks before Speech recognition. Segment timestamps receive each chunk's time offset before the two speaker streams are merged. This avoids passing a 60-minute recording to a single Speech recognition request.

## Data Flow

1. User selects an M4A from the menu panel.
2. The app validates that the file is readable and has two channels.
3. A transcription window opens and starts preprocessing.
4. Left and right channels are extracted into temporary chunk files.
5. Apple Speech recognizes chunks using the current UI language (`en-US` or `zh-CN`).
6. Results are offset, labeled, merged by timestamp, and displayed.
7. Temporary files are deleted.
8. Copy and Markdown save behavior remains unchanged.

## Error Handling

- Reject non-M4A selections in the picker.
- Reject unreadable or non-stereo files with a localized error.
- Preserve partial results when one speaker track fails, using the existing warning model.
- Clean up temporary files on success and failure.
- Keep the original recording unchanged.

## Testing

- Session resolution accepts a stereo exported M4A when diagnostics are absent.
- Session resolution continues to prefer preserved diagnostics.
- Channel extraction maps left and right samples correctly and uses bounded chunks.
- Chunk recognition applies timestamp offsets and merges speakers in order.
- The menu action is present independently of recording state.
- Existing transcription, localization, recording, and export tests remain green.

## Non-Goals

- Arbitrary mixed mono audio.
- Automatic speaker diarization.
- Translation or summarization.
- Manual speaker relabeling.
- Rewriting or modifying the selected M4A.

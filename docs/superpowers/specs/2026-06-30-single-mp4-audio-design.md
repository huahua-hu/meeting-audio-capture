# Single MP4 Audio Output Design

## Goal

Replace the current recording directory containing separate system, microphone,
mixed M4A files, and metadata JSON with one portable MP4 file. The file must
play both participants normally by default while retaining independently
identifiable system and microphone audio for future extraction.

## Output Contract

Each completed recording produces exactly one user-visible file in the selected
output directory:

`Meeting-YYYYMMDD-HHmmss.mp4`

The timestamp uses the user's current time zone and the Gregorian calendar. The
application permits only one active recording, so second-level precision is
sufficient. If a file with the same name already exists, append `-2`, `-3`, and
so on rather than overwriting it.

The MP4 contains three AAC audio tracks aligned to the same zero-based timeline:

1. `Mixed` — the default enabled track. System audio retains its stereo image;
   microphone audio is centered and mixed into both channels.
2. `System Audio` — the captured system audio without microphone audio.
3. `Microphone` — the captured microphone audio without system audio.

The three-track design is intentional. Common players usually select one MP4
audio track rather than mixing two independent tracks. A default mixed track
therefore provides compatible playback, while the two source tracks preserve
future extraction capability. This release does not add an in-app extraction
feature.

## Recording and Export Flow

At recording start, create a uniquely named session directory below
`FileManager.default.temporaryDirectory`, scoped under an application-owned
`MeetingAudioCapture` directory. Store the system and microphone PCM CAF files
there. No recording directory or metadata file is created in the user's output
location at this stage.

At recording stop:

1. Finish both PCM writers.
2. Build the three AAC tracks into a temporary MP4 inside the session directory.
3. Validate that the MP4 is readable and contains all three named audio tracks.
4. Move the completed MP4 into the selected output directory using the final
   collision-safe filename.
5. Delete the session directory and all source files only after the destination
   file exists successfully.

The public completion snapshot points to the final MP4 file rather than a
recording directory. UI actions that reveal output should select or reveal that
file.

## Failure and Cleanup Behavior

An export or final move failure must not leave a visible partial MP4 in the
output directory. The application reports a localized export error and marks the
recording failed.

Failed session data remains in the system temporary directory for the rest of
the current process, avoiding deletion while an export failure is being handled.
On the next application launch, remove stale application-owned session
directories. The cleanup routine must never traverse or delete unrelated system
temporary files.

If the final MP4 was moved successfully but temporary cleanup fails, the
recording still counts as completed; cleanup is retried on the next launch.

## Metadata and Privacy

Remove `metadata.json` and the related metadata model and serialization code.
Do not place microphone names, operating-system versions, app versions, errors,
or other device information in the filename or MP4 metadata. Only generic track
labels and the recording timestamp are stored.

## Compatibility

Use the MP4 container with AAC audio at the existing 48 kHz recording timeline.
The mixed track is stereo and is marked as the default playback choice. Source
track channel layouts follow their captured content: system audio may be stereo,
while microphone audio may be mono.

The output must open and play the mixed track in QuickTime Player and remain
inspectable by tools that understand multiple MP4 audio tracks, such as VLC or
ffmpeg. Player-specific presentation of the two non-default tracks is not part of
the compatibility guarantee.

## Code Boundaries

- `RecordingFiles` becomes a session/output-path value responsible for temporary
  source URLs and collision-safe final MP4 naming.
- `RecordingExporter` owns construction, labeling, validation, and finalization
  of the three-track MP4.
- `RecordingCoordinator` continues to own lifecycle state and delegates all file
  production and cleanup to the file/export components.
- A focused stale-session cleanup component removes only application-owned
  temporary session directories.

These responsibilities should remain testable without starting a live
ScreenCaptureKit recording.

## Verification

Automated tests must cover:

- filename formatting and collision handling;
- temporary session placement outside the selected output directory;
- absence of `metadata.json` and separate user-visible M4A files;
- successful output containing exactly three named audio tracks;
- `Mixed` being the default enabled track;
- aligned track start times and expected duration;
- mixed-track samples containing both system and microphone fixtures;
- deletion of source files after successful finalization;
- no partial destination file after export failure;
- narrowly scoped stale-session cleanup;
- existing pause/resume timeline and boundary-click regression behavior.

Before release, run the full Swift test suite, build the application bundle, and
verify its code signature. Manually open a generated fixture or recording in
QuickTime Player and confirm that normal playback uses the mixed track.

## Out of Scope

- In-app extraction or splitting of source tracks.
- Speech transcription, analysis, or cloud upload.
- Video capture or a placeholder video track.
- User-configurable codecs, bitrates, track names, or filename templates.
- Recovery UI for failed temporary sessions.

# Stereo M4A Output and Visible Menu Status Design

## Goal

Replace the three-track MP4 output with one conventional stereo M4A file that
keeps system and microphone audio separable by channel. Also make the subtle
recording and paused indicators reliably visible in the macOS menu bar.

This specification supersedes the output-container and audio-track sections of
`2026-06-30-single-mp4-audio-design.md`. The temporary-session, privacy,
filename timestamp, and failure-cleanup requirements from that specification
remain in force unless changed below.

## Output Contract

Each completed recording produces exactly one user-visible file:

`Meeting-YYYYMMDD-HHmmss.m4a`

Use AAC at 48 kHz and a target bitrate of 192 kbps. The file contains one stereo
audio track with this fixed mapping:

- channel 1 / left: system audio, downmixed from captured stereo to mono;
- channel 2 / right: microphone audio.

Do not create a user-visible MP4, metadata JSON, separate source M4As, or mixed
playback file. Continue using temporary CAF or intermediate audio files only
inside the application-owned system temporary session directory, and delete
the session after the final M4A has been moved successfully.

If the final filename already exists, append `-2`, `-3`, and so on. Never
overwrite an existing recording.

## Channel Processing

Both output channels share the existing zero-based 48 kHz timeline, including
pause removal and inserted silence for timestamp gaps.

For the left channel, combine the captured system left and right channels with
equal-power-safe averaging:

`systemMono = 0.5 * systemLeft + 0.5 * systemRight`

For the right channel, copy the captured mono microphone samples without
panning or automatic gain changes. Clamp both results to the valid floating
point PCM range before AAC encoding. If one source ends before the other, pad
the shorter source with silence so both output channels have identical frame
counts.

Do not normalize, compress, gate, denoise, or automatically rebalance either
source in this version. Independent channel levels are intentional.

## Export Architecture

Read the aligned temporary CAF sources and construct one interleaved stereo PCM
stream in bounded chunks. Feed that stream to an `AVAssetWriter` audio input
configured for AAC, 48 kHz, two channels, and 192 kbps, writing directly to a
temporary M4A.

The exporter validates the temporary M4A before moving it to the destination:

- file type is M4A/MPEG-4 audio;
- exactly one audio track exists;
- channel count is two;
- sample rate is 48 kHz;
- duration matches the longer source within AAC encoder tolerance;
- left-channel fixtures contain only system audio;
- right-channel fixtures contain only microphone audio.

Only after validation succeeds may the exporter choose the collision-safe final
URL, move the file, and remove the temporary session. Export or move failure
must not leave a visible partial file. Cleanup failure after a successful move
must not delete the completed recording.

## Future Splitting

The M4A can later be decoded and split into left and right mono files. Splitting
to WAV preserves the decoded AAC samples without another lossy encoding step;
splitting to M4A or MP3 requires re-encoding. An in-app split command remains out
of scope for this version.

## Menu Bar Status Root Cause

The current recording dot and pause mark are drawn with positive horizontal and
negative vertical offsets outside the waveform's layout bounds. `MenuBarExtra`
can clip that overflow when macOS renders the status item, making idle,
recording, and paused states appear identical.

## Menu Bar Status Design

Reserve real layout space to the right of the waveform instead of drawing
badges outside a `ZStack`:

- idle and completed: waveform only;
- preparing, recording, and stopping: waveform followed by a 5-point neutral
  gray filled circle;
- paused: waveform followed by a 6-point neutral gray pause symbol;
- failed: warning triangle only.

Use a compact horizontal layout with two points of spacing. The dot and pause
symbol must be inside the view's measured bounds, with no offset, clipping,
animation, flashing, or red color. The explicit localized state and timer remain
visible inside the open menu.

## Verification

Automated tests must verify:

- `.m4a` filename formatting and collision behavior;
- one final user-visible file and no MP4/metadata output;
- exactly one stereo audio track at 48 kHz;
- left-only system fixture and right-only microphone fixture after decoding;
- equal system-channel downmix and silence padding for unequal durations;
- temporary-session removal on success and retention on export failure;
- completed output preservation when cleanup fails;
- menu indicator mappings for idle, active, paused, completed, and failed;
- the rendered status component uses in-bounds horizontal badge layout without
  offsets;
- existing pause/resume and boundary-click regressions remain passing.

Before release, run the complete Swift test suite, rebuild the application and
DMG, verify both app signatures and the DMG checksum, and manually confirm the
recording dot and paused mark in the menu bar.

## Documentation Changes

Update both READMEs to describe one stereo M4A, the left/right source mapping,
the intentionally separated headphone playback, and future channel splitting.
Remove three-track MP4 instructions from current user-facing documentation.

## Out of Scope

- MP3, WAV, MP4, or selectable output formats.
- In-app channel splitting.
- Automatic gain matching or audio enhancement.
- Changing the app icon or DMG installation design.
- Notarization, cloud processing, transcription, or analysis.

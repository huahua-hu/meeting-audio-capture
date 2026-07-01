# Audio Diagnostics and Track Leveling Design

## Goal

Make exported interview recordings easier to review by balancing the system and microphone tracks without hiding the source of audible distortion. Preserve enough lossless diagnostic data to determine whether noise originates during capture, timeline assembly, or M4A export.

## Current Evidence

Analysis of `Meeting-20260701-233210.m4a` found a valid, continuous 48 kHz AAC-LC stream with no packet gaps or decode errors. The system track did not clip, but it contained abrupt sample changes around several audio transitions. The microphone track was about 3 LU louder and reached 0 dBFS, creating clipping risk. The final M4A alone cannot identify the source of the system-track artifacts because successful export currently deletes both temporary CAF files.

## Diagnostic Artifacts

Recording continues to write lossless system and microphone CAF files in the temporary session directory. After export, the exporter moves diagnostic artifacts to:

```text
<recording destination>/.diagnostics/<M4A filename without extension>/
  system.caf
  microphone.caf
  timeline.json
```

Diagnostics are preserved after successful and failed export. The visible M4A location and application interface remain unchanged.

`timeline.json` records, for each track:

- first presentation timestamp;
- received buffer count;
- inserted silence frame count;
- discarded overlap frame count;
- maximum observed timestamp gap;
- timestamps of material gaps or overlaps.

The application retains only the five newest diagnostic directories. Startup cleanup removes older entries. Cleanup is limited to application-owned directories beneath `.diagnostics`.

## Timeline Instrumentation

`PCMTrackWriter` reports append outcomes without changing its existing alignment behavior. Each append records inserted silence and discarded overlap frames. `RecordingCoordinator` associates those values with the corresponding track and presentation timestamp, then produces the diagnostic report during finalization.

No de-clicking, denoising, crossfading, or timestamp policy change is included. The diagnostic recording must preserve the current signal so the next sample can isolate the fault accurately.

## Track Leveling

M4A export uses a two-pass process:

1. Scan both CAF files and calculate peak amplitude and gated RMS independently for the system downmix and microphone track. Silent samples do not contribute to gated RMS.
2. Calculate one constant gain per track and apply it while writing the stereo M4A.

The target is approximately -24 dBFS gated RMS. Gain is constrained by both:

- a maximum boost of +12 dB;
- a post-gain peak ceiling of -3 dBFS.

Peak safety takes precedence over the RMS target. The exporter applies no time-varying automatic gain control or compression. System audio remains on the left channel and microphone audio remains on the right channel.

If a track has no samples above the activity gate, its gain remains unity. Invalid or non-finite samples cause export to fail rather than producing a misleading recording.

## Failure Handling

Diagnostic preservation is best effort but must not delete a completed M4A. If M4A encoding succeeds and diagnostic movement fails, the completed recording remains available and the temporary session is retained for recovery. If encoding fails, no partial visible M4A remains and the raw CAF files plus report are retained.

## Testing

Automated tests cover:

- silence insertion and overlap removal statistics;
- per-track timestamp diagnostics;
- gated RMS measurement and silence handling;
- target gain, +12 dB boost limit, and -3 dBFS peak protection;
- constant-gain stereo encoding and left/right mapping;
- diagnostic CAF and JSON preservation after success and failure;
- retention of only the five newest diagnostic directories;
- all existing capture, timeline, localization, and export regressions.

Runtime validation uses the next real recording to compare `system.caf` directly with the final M4A. Distortion present in both points to capture or timeline assembly; clean CAF with distorted M4A points to leveling or AAC export.

## Scope

This work does not add noise reduction, de-clicking, compression, automatic gain riding, UI controls, transcription, or changes to the macOS version-specific capture strategies.

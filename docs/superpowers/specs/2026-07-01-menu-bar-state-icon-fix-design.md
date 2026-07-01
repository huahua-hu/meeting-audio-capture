# Menu Bar State Icon Fix Design

## Problem

The menu content correctly reports the recording state, but the macOS status item still displays only the waveform. The installed and running application binaries match the latest build, so this is not a stale-process problem. `MenuBarExtra` is clipping or discarding the secondary `HStack` content used for the gray recording dot and pause mark.

## Design

Replace the composite SwiftUI label with one template `NSImage` generated for each indicator state. The renderer will draw the existing SF Symbol waveform and its state badge into a single fixed-size menu-bar canvas. `MenuBarExtra` will receive that single image, preventing macOS from laying out or clipping the badge separately.

The visual states remain intentionally subtle:

- Idle and completed: waveform only.
- Preparing, recording, and stopping: waveform with a small gray dot.
- Paused: waveform with a small gray pause mark.
- Failed: warning symbol, preserving the current behavior.

All normal-state artwork uses template rendering so macOS controls foreground color for light mode, dark mode, disabled appearance, and menu-bar accessibility. There is no animation or colored recording indicator.

## Components

- Add a focused menu-bar image renderer that accepts `MenuBarIndicator` and returns a template `NSImage`.
- Keep `RecordingPresentation.menuBarIndicator(_:)` as the state-to-presentation mapping.
- Simplify `MenuBarIndicatorLabel` to display the one rendered image.

The renderer owns only image composition. It does not observe recording state or change application behavior.

## Testing

- Add renderer tests first, verifying distinct rendered output for idle, recording, and paused states, the expected image dimensions, and template-image behavior.
- Keep the existing presentation mapping tests.
- Run the full Swift test suite and build/sign/package checks.
- Install the rebuilt app and manually verify idle, recording, and paused icons in the macOS menu bar.

## Scope

This change only fixes status-item rendering. It does not change recording, M4A export, localization, menu layout, or notification behavior.

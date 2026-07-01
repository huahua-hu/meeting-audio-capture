# Menu Bar State Icon Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make recording and paused states visibly distinct in the macOS menu bar without color or animation.

**Architecture:** Compose the SF Symbol and badge into one template `NSImage`, then give `MenuBarExtra` one image instead of a composite SwiftUI layout. Keep recording-state mapping separate from pixel rendering.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest, macOS 15+

## Global Constraints

- Keep normal status-item artwork monochrome and template-rendered.
- Recording uses a small dot; paused uses a small pause mark; idle uses waveform only.
- Do not change recording, export, localization, or menu behavior.

---

### Task 1: Template image renderer

**Files:**
- Create: `Sources/MeetingAudioCapture/MenuBarIndicatorImageRenderer.swift`
- Create: `Tests/MeetingAudioCaptureTests/MenuBarIndicatorImageRendererTests.swift`

**Interfaces:**
- Consumes: `MenuBarIndicator`
- Produces: `MenuBarIndicatorImageRenderer.image(for:) -> NSImage`

- [ ] **Step 1: Write failing renderer tests**

Test that every output has a fixed menu-bar size and template flag, and that bitmap data differs between idle, recording, and paused indicators.

- [ ] **Step 2: Verify the tests fail**

Run: `swift test --filter MenuBarIndicatorImageRendererTests`

Expected: compilation fails because `MenuBarIndicatorImageRenderer` does not exist.

- [ ] **Step 3: Implement minimal renderer**

Create a fixed-size `NSImage`, draw the requested SF Symbol on the left, and draw either no badge, a small filled circle, or two pause bars on the right. Mark the result as a template image.

- [ ] **Step 4: Verify focused and full tests pass**

Run: `swift test --filter MenuBarIndicatorImageRendererTests && swift test`

Expected: all tests pass.

- [ ] **Step 5: Commit renderer**

```bash
git add Sources/MeetingAudioCapture/MenuBarIndicatorImageRenderer.swift Tests/MeetingAudioCaptureTests/MenuBarIndicatorImageRendererTests.swift
git commit -m "fix: render menu bar states as one image"
```

### Task 2: Integrate, package, and install

**Files:**
- Modify: `Sources/MeetingAudioCapture/MeetingAudioCaptureApp.swift`

**Interfaces:**
- Consumes: `MenuBarIndicatorImageRenderer.image(for:)`
- Produces: one `Image(nsImage:)` in the `MenuBarExtra` label

- [ ] **Step 1: Replace the composite label**

Remove the `HStack` badge layout and render the single template image returned by `MenuBarIndicatorImageRenderer`.

- [ ] **Step 2: Verify and package**

Run: `swift test && make dmg`

Expected: tests pass and `.build/MeetingAudioCapture-0.1.0.dmg` is created.

- [ ] **Step 3: Verify signature and disk image**

Run: `codesign --verify --deep --strict .build/MeetingAudioCapture.app && hdiutil verify .build/MeetingAudioCapture-0.1.0.dmg`

Expected: signature verification exits successfully and DMG CRC is valid.

- [ ] **Step 4: Commit integration**

```bash
git add Sources/MeetingAudioCapture/MeetingAudioCaptureApp.swift
git commit -m "fix: show recording state in menu bar"
```

- [ ] **Step 5: Install and launch**

Stop the current app, copy `.build/MeetingAudioCapture.app` to `/Applications`, and open the installed application. Confirm that the running executable is `/Applications/MeetingAudioCapture.app/Contents/MacOS/MeetingAudioCapture`.

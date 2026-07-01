# Upper-Right Recording Badge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the gray recording dot from the waveform's right side to a compact upper-right corner badge.

**Architecture:** Keep the existing single-template-image renderer and change only its tested layout constants. Expose badge geometry internally so placement can be verified without fragile screenshot comparison.

**Tech Stack:** Swift 6, AppKit, XCTest, macOS 15+

## Global Constraints

- Recording dot is 4 points and sits at the waveform's upper-right corner.
- Artwork remains monochrome, static, and template-rendered.
- Do not change recording or export behavior.

---

### Task 1: Compact upper-right badge layout

**Files:**
- Modify: `Sources/MeetingAudioCapture/MenuBarIndicatorImageRenderer.swift`
- Modify: `Tests/MeetingAudioCaptureTests/MenuBarIndicatorImageRendererTests.swift`

**Interfaces:**
- Produces: `MenuBarIndicatorImageRenderer.dotRect: NSRect`

- [ ] Add failing assertions for a 22-by-18 image and `dotRect == NSRect(x: 18, y: 13, width: 4, height: 4)`.
- [ ] Run `swift test --filter MenuBarIndicatorImageRendererTests` and confirm failure against the current 26-point layout.
- [ ] Change the image width, dot rectangle, and pause-bar coordinates to fit the compact canvas.
- [ ] Run focused tests and the complete test suite.
- [ ] Commit the implementation.
- [ ] Build and verify the app and DMG, install `/Applications/MeetingAudioCapture.app`, launch it, and confirm the installed binary matches the build.

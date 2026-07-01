# Upper-Right Pause Badge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the pause mark from the waveform's middle-right edge to its upper-right corner.

**Architecture:** Keep the 20-by-18 template renderer and expose the two pause bar rectangles as tested layout constants. Drawing continues through the existing single-image badge path.

**Tech Stack:** Swift 6, AppKit, XCTest, macOS 15+

## Global Constraints

- Pause badge uses two 1-by-5-point vertical bars.
- Bars occupy the upper-right 4-by-5-point area.
- Canvas remains 20 by 18 points and monochrome.

---

### Task 1: Upper-right pause geometry

**Files:**
- Modify: `Sources/MeetingAudioCapture/MenuBarIndicatorImageRenderer.swift`
- Modify: `Tests/MeetingAudioCaptureTests/MenuBarIndicatorImageRendererTests.swift`

**Interfaces:**
- Produces: `pauseBarRects == [NSRect(x: 16, y: 12, width: 1, height: 5), NSRect(x: 19, y: 12, width: 1, height: 5)]`.

- [ ] Add a failing geometry assertion and run the focused renderer tests.
- [ ] Implement the two upper-right pause rectangles.
- [ ] Run focused and complete tests, then commit.
- [ ] Build and verify app/DMG, merge to `main`, verify again, install, launch, and compare hashes.

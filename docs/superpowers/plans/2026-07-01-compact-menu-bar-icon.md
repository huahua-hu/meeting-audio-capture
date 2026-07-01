# Compact Menu Bar Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce the status-item artwork width from 22 to 20 points without losing the upper-right recording badge.

**Architecture:** Change only tested renderer layout constants: canvas width, SF Symbol point size, dot rectangle, and pause coordinates. Keep single-image template rendering unchanged.

**Tech Stack:** Swift 6, AppKit, XCTest, macOS 15+

## Global Constraints

- Canvas is 20 by 18 points.
- Waveform symbol configuration is 13 points.
- Recording dot remains 4 points at the upper-right edge.
- No recording or export behavior changes.

---

### Task 1: Compact renderer layout

**Files:**
- Modify: `Sources/MeetingAudioCapture/MenuBarIndicatorImageRenderer.swift`
- Modify: `Tests/MeetingAudioCaptureTests/MenuBarIndicatorImageRendererTests.swift`

**Interfaces:**
- Produces: `imageSize == NSSize(width: 20, height: 18)`, `symbolPointSize == 13`, and `dotRect == NSRect(x: 16, y: 13, width: 4, height: 4)`.

- [ ] Add failing assertions for the new constants.
- [ ] Run focused tests and confirm failure against the 22-point renderer.
- [ ] Implement the compact constants and update pause coordinates.
- [ ] Run focused and complete tests, then commit.
- [ ] Build and verify the app and DMG.
- [ ] Merge to `main`, verify again, install, launch, and compare installed/build hashes.

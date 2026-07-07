# Paragraph Assembly and Adaptive Concurrency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce readable speaker-turn paragraphs and accelerate chunk recognition with bounded CPU-aware concurrency.

**Architecture:** Add a pure segment assembler between recognition and formatting. Replace the sequential chunk loop with a bounded task-group scheduler whose limit derives from logical CPU count and whose collected results are sorted deterministically.

**Tech Stack:** Swift 6, Foundation structured concurrency, Speech, XCTest.

## Global Constraints

- Merge same-speaker words while gaps are at most 2 seconds.
- Chinese text joins without spaces; English text joins with spaces.
- Concurrent chunks equal `min(max(2, activeProcessorCount / 2), 6)`.
- Never return results in completion order; sort by absolute timestamp.
- Preserve partial-result and no-speech behavior.
- Preserve the unrelated `Scripts/create-dmg.sh` change.

### Task 1: Speaker-Turn Paragraph Assembly

**Files:**
- Create: `Sources/MeetingAudioCapture/Transcription/TranscriptSegmentAssembler.swift`
- Create: `Tests/MeetingAudioCaptureTests/TranscriptSegmentAssemblerTests.swift`
- Modify: `Sources/MeetingAudioCapture/Transcription/TranscriptionService.swift`

- [ ] Write failing tests for same-speaker Chinese joining, English spacing, speaker changes, and gaps over 2 seconds.
- [ ] Run `swift test --filter TranscriptSegmentAssemblerTests` and confirm the assembler is absent.
- [ ] Implement `TranscriptSegmentAssembler.assemble(_:language:maxGap:)` as a pure deterministic transform.
- [ ] Apply assembly after all recognized words are sorted.
- [ ] Run focused service and assembler tests.

### Task 2: Adaptive Bounded Chunk Concurrency

**Files:**
- Modify: `Sources/MeetingAudioCapture/Transcription/TranscriptionService.swift`
- Modify: `Tests/MeetingAudioCaptureTests/TranscriptionServiceTests.swift`

- [ ] Write failing tests for concurrency-limit calculation and overlapping fake-recognizer execution.
- [ ] Implement `TranscriptionService.chunkConcurrency(processorCount:)` with a 2...6 bound.
- [ ] Use a throwing task group with a sliding window of at most the computed chunk limit.
- [ ] Keep both speaker requests concurrent inside each chunk and sort all results by timestamp.
- [ ] Add bounded retries for service-busy/rate-limit errors only.
- [ ] Run all transcription tests.

### Task 3: Verify and Deploy

**Files:**
- No source changes unless verification exposes a defect.

- [ ] Run the complete test suite and `git diff --check`.
- [ ] Build and sign the release app with `make app`.
- [ ] Replace `/Applications/MeetingAudioCapture.app` and relaunch.
- [ ] Verify signature, installed binary, process response, and branch status.

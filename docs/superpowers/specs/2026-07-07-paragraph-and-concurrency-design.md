# Paragraph Assembly and Adaptive Concurrency Design

## Goal

Produce readable speaker turns instead of one line per recognized word, and reduce long-recording transcription time with bounded adaptive concurrency.

## Paragraph Assembly

- Sort recognized words by absolute timestamp.
- Merge adjacent words when they belong to the same speaker and the gap between word start times is at most 2 seconds.
- Start a new paragraph when the speaker changes or the gap exceeds 2 seconds.
- Preserve the first word's timestamp as the paragraph timestamp.
- Join Chinese words without spaces and English words with spaces.
- Apply assembly before Markdown rendering so display, copy, and save use identical paragraphs.

## Adaptive Concurrency

- Determine logical CPU count with `ProcessInfo.processInfo.activeProcessorCount`.
- Compute concurrent chunk count as `min(max(2, activeProcessorCount / 2), 6)`.
- Each chunk recognizes system and microphone tracks concurrently.
- Process at most the calculated number of chunks simultaneously.
- Collect results independently of completion order, then sort by absolute timestamp.
- Preserve partial results and warnings using the existing behavior.
- Treat `No speech detected` as an empty successful track.

## Load Control

Apple Speech is an external service and is not CPU-bound. The six-chunk ceiling prevents high-core machines from creating unbounded Speech requests. Service-busy and rate-limit failures are retried with bounded delay; persistent failures remain warnings and do not discard successful chunks.

## Testing

- Chinese words from one speaker become one paragraph without spaces.
- English words become one paragraph with spaces.
- Speaker changes and gaps over 2 seconds create new paragraphs.
- Adaptive concurrency returns 2 for low-core systems and never exceeds 6.
- A fake recognizer verifies multiple chunks overlap in execution and final output remains timestamp ordered.
- Existing transcription and UI tests remain green.

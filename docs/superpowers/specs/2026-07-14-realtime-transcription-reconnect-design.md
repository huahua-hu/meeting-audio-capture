# Realtime Transcription Reconnect Design

## Goal

Keep each XFYun realtime transcription track running across transient WebSocket failures without showing a user-facing warning. Stop retrying one track after ten consecutive failed connection attempts while leaving audio recording and the other track unaffected.

## Root Cause

The current transcriber creates one WebSocket per track and exits its worker after the first connection, receive, or send error. On 2026-07-14 both WebSocket upgrades succeeded through the system proxy, then the proxy closed both sockets immediately. The errors were intentionally swallowed, so recording completed without a transcript journal.

## Behavior

- System audio and microphone use independent workers and independent failure counters.
- A worker reconnects one second after a failed connection, receive, or send operation.
- A server `started` event marks a connection as established and resets that track's consecutive failure counter.
- A failed attempt before `started` increments the counter.
- The tenth consecutive failed attempt stops that track's worker silently.
- No new alert, banner, or recording failure is presented.
- Audio recording and export continue regardless of transcription state.
- Each track buffers the newest 2,048 chunks while reconnecting. A chunk whose send fails remains pending for the next connection.
- Every audio chunk carries its absolute PCM byte offset. If the bounded buffer evicts audio, the next connection uses that absolute offset and transcript entries stay on the original recording timeline.
- A receive failure injects a connection-scoped control event into the same input stream, waking a worker even when no new audio is arriving.
- Finishing a recording immediately prevents new connection attempts, sends the XFYun end marker when connected, then closes active sockets and waits for both workers after the existing grace period.

## Structure

`XFYunReconnectPolicy` owns the deterministic threshold and delay rules. `XFYunRealtimeTranscriber` owns each long-lived track worker, keeps the stream iterator across connection attempts, and uses the policy without exposing status to the UI.

## Testing

- Unit-test attempts one through nine returning a one-second retry and attempt ten returning give-up.
- Unit-test `started` resetting the consecutive failure counter.
- Unit-test the worker reconnecting after a transport failure and preserving the pending audio chunk.
- Unit-test the worker creating exactly ten failed connections before stopping.
- Unit-test the absolute PCM byte offsets used to preserve transcript timestamps across replacement connections and buffer eviction.
- Unit-test post-start receive failure, a receive blocked until socket cancellation, buffer eviction, and finish during retry/initial connection.
- Run the complete Swift test suite.
- Perform a real short recording with the local proxy path unavailable, restore connectivity, and verify that a transcript journal is created after reconnection.

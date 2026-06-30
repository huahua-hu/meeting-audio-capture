# Contributing

Contributions are welcome.

## Requirements

- macOS 15 or later
- Xcode 16 or later
- No third-party runtime dependencies without an approved design discussion

## Workflow

1. Create a focused branch.
2. Add a failing test for behavior changes.
3. Implement the smallest change that passes the test.
4. Run `make test` and `make app`.
5. Explain user-visible changes and privacy implications in the pull request.

Keep capture callbacks, timeline calculations, file writing, export, coordination, and UI in their existing focused components. Core behavior must remain testable without granting ScreenCaptureKit permissions.

Do not add networking, telemetry, cloud processing, hidden recording, recording-indicator evasion, or detection-evasion features without a separate public design review. Recorded content must stay local by default.

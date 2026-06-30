# MeetingAudioCapture

An open-source, local-only macOS menu-bar app. It uses ScreenCaptureKit to record system output and microphone input into one MP4 containing a playback mix and independently identifiable source tracks for reviewing meetings, interviews, and conversations.

[中文](README.md)

## Features

- One MP4 containing default mix, system-audio, and microphone tracks
- Live level meters for both sources
- Pause, resume, and stop controls
- Local-only output with temporary sources deleted after successful export
- No networking, telemetry, cloud processing, or virtual audio driver
- Menu-bar interface with no Dock icon

## Requirements

- macOS 15.0 or later
- Xcode 16 or later
- Compiled on macOS 15.5 (24F74); macOS 26 still requires manual verification on the target Mac

## Build and run

```bash
make test
make app
make run
```

The app bundle is created at `.build/MeetingAudioCapture.app`. It is ad-hoc signed for local development. This release is source-only and is not Apple-notarized.

## Usage

1. Start the app and click the waveform icon in the menu bar.
2. The first launch defaults to English. Use `Language` at the bottom of the menu to select `简体中文`; the interface updates immediately and remembers the selection.
3. Select a microphone and destination folder.
4. Click **Start Recording**.
5. Grant Microphone and Screen & System Audio Recording access when macOS asks. A restart may be required after first authorization.
6. Confirm both meters respond before starting the meeting.
7. Stop recording, wait for export to finish, and reveal the recording in Finder.

Each session creates one file:

```text
Meeting-YYYYMMDD-HHmmss.mp4
```

Regular players use the `Mixed` track by default. The MP4 also contains `System Audio` and `Microphone` source tracks that multi-track tools such as VLC and ffmpeg can identify and extract. This version does not include an in-app split command. Recording-time CAF/M4A sources live in the macOS temporary directory and are deleted after the MP4 is finalized successfully.

The system track captures all system playback, including notifications. Enable Do Not Disturb, close unrelated audio apps, and use headphones before an important meeting.

## Permissions and troubleshooting

Under System Settings > Privacy & Security, verify that MeetingAudioCapture has access to Microphone and Screen & System Audio Recording. If a meter stays at `No signal`, verify the meeting app output device, selected microphone, permissions, and then restart MeetingAudioCapture.

## Privacy and responsible use

MeetingAudioCapture does not upload, analyze, or share recordings. It does not attempt to evade recording indicators or detection by macOS, meeting software, or device-management tools. Third-party behavior may change; this project does not guarantee that recording is undetectable.

Follow applicable laws, meeting rules, employer policies, confidentiality duties, and consent requirements. Do not distribute recordings containing private information, personal data, or trade secrets.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for architecture and test requirements and [SECURITY.md](SECURITY.md) for vulnerability reporting.

## License

MIT

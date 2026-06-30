# Runtime English and Simplified Chinese Localization Design

## Goal

Add an in-app language selector to MeetingAudioCapture. A new installation starts in English. Users can switch the full menu-bar interface to Simplified Chinese immediately, and the selected language persists across launches.

## Scope

The change localizes all user-facing application text:

- recording state labels and elapsed-time context;
- audio-track labels and no-signal text;
- microphone and destination controls;
- start, pause, resume, stop, folder, privacy, refresh, and quit actions;
- preparation, saving, permission, capture, export, disk-space, and runtime errors;
- consent and responsible-use guidance;
- language names and the language-selector label.

The following remain language-neutral and unchanged:

- recording directory and audio file names;
- `metadata.json` keys and status values;
- Git history, source identifiers, and diagnostic data;
- microphone device names supplied by macOS.

## Approach

Use a type-safe in-process localization table rather than Apple String Catalog resources. The project is a Swift Package wrapped manually into an app bundle; an in-process table avoids adding resource-bundle copying and makes immediate language changes deterministic.

Define:

- `AppLanguage`: `english` and `simplifiedChinese`, with stable persisted raw values.
- `LocalizedStringKey`: one case for every translatable message or label.
- `AppLocalizer`: resolves a key for a selected language, supports formatted values, and falls back to English if a Chinese entry is unavailable.

English and Simplified Chinese translations live together in a focused localization source file. Views request text by key and must not contain new user-facing string literals.

## State and Data Flow

`AppModel` owns `language` and initializes it from `UserDefaults`. If the preference is absent or invalid, it uses English. Changing `language` writes the stable raw value immediately.

`RecorderMenuView` shows a `Language / 语言` picker. SwiftUI observes `AppModel.language`, so every localized label is recomputed immediately without restarting the app. Switching language is permitted while preparing, recording, paused, or saving because it changes presentation only.

Recording, capture, file writing, output names, timing, and audio data do not depend on the selected language.

## Error Handling

Domain errors carry stable typed values and associated technical details rather than finalized English sentences where practical. `AppLocalizer` renders known errors in the selected language. Unknown system errors retain their original macOS-provided description and are prefixed with a localized generic error label.

Invalid or obsolete stored language values fall back to English and are replaced with the valid English value on the next preference write.

## Testing

Automated tests verify:

- English is the default when no valid preference exists.
- English and Simplified Chinese raw values round-trip through persistence.
- every localization key resolves to non-empty English and Chinese text.
- representative recording states, controls, consent guidance, and permission errors render correctly in both languages.
- formatted messages preserve their dynamic values in both languages.
- language selection does not alter recording filenames or metadata schema.

After implementation, run the complete test suite, create a Release app bundle, verify its ad-hoc signature, switch languages during an active short recording, and confirm the audio outputs remain valid.


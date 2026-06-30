# Runtime English and Simplified Chinese Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an immediately switchable, persisted English and Simplified Chinese interface while keeping English as the first-launch default.

**Architecture:** A type-safe `AppLanguage` and `AppTextKey` feed a single `AppLocalizer` table. `AppModel` owns and persists the language, while SwiftUI views resolve every user-facing label from the selected language without changing audio or file behavior.

**Tech Stack:** Swift 6, SwiftUI, Observation, Foundation `UserDefaults`, XCTest.

## Global Constraints

- New installations default to English.
- Supported languages are English and Simplified Chinese only.
- Switching takes effect immediately and remains allowed during recording.
- The selected stable raw value persists across launches.
- Missing translations fall back to English.
- Recording directory names, audio filenames, `metadata.json` keys, status values, and microphone device names remain unchanged.
- No String Catalog or external localization dependency is introduced.
- Existing macOS 15.0 deployment floor, local-only privacy boundary, and audio behavior remain unchanged.

---

### Task 1: Type-Safe Localization Core

**Files:**
- Create: `Sources/MeetingAudioCapture/Localization/AppLocalization.swift`
- Create: `Tests/MeetingAudioCaptureTests/AppLocalizationTests.swift`

**Interfaces:**
- Produces: `AppLanguage`, `AppTextKey`, `AppLocalizer.text(_:language:)`, and `AppLocalizer.format(_:language:_:)`.
- Consumes: Foundation only.

- [ ] **Step 1: Write failing tests for defaults, completeness, fallback, and formatting**

Create tests that assert:

```swift
XCTAssertEqual(AppLanguage.defaultLanguage, .english)
XCTAssertEqual(AppLanguage(rawValue: "zh-Hans"), .simplifiedChinese)
XCTAssertEqual(AppLocalizer.text(.startRecording, language: .english), "Start Recording")
XCTAssertEqual(AppLocalizer.text(.startRecording, language: .simplifiedChinese), "开始录音")
for key in AppTextKey.allCases {
    XCTAssertFalse(AppLocalizer.text(key, language: .english).isEmpty)
    XCTAssertFalse(AppLocalizer.text(key, language: .simplifiedChinese).isEmpty)
}
XCTAssertEqual(
    AppLocalizer.format(.genericErrorFormat, language: .simplifiedChinese, "磁盘已满"),
    "错误：磁盘已满"
)
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter AppLocalizationTests`

Expected: FAIL because `AppLanguage`, `AppTextKey`, and `AppLocalizer` do not exist.

- [ ] **Step 3: Implement the localization types and complete table**

Define:

```swift
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    static let defaultLanguage: AppLanguage = .english
    var id: String { rawValue }
}

enum AppTextKey: CaseIterable, Sendable {
    case language, english, simplifiedChinese
    case ready, checkingAudio, recording, paused, saving, saved, failed
    case systemAudio, microphone, noSignal, systemDefault, saveTo, choose
    case openPrivacySettings, openFolder, consentNotice, refreshMicrophones, quit
    case startRecording, waitingForTracks, pause, stop, resume, savingFiles
    case permissionDenied, noDisplay, captureSetupFormat, insufficientSpace
    case exportFailed, unexpectedCaptureStop, genericErrorFormat
}
```

Implement `AppLocalizer` with complete English and Chinese dictionaries, English fallback, and `String(format:locale:arguments:)` formatting. Keep dynamic technical details unchanged inside formatted localized prefixes.

- [ ] **Step 4: Run focused tests and commit**

Run: `swift test --filter AppLocalizationTests`

Expected: all localization tests PASS with no warnings.

Commit:

```bash
git add Sources/MeetingAudioCapture/Localization Tests/MeetingAudioCaptureTests/AppLocalizationTests.swift
git commit -m "feat: add runtime English and Chinese localization"
```

---

### Task 2: Persisted Language State and Fully Localized Menu

**Files:**
- Modify: `Sources/MeetingAudioCapture/AppModel.swift`
- Modify: `Sources/MeetingAudioCapture/Views/RecorderMenuView.swift`
- Modify: `Sources/MeetingAudioCapture/Views/AudioLevelView.swift`
- Modify: `Sources/MeetingAudioCapture/Recording/RecordingPresentation.swift`
- Modify: `Tests/MeetingAudioCaptureTests/RecordingPresentationTests.swift`
- Create: `Tests/MeetingAudioCaptureTests/AppLanguagePreferenceTests.swift`

**Interfaces:**
- Consumes: Task 1 `AppLanguage`, `AppTextKey`, and `AppLocalizer`.
- Produces: `AppModel.language`, `AppModel.text(_:)`, immediate view refresh, and persisted language selection.

- [ ] **Step 1: Write failing preference and presentation tests**

Use an isolated `UserDefaults` suite and assert that no stored value resolves to English, `zh-Hans` resolves to Simplified Chinese, and invalid stored values resolve to English. Update state-label tests to call:

```swift
RecordingPresentation.stateLabel(.recording, language: .english)
RecordingPresentation.stateLabel(.recording, language: .simplifiedChinese)
```

Expected values are `Recording` and `录音中`.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `swift test --filter 'AppLanguagePreferenceTests|RecordingPresentationTests'`

Expected: FAIL because persisted language resolution and language-aware state labels are missing.

- [ ] **Step 3: Implement persisted language state**

Add `AppLanguagePreference` with key `appLanguage`, `load(from:)`, and `save(_:to:)`. Add `var language: AppLanguage` to `AppModel`, initialize it from the preference, save in `didSet`, and expose:

```swift
func text(_ key: AppTextKey) -> String {
    AppLocalizer.text(key, language: language)
}
```

- [ ] **Step 4: Replace all menu and meter literals**

Add a `Picker` bound to `$model.language` with English and 简体中文 choices. Replace every user-facing literal in `RecorderMenuView` and `AudioLevelView` with keys resolved through `AppModel`. Change `RecordingPresentation.stateLabel` to accept `AppLanguage`. Keep `MeetingAudioCapture`, paths, dBFS, device names, and elapsed digits language-neutral.

- [ ] **Step 5: Localize application-owned error presentation**

Map typed `CaptureFailure` and known `RecordingFailure` messages to localized keys in `AppModel`. Wrap unknown system error text with `.genericErrorFormat`. Do not translate the embedded macOS technical description.

- [ ] **Step 6: Run tests, build, and commit**

Run:

```bash
swift test
swift build
```

Expected: all tests PASS and the app compiles without warnings.

Commit:

```bash
git add Sources/MeetingAudioCapture Tests/MeetingAudioCaptureTests
git commit -m "feat: add persisted in-app language switching"
```

---

### Task 3: Documentation, Release Build, Sync, and Smoke Test

**Files:**
- Modify: `README.md`
- Modify: `README.en.md`

**Interfaces:**
- Produces: documented bilingual switching and a verified app at the user-requested Desktop repository.

- [ ] **Step 1: Document language switching**

Add instructions to both README files: first launch is English, use `Language / 语言` in the menu to select 简体中文, the change is immediate, and the preference persists.

- [ ] **Step 2: Run complete verification**

Run:

```bash
make test
make app
codesign --verify --deep --strict .build/MeetingAudioCapture.app
git diff --check
```

Expected: all tests PASS, the Release app builds, signature verification exits 0, and no whitespace errors are reported.

- [ ] **Step 3: Commit documentation**

```bash
git add README.md README.en.md
git commit -m "docs: explain runtime language switching"
```

- [ ] **Step 4: Sync and launch**

Confirm `/Users/yang/Desktop/test-projects/meeting-audio-capture` is clean, stop the running old app, sync the verified repository and `.build/MeetingAudioCapture.app`, verify the target commit and signature, then launch the new app.

- [ ] **Step 5: Manual smoke test**

Switch English → 简体中文 → English, restart the app and confirm the last selection persists, then switch language during a short recording and verify recording state and audio files remain valid.

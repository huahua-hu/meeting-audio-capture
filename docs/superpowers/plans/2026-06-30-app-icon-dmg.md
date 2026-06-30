# App Icon and Drag-to-Install DMG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the approved Dual Wave macOS icon and produce a versioned DMG whose Finder window prompts users to drag MeetingAudioCapture into Applications.

**Architecture:** Keep a 1024-pixel source icon and compiled ICNS in the repository, copy the ICNS into the app bundle before signing, and use a system-tool-only shell script to create and lay out a compressed disk image. The Makefile remains the public interface through `make app` and `make dmg`.

**Tech Stack:** Swift 6, XCTest, Make, POSIX shell, `sips`, `iconutil`, `hdiutil`, Finder AppleScript, `ditto`, macOS 15+

## Global Constraints

- Use the approved Dual Wave artwork: navy rounded square, cyan and blue-violet waveforms, small gray status dot, no text or red recording symbol.
- Keep the deployment floor at macOS 15.0 and add no third-party dependencies.
- Keep the current ad-hoc signing flow; do not claim notarization or Gatekeeper suppression.
- The final file is `.build/MeetingAudioCapture-<CFBundleShortVersionString>.dmg`.
- The DMG contains the app, an Applications symlink, hidden background assets, and Finder metadata only.
- Do not modify an app already installed in `/Applications`.

---

### Task 1: Generate and Compile the Dual Wave Icon

**Files:**
- Create: `Design/AppIcon-1024.png`
- Create: `Config/AppIcon.icns`
- Modify: `Tests/MeetingAudioCaptureTests/BundleConfigurationTests.swift`

**Interfaces:**
- Produces a 1024-by-1024 source PNG and a valid macOS ICNS containing 16, 32, 128, 256, and 512 point `1x`/`2x` representations.

- [ ] **Step 1: Generate the approved icon master with imagegen**

Generate a centered, front-facing macOS app icon with exact Dual Wave colors and geometry. Inspect the result at full resolution; reject text, extra symbols, gradients that reduce small-size contrast, and inconsistent corner geometry.

- [ ] **Step 2: Write the failing bundle asset test**

Extend `BundleConfigurationTests` to assert:

```swift
XCTAssertEqual(info["CFBundleIconFile"] as? String, "AppIcon")
XCTAssertTrue(FileManager.default.fileExists(atPath: config.appending(path: "AppIcon.icns").path))
```

Run: `swift test --filter BundleConfigurationTests`

Expected: failure because the plist key and ICNS do not exist.

- [ ] **Step 3: Produce the iconset and ICNS**

Use `sips` to generate `icon_16x16.png`, `icon_16x16@2x.png`, `icon_32x32.png`, `icon_32x32@2x.png`, `icon_128x128.png`, `icon_128x128@2x.png`, `icon_256x256.png`, `icon_256x256@2x.png`, `icon_512x512.png`, and `icon_512x512@2x.png`, then compile with:

```bash
iconutil -c icns AppIcon.iconset -o Config/AppIcon.icns
```

Add `CFBundleIconFile` = `AppIcon` to `Config/Info.plist`.

- [ ] **Step 4: Run focused tests and inspect ICNS**

Run: `swift test --filter BundleConfigurationTests`

Run: `iconutil -c iconset Config/AppIcon.icns -o /tmp/MeetingAudioCapture.iconset`

Expected: tests pass and all ten expected PNG representations are extracted.

- [ ] **Step 5: Commit**

```bash
git add Design/AppIcon-1024.png Config/AppIcon.icns Config/Info.plist Tests/MeetingAudioCaptureTests/BundleConfigurationTests.swift
git commit -m "feat: add Dual Wave application icon"
```

### Task 2: Bundle the Icon and Add DMG Background

**Files:**
- Modify: `Makefile`
- Create: `Config/DMGBackground.png`
- Modify: `Tests/MeetingAudioCaptureTests/BundleConfigurationTests.swift`

**Interfaces:**
- `make app` produces `.build/MeetingAudioCapture.app/Contents/Resources/AppIcon.icns` before signing.
- Produces a 1320-by-840 pixel background for a 660-by-420 point Retina Finder window.

- [ ] **Step 1: Add a failing built-bundle resource assertion**

Run the current `make app`, then assert the configured icon is absent from `Contents/Resources`; record the failure as the red phase.

- [ ] **Step 2: Update the app bundle recipe**

Create `Contents/Resources`, copy `Config/AppIcon.icns`, then sign. Keep executable and plist copying unchanged.

- [ ] **Step 3: Create the DMG background**

Create a pale gray-blue 1320-by-840 PNG with generous whitespace and a centered left-to-right arrow between the app and Applications icon positions. Do not bake app or folder icons into the background; Finder supplies those.

- [ ] **Step 4: Verify the built bundle**

Run: `make app`

Run: `test -f .build/MeetingAudioCapture.app/Contents/Resources/AppIcon.icns`

Run: `codesign --verify --deep --strict .build/MeetingAudioCapture.app`

Expected: all commands exit 0 and Finder displays the Dual Wave icon for the built app.

- [ ] **Step 5: Commit**

```bash
git add Makefile Config/DMGBackground.png Tests/MeetingAudioCaptureTests/BundleConfigurationTests.swift
git commit -m "build: bundle app icon and DMG background"
```

### Task 3: Build the Drag-to-Applications DMG

**Files:**
- Create: `Scripts/create-dmg.sh`
- Modify: `Makefile`

**Interfaces:**
- Produces: `make dmg`
- Consumes: `.build/MeetingAudioCapture.app`, `Config/DMGBackground.png`, and the short version from the built app's Info.plist.

- [ ] **Step 1: Verify the target is missing**

Run: `make -n dmg`

Expected: FAIL with `No rule to make target 'dmg'`.

- [ ] **Step 2: Implement the packaging script**

Use `set -eu`, verify required tools and inputs, create a staging directory, copy the app with `ditto`, create an `Applications` symlink, and create a writable HFS+ disk image. Attach it with a known mount point and use Finder AppleScript to set icon view, 112-point icons, a 660-by-420 window, app position `(170, 210)`, Applications position `(490, 210)`, hidden toolbar/status bar/sidebar, and `.background/DMGBackground.png` as the background.

Install a trap that detaches the mounted volume and removes staging/writable-image files. After Finder writes `.DS_Store`, detach and convert to compressed UDZO format at the versioned final path.

- [ ] **Step 3: Add the Makefile target**

Declare `dmg: app` and invoke `Scripts/create-dmg.sh "$(APP_DIR)" "Config/DMGBackground.png" ".build"`. Add `dmg` to `.PHONY`.

- [ ] **Step 4: Validate syntax and build the DMG**

Run: `sh -n Scripts/create-dmg.sh`

Run: `make dmg`

Expected: `.build/MeetingAudioCapture-0.1.0.dmg` exists and the command exits 0.

- [ ] **Step 5: Verify mounted contents**

Run: `hdiutil verify .build/MeetingAudioCapture-0.1.0.dmg`, attach read-only/nobrowse, verify the app, Applications symlink, `.background/DMGBackground.png`, and `.DS_Store`, then verify the app's strict signature and detach.

- [ ] **Step 6: Commit**

```bash
git add Scripts/create-dmg.sh Makefile
git commit -m "build: add drag-to-Applications DMG"
```

### Task 4: Documentation and Final Verification

**Files:**
- Modify: `README.md`
- Modify: `README.en.md`

- [ ] **Step 1: Document installation and local packaging**

Explain dragging the app from the DMG to Applications, the possible Control-click Open step for the ad-hoc build, `make app`, and `make dmg`. Do not describe the package as notarized.

- [ ] **Step 2: Run complete verification**

Run: `make clean && make test && make app && make dmg`

Run strict code-signature verification for the built app and the app mounted from the final DMG. Run `hdiutil verify` and inspect the mounted contents.

Expected: all tests pass; app, icon, and DMG checks exit 0.

- [ ] **Step 3: Manually inspect the Finder layout**

Open the DMG and confirm the Dual Wave icon is recognizable, the drag arrow aligns with the app and Applications icons, labels are not clipped, and the window opens at the intended size.

- [ ] **Step 4: Commit**

```bash
git add README.md README.en.md
git commit -m "docs: add DMG installation instructions"
```

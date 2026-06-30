# App Icon and Drag-to-Install DMG Design

## Goal

Give MeetingAudioCapture a recognizable macOS application icon and distribute
the locally signed app in a conventional disk image that instructs users to drag
the app into Applications.

## Visual Direction

Use the approved **Dual Wave** direction:

- a dark navy macOS rounded-square base;
- an upper cyan waveform representing system audio;
- a lower blue-violet waveform representing microphone audio;
- a small neutral-gray status dot in the upper-right;
- no red recording symbol, text, microphone silhouette, photographic detail, or
  transparency inside the rounded-square artwork;
- enough padding and contrast to remain legible at 16, 32, and 64 points.

The master artwork is a 1024-by-1024 PNG. Generate the complete macOS iconset at
16, 32, 128, 256, and 512 points with `1x` and `2x` representations, then compile
it into `Config/AppIcon.icns`. Keep the approved 1024 PNG source in
`Design/AppIcon-1024.png` so future contributors can regenerate the iconset.

## Application Bundle Integration

Add `CFBundleIconFile` with value `AppIcon` to `Config/Info.plist`. The `app`
build target creates `Contents/Resources`, copies `Config/AppIcon.icns` there,
and signs only after all executable and resource files are in place.

The icon must appear for the built app in Finder, `/Applications`, Spotlight,
Launchpad, and the standard macOS application chooser. The app remains a
menu-bar-only application and continues to omit a Dock icon while running.

## DMG User Experience

Add a `make dmg` target that first builds the signed app and then creates:

`MeetingAudioCapture-<CFBundleShortVersionString>.dmg`

The mounted volume is named `MeetingAudioCapture`. Its Finder window uses a
660-by-420-point layout with:

- MeetingAudioCapture.app at the left;
- an Applications directory symlink at the right;
- a pale gray-blue background with a clear left-to-right drag arrow;
- icon view, 112-point icons, hidden toolbar, hidden status bar, and no sidebar;
- no license dialog, extra documentation file, installer package, or executable
  setup wizard.

The background asset is stored at `Config/DMGBackground.png` and copied into a
hidden `.background` directory on the disk image. The app and Applications
positions must align with the background artwork.

## Build Architecture

Create `Scripts/create-dmg.sh` using only macOS system tools: `hdiutil`, Finder
AppleScript, `ditto`, and standard shell utilities. Do not add Homebrew,
`create-dmg`, Node, Python, or other packaging dependencies.

The script:

1. reads the version from the built app's Info.plist;
2. creates a clean staging directory;
3. copies the app and creates the Applications symlink;
4. creates and mounts a writable disk image;
5. copies the background and configures the Finder window;
6. detaches the image even when Finder layout configuration fails;
7. converts the writable image to compressed UDZO format;
8. writes the final versioned DMG under `.build`;
9. removes staging and writable-image temporary files.

All temporary packaging files remain under `.build` or the system temporary
directory. Re-running `make dmg` replaces only the same version's generated DMG.

## Signing and Gatekeeper Expectations

Continue to use the existing ad-hoc signature. The DMG is not Developer ID
signed, notarized, or stapled. Documentation must state that users may need to
Control-click the app and choose Open on first launch. This packaging work must
not claim that macOS Gatekeeper warnings have been removed.

## Error Handling

The DMG script exits non-zero if the app bundle, icon, background, mount point,
or required system utility is missing. It must use a cleanup trap to detach any
mounted image and remove staging files. It must never overwrite or modify an app
already installed in `/Applications`.

## Verification

Automated and command-level checks must cover:

- the full Swift test suite;
- `make app` and strict recursive code-signature verification;
- `CFBundleIconFile` resolving to `Contents/Resources/AppIcon.icns`;
- all required icon representations being present in the compiled ICNS;
- shell syntax validation for `Scripts/create-dmg.sh`;
- successful `make dmg` output with the versioned filename;
- `hdiutil verify` on the final disk image;
- read-only mounting of the DMG and confirmation that it contains exactly the
  app, Applications symlink, hidden background assets, and Finder metadata;
- strict signature verification of the app inside the mounted DMG;
- manual Finder inspection of the icon artwork and drag-to-Applications layout.

## Documentation

Update both READMEs with two installation paths:

1. download and open the DMG, then drag the app to Applications;
2. build from source with `make app` or build a local disk image with `make dmg`.

State clearly that the current build is ad-hoc signed and not notarized.

## Out of Scope

- Apple Developer ID enrollment, notarization, or App Store packaging.
- Automatic updates or a package manager formula.
- A PKG installer, privileged helper, or post-install script.
- Changing the menu-bar status indicator artwork.
- Renaming the application, bundle identifier, or GitHub repository.

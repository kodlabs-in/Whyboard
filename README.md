# Whyboard

[![CI](https://github.com/kodlabs-in/Whyboard/actions/workflows/ci.yml/badge.svg)](https://github.com/kodlabs-in/Whyboard/actions/workflows/ci.yml)

Whyboard is a calm, offline-first iPad notebook for Apple Pencil writing, visual thinking, and
structured learning. Notes can use an effectively unlimited sequence of numbered pages or a
zoomable infinite canvas.

## Product direction

The base release is deliberately focused on being an excellent digital notebook:

- Apple Pencil-first drawing powered by PencilKit
- Infinite Pages and Infinite Canvas note types
- Text, images, PDFs, lines, rectangles, ellipses, and circles
- Overlapping object selection, arrangement, duplication, deletion, and Undo/Redo
- Nested folders, search, favorites, recents, and local backup/restore
- Reliable local persistence with no account, analytics, or network dependency
- Bounded page sessions, previews, imports, and history so large notebooks remain responsive
- VoiceOver actions, large-text support, portrait layouts, and dark mode

AI, handwriting recognition, collaboration, cloud sync, and non-iPad platforms are outside the
base release. The data model keeps stable page identities and revisions so those capabilities can
be considered after the notebook foundation is dependable.

## Technology

- Swift 6 and SwiftUI
- PencilKit through a UIKit bridge
- SwiftData for metadata
- PencilKit drawing files for editable ink
- Swift Testing and XCTest
- Apple frameworks only at runtime

The project targets iPadOS 18 and later and supports iPad in portrait and landscape. A privacy
manifest declares the required-reason APIs used by the app; Whyboard does not collect user data.

## Development

Use Xcode 27 or newer. SwiftLint is the only development tool that is not bundled with Xcode:

```sh
brew install swiftlint
```

The project keeps its development commands in one small `Makefile`:

```sh
make format  # Apply the repository's Swift style.
make lint    # Verify swift-format and SwiftLint rules.
make build   # Compile for a generic iOS device without code signing.
make test    # Run all tests on an automatically selected iPad simulator.
make check   # Run the complete lint, build, and test workflow used by CI.
```

The default test command selects an available iPad simulator dynamically, so it works on a clean
Xcode VM or GitHub Actions runner without relying on a developer's device, files, or signing
identity. To run the same suite on a connected physical iPad, pass its identifier explicitly:

```sh
xcrun devicectl list devices
make test DEVICE_ID=<connected-ipad-udid>
```

The reliability suite covers storage rollback, import and backup validation, cancellation,
multi-window save coordination, bounded Undo/Redo history, library scaling, object editing, and
process-relaunch persistence. UI coverage includes real PencilKit ink, overlapping shapes,
page creation and deletion, search selection, portrait, dark mode, and accessibility text sizes.

## Release builds

App Store Connect archives and TestFlight uploads use the `asc` CLI:

```sh
asc auth status --validate
asc xcode version edit --next-build-number --app <app-id> --platform IOS
asc xcode archive --project Whyboard.xcodeproj --scheme Whyboard \
  --configuration Release --archive-path .asc/artifacts/Whyboard.xcarchive
asc xcode export --archive-path .asc/artifacts/Whyboard.xcarchive \
  --ipa-path .asc/artifacts/Whyboard.ipa
asc publish testflight --app <app-id> --ipa .asc/artifacts/Whyboard.ipa --wait
```

Release artifacts are written beneath `.asc/artifacts/` and are ignored by Git.

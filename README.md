# Whyboard

[![CI](https://github.com/kodlabs-in/Whyboard/actions/workflows/ci.yml/badge.svg)](https://github.com/kodlabs-in/Whyboard/actions/workflows/ci.yml)

Whyboard is a calm, offline-first iPad notebook for natural Apple Pencil writing across
organised folders and an effectively unlimited sequence of numbered pages.

## Product direction

The base release is deliberately focused on being an excellent digital notebook:

- Apple Pencil-first drawing powered by PencilKit
- Nested folders and locally stored notes
- Independent, stable pages in one continuous vertical document
- Reliable, atomic autosave with no account or network dependency
- Lazy page activation so long notebooks remain responsive

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

The project targets iPadOS 18 and later and supports iPad in portrait and landscape.

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

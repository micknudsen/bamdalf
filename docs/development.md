# Native development

## Prerequisites

Use an Apple Silicon Mac running macOS 15 or newer, with Xcode 16.4 or newer
and its macOS SDK. Open Xcode once and complete its license agreement and
component installation. These setup steps require the developer's acceptance;
a successful `xcodebuild -version` alone does not prove setup is complete.

Select the installed Xcode for the current shell without changing the system
selection:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
swift --version
```

CI uses the Apple Silicon `macos-15` runner and explicitly selects
`/Applications/Xcode_16.4.app/Contents/Developer` (Swift 6.1). The runner and
installed Xcode version are described in GitHub's
[runner documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)
and [macOS 15 image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md).

## Build, test, and launch

From a fresh checkout:

```sh
swift build
swift test --disable-xctest
bash scripts/build-app.sh
open .build/Bamdalf.app
```

The script builds the release executable, packages its native application bundle,
and applies an ad hoc signature for local use. No paid Apple developer account
is needed. This is a development app, not a notarized distribution.

The launch window contains a full-width workspace with the message
**No BAM file open**. It has no permanent file sidebar or Open BAM toolbar
button. BAM opening and alignment display belong to subsequent implementation
tickets; this increment displays no simulated alignments. Close the window or
use **Bamdalf → Quit Bamdalf** / **Command-Q** to quit.

For a focused check while developing:

```sh
swift test --disable-xctest --filter LaunchTests
```

Run the documentation checks in [CONTRIBUTING.md](../CONTRIBUTING.md) as well.

## Implementation and test boundary

Swift 6, AppKit, and Swift Package Manager supply the native application, window,
build, and tests. This bootstrap has no third-party runtime dependencies.
AppKit gives subsequent viewer increments native dialogs and direct drawing
without introducing an unused UI layer. Select and pin the BAM reader dependency
when the file-opening increment actually needs it.

`ViewerSession` owns the application-facing presentation consumed by the real
native workspace. Swift Testing checks that seam and the actual AppKit window.
Native checks inspect the visible message and workspace sizing; they do not
claim BAM decoding, alignment rendering, or performance coverage.

The `Native macOS` CI job builds, runs the tests, and packages the application.
`Required checks` depends on both native and documentation jobs and accepts
only successful results. All three jobs must be required by branch protection
before this bootstrap can merge.

## Native demonstration

On 2026-11-07, the packaged release app was launched on Apple Silicon macOS
27.2, built with Xcode 27.2 / Swift 6.4.2. The native accessibility tree exposed
the Bamdalf window, its message, standard window controls, and Bamdalf/File/Window
menus. **Command-Q** terminated the app. Both automated session/window tests
passed locally, including workspace resizing. CI independently exercises Xcode
16.4 / Swift 6.1.2 on macOS 15.

![Native Bamdalf workspace with no BAM file open](images/native-workspace.png)

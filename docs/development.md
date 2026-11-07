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
bash scripts/build-htslib.sh
swift build
swift test --disable-xctest
bash scripts/build-app.sh
open .build/Bamdalf.app
```

The script builds the release executable, packages its native application bundle,
and applies an ad hoc signature for local use. No paid Apple developer account
is needed. This is a development app, not a notarized distribution.

The launch window contains a full-width workspace with **No BAM file open**.
Use **File → Open BAM…** / **Command-O** to select a local BAM. The app discovers
`sample.bam.bai`, `sample.bai`, `sample.bam.csi`, and `sample.csi` beside
`sample.bam`. One candidate opens automatically; multiple candidates require an
explicit choice. Canceling or failing a replacement preserves the open session.
An index failure identifies the selected file without trying another index.

A successful open shows **Enter a genomic interval** and focuses the field.
This increment opens the BAM/header/index; it does not yet navigate or query/draw
regional alignments. There is no permanent file sidebar or Open BAM toolbar
button. Close the window or use **Bamdalf → Quit Bamdalf** / **Command-Q** to quit.

For a focused check while developing:

```sh
swift test --disable-xctest --filter LaunchTests
```

Run the documentation checks in [CONTRIBUTING.md](../CONTRIBUTING.md) as well.

## Implementation and test boundary

Swift 6, AppKit, and Swift Package Manager supply the native application, window,
build, and tests. A narrow C adapter uses source-built **HTSlib 1.25** behind an
actor that owns the BAM, header, and selected index. This is an internal app
boundary, not a public SDK. Header/index loading runs off the main thread, and
obsolete open attempts cannot replace a newer session or show stale errors.

`scripts/build-htslib.sh` downloads the official
[HTSlib 1.25 release](https://github.com/samtools/htslib/releases/tag/1.25), verifies
its pinned SHA-256, and builds a static library for macOS 15 or newer. The first
build needs network access; subsequent builds reuse the verified archive and
toolchain-specific build. Optional networking, plugins, libdeflate, bzip2, and
LZMA are disabled for this local-BAM scope. The app links system zlib and copies
the upstream HTSlib/HTScodecs licenses into its bundle. It needs no Homebrew
libraries or runtime samtools executable. Run the dependency script again after
cleaning `.build` or changing Xcode. CI runs the same script before Swift builds.

`ViewerSession` owns the application-facing presentation consumed by the real
native workspace. Swift Testing checks that seam and the actual AppKit window.
Native checks inspect the visible message, workspace sizing, BAM chooser
configuration, and field focus after real opening. Integration checks use the
production reader and small real BAI/CSI files through the session. Controlled
completion tests deliver older results after newer opens without timing sleeps.
These checks do not claim regional alignment rendering or WGS performance.

The readable source fixture is
[`opening.sam`](../Tests/BamdalfKitTests/Fixtures/opening.sam). Its references are
`tiny` (2,000 bases) and `other_reference` (800 bases), with 10-base and 6-base
alignments at positions 101 and 201 respectively. Regenerate the committed BAM,
BAI, and CSI from that source using:

```sh
bash scripts/generate-fixtures.sh
```

Opening validates format/header and loads the explicitly selected index. It
does not scan all alignments, verify complete sorting, or guarantee detection of
every stale/mismatched index. No reference FASTA is required.

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

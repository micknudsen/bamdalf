# Releases

Releases support Apple Silicon Macs running macOS 15 or newer. They use the
existing ad hoc signing setup, with no Apple Developer Program credentials
required in CI. Signature details remain available in the build provenance.

The reusable process is: prepare a version through a PR, push its version tag,
then review and publish the automatically prepared GitHub draft. A tag push
triggers CI verification, release tests, ZIP packaging, asset upload, and draft
creation. The workflow never publishes a release or creates a tag.

For a native Mac app, the downloadable ZIP is the distribution artifact. The
draft stages that ZIP and its companion files while you write the public release
notes. Publishing the draft exposes those same assets without rebuilding them.

## Ask the release assistant

In this repository, say **Make release vX.Y.Z**, using a concrete version, for
example **Make release v1.2.3**. The repository's
[bamdalf-release skill](../.agents/skills/bamdalf-release/SKILL.md) handles the
process in two phases:

1. Propose release notes based on the changes since the previous release. Review
   the notes and suggest changes until you are satisfied. The assistant waits
   for your explicit agreement before changing versions, creating a PR, or
   creating/pushing a release tag.
2. Once you approve the notes, the assistant prepares any needed version/build
   update through a PR, waits for the required checks, squash-merges, pushes the
   tag, and monitors the release workflow. After verifying the draft assets, it
   applies the agreed notes and **publishes a normal GitHub release**. Your notes
   approval authorizes these remaining steps; a separate publish confirmation
   is unnecessary.

The assistant uses prerelease status only when you explicitly request it. It
ensures the draft has the requested release status before publishing. Release
notes and summaries follow the content rules in the skill.

Proposed notes and their source revision are kept in `.local/releases/` so an
interrupted conversation can resume. Material changes to the release contents
or agreed notes require renewed agreement. A question about releasing or a
request to edit this process does not start a release.

The tag workflow still creates a draft. When using the manual instructions
below, review and publish that draft yourself; the assistant completes those
steps only after you approve its proposed release notes.

## Version metadata

[Resources/Info.plist](../Resources/Info.plist) is the version source:

- `CFBundleShortVersionString`: `MAJOR.MINOR.PATCH`; `0.0.0` denotes the unreleased development build.
- `CFBundleVersion`: a positive integer build number, initially `1`; increment
  for each new release candidate that changes the shipped app.
- `LSMinimumSystemVersion`: minimum supported macOS, currently `15.0`.

The distribution examples below use `v1.2.3` as an illustrative version. Choose
the intended release version and update the plist before using them. Git tags
must match the plist version; the scripts reject mismatches, leading zeroes,
and tag suffixes. Releases use normal GitHub release status by default. Keep
the deployment target in `Package.swift`, HTSlib build flags, and the plist aligned when changing
the supported OS.

## Prepare a version

1. Make the version/build change in a branch and PR. The development version is
   `0.0.0` / `1`; select the intended release version before preparing a release.
   Summarize the features, limitations, and any remaining MVP
   work for the eventual release notes. Run the documentation and native checks
   described in [development](development.md) and [contributing](../CONTRIBUTING.md).
2. Merge only after all required CI checks pass and merge is authorized. Release
   workflow setup also follows this PR process. The workflow must be included
   in the commit being tagged.
3. Optionally rehearse packaging locally using the commands below. Normal PR CI
   also tests version validation and ZIP packaging without uploading a release.

For a local rehearsal, select Xcode as in the development instructions:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
python3 -m unittest discover -s scripts/tests
bash scripts/test.sh --configuration release
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
bash scripts/package-release.sh "v$version"
```

This only writes `.build/` products. It neither creates a tag nor contacts the
GitHub release API; building HTSlib may download its pinned source archive.
`BUILD-INFO.txt` marks uncommitted source changes as a dirty development build.
Use the clean Actions build for distribution.

## Push a tag to prepare the release

These are future release steps, not setup commands. Perform them only when
ready to create the release tag.

1. Confirm a clean checkout, fetch remote master/tags, and select the exact
   merged revision to release. Do not move or reuse an existing release tag.
2. Create and push an annotated tag for that revision. For example:

   ```sh
   git fetch origin master --tags
   git log -1 origin/master
   git tag -a v1.2.3 origin/master -m "bamdalf v1.2.3"
   git push origin refs/tags/v1.2.3
   ```

3. The tag push automatically starts **Prepare release**. There is no
   separate Actions dispatch. It validates the tag/version match, requires the
   commit to belong to `master`, and waits for successful **master push CI on
   that exact commit**. A green PR run alone is insufficient. It allows up to
   one minute for the push CI run to appear; a missing or failed run stops release
   preparation. An older merged commit is valid even if master has advanced.
4. After CI succeeds, the workflow runs native release tests, packages and
   verifies the ZIP, uploads an Actions artifact, then creates a **draft
   release** with the app ZIP and `SHA256SUMS`. The ZIP includes `BUILD-INFO.txt`
   and `release-metadata.json` beside the app. Only the draft job has repository
   write permission.
5. When the workflow succeeds, open **Releases** on GitHub and edit the draft.
   Replace the editing reminder with a useful feature summary and limitations;
   review the generated changelog. The draft includes the source commit and a
   link to the workflow run. Keep the Apple Silicon/macOS requirements prominent.
6. Download and smoke-test the actual draft assets, then publish when satisfied.
   Leave **Set as a prerelease** disabled for a normal release. Publishing is a
   separate human action; this workflow has no automatic publication step.

If a run fails, fix the cause and use GitHub's **Re-run failed jobs** on the
original tag run. No tag movement or separate manual dispatch is needed. A
failed or canceled master CI run must be rerun successfully first. The prepare
job has a 35-minute limit including the wait for CI; it can be rerun if CI takes
longer.

The workflow refuses an existing release instead of replacing its assets. If
draft creation partially fails, inspect the draft and run before retrying; a
maintainer may remove an incomplete unpublished draft after confirming nobody
needs it. Published releases and tags should remain unchanged. Fix a shipped
problem with a new version and build number. A workflow/script fix requires a new
merged commit and a new version tag because reruns use the original tagged code.

## Verify the downloaded app

Download the app ZIP and `SHA256SUMS` to the same directory. In Terminal:

```sh
shasum -a 256 --check SHA256SUMS
ditto -x -k bamdalf-v1.2.3-macos-arm64.zip extracted
codesign --verify --strict extracted/bamdalf.app
```

Checksums check file integrity; the ad hoc signature does not authenticate the
publisher. The ZIP includes `BUILD-INFO.txt` and `release-metadata.json` beside
the app. `BUILD-INFO.txt` records the source commit, source cleanliness,
toolchain, OS, and signing status. The ZIP contains the app and licenses for
bamdalf, HTSlib, and HTScodecs. Packaging rejects dynamic dependencies outside
Apple's system library locations, so users need neither conda nor Homebrew.

Move `bamdalf.app` into Applications. Test from the downloaded archive on a
supported Mac, preferably one without the development tools or local HTSlib:

- Confirm the displayed app version in Finder's **Get Info**.
- Launch, open a small local BAM with its index, and navigate to a known region.
- Pan, zoom, and scroll; confirm a wide view asks you to zoom in.
- Try a missing index and an invalid interval, then confirm recovery.
- Close and relaunch the app.

Expect Gatekeeper to potentially block this app. For software you have
reviewed and trust, Apple documents the **System Settings → Privacy & Security →
Open Anyway** exception after an attempted launch. Managed Macs may prohibit
exceptions; those users need a future signed/notarized build. Do not disable
Gatekeeper globally. See [Apple's opening-app guidance](https://support.apple.com/en-us/102445).

Local launch and ad hoc signature validation do not prove a downloaded app will
pass Gatekeeper. A fresh download test is a release check, separate from CI.

## Implementation references

- [GitHub tag push workflow triggers](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#push)
- [GitHub CLI waiting for CI](https://cli.github.com/manual/gh_run_watch)
- [GitHub CLI release creation, draft, and tag verification](https://cli.github.com/manual/gh_release_create)
- [Apple notarization workflow for a future signed distribution](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

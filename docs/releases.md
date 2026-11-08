# Preview releases

The initial distribution is an **unnotarized preview** for Apple Silicon Macs
running macOS 15 or newer. It has an ad hoc signature, with no Developer ID
signature or Apple notarization. It needs no Apple account secrets in CI.
This is the distribution choice made on 2026-11-08; signed and notarized releases
remain future work.

The reusable process is: prepare a version through a PR, push its version tag,
then review and publish the automatically prepared GitHub draft. A tag push
triggers CI verification, release tests, ZIP packaging, asset upload, and draft
creation. The workflow never publishes a release or creates a tag.

For a native Mac app, the downloadable ZIP is the distribution artifact. The
draft stages that ZIP and its companion files while you write the public release
notes. Publishing the draft exposes those same assets without rebuilding them.

## Version metadata

[Resources/Info.plist](../Resources/Info.plist) is the version source:

- `CFBundleShortVersionString`: `MAJOR.MINOR.PATCH`, initially `0.1.0`.
- `CFBundleVersion`: a positive integer build number, initially `1`; increment
  for each new release candidate that changes the shipped app.
- `LSMinimumSystemVersion`: minimum supported macOS, currently `15.0`.

Use matching Git tags such as `v0.1.0`. The scripts reject a different version,
leading zeroes, and tag suffixes. GitHub's **prerelease** flag labels these early
previews even though the tag uses the simple `v0.1.0` form. Keep the deployment
target in `Package.swift`, HTSlib build flags, and the plist aligned when changing
the supported OS.

## Prepare a version

1. Make the version/build change in a branch and PR. The initial version already
   says `0.1.0` / `1`. Summarize the features, limitations, and any remaining MVP
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
bash scripts/package-release.sh v0.1.0
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
   git tag -a v0.1.0 origin/master -m "Bamdalf v0.1.0"
   git push origin refs/tags/v0.1.0
   ```

3. The tag push automatically starts **Prepare preview release**. There is no
   separate Actions dispatch. It validates the tag/version match, requires the
   commit to belong to `master`, and waits for successful **master push CI on
   that exact commit**. A green PR run alone is insufficient. It allows up to
   one minute for the push CI run to appear; a missing or failed run stops release
   preparation. An older merged commit is valid even if master has advanced.
4. After CI succeeds, the workflow runs native release tests, packages and
   verifies the ZIP, uploads an Actions artifact, then creates a **draft
   prerelease** with the app ZIP, `SHA256SUMS`, `BUILD-INFO.txt`, and
   `release-metadata.json`. Only the draft job has repository write permission.
5. When the workflow succeeds, open **Releases** on GitHub and edit the draft.
   Replace the editing reminder with a useful feature summary and limitations;
   review the generated changelog. The draft includes the source commit and a
   link to the workflow run. Keep the unnotarized/Apple Silicon/macOS requirements
   prominent.
6. Download and smoke-test the actual draft assets, then publish when satisfied.
   Keep **Set as a prerelease** enabled for the initial preview. Publishing is a
   separate human action; this workflow has no automatic publication step.

If a run fails, fix the cause and use GitHub's **Re-run failed jobs** on the
original tag run. No tag movement or separate manual dispatch is needed. A
failed or canceled master CI run must be rerun successfully first. The prepare
job has a 35-minute limit including the wait for CI; it can be rerun if CI takes
longer.

The workflow refuses an existing release instead of replacing its assets. If
draft creation partially fails, inspect the draft and run before retrying; a
maintainer may remove an incomplete unpublished draft after confirming nobody
needs it. Actions artifacts are retained for 14 days; the draft's attached assets
are separate. Published releases and tags should remain unchanged. Fix a shipped
problem with a new version and build number. A workflow/script fix requires a new
merged commit and a new version tag because reruns use the original tagged code.

## Verify the downloaded app

Download all four assets to the same directory. In Terminal:

```sh
shasum -a 256 --check SHA256SUMS
ditto -x -k Bamdalf-v0.1.0-macos-arm64-unnotarized.zip preview
codesign --verify --strict preview/Bamdalf.app
```

Checksums check file integrity; the ad hoc signature does not authenticate the
publisher. `BUILD-INFO.txt` records the source commit, source cleanliness,
toolchain, OS, and signing status. The ZIP contains the app and licenses for
Bamdalf, HTSlib, and HTScodecs. Packaging rejects dynamic dependencies outside
Apple's system library locations, so users need neither conda nor Homebrew.

Move `Bamdalf.app` into Applications. Test from the downloaded archive on a
supported Mac, preferably one without the development tools or local HTSlib:

- Confirm the displayed app version in Finder's **Get Info**.
- Launch, open a small local BAM with its index, and navigate to a known region.
- Pan, zoom, and scroll; confirm a wide view asks you to zoom in.
- Try a missing index and an invalid interval, then confirm recovery.
- Close and relaunch the app.

Expect Gatekeeper to potentially block this preview. For software you have
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

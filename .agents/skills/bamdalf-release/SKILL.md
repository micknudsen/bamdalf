---
name: bamdalf-release
description: 'Make a bamdalf release when the user says "Make release vX.Y.Z": propose release notes, wait for agreement, then deliver the version through CI and publish the GitHub release. Release questions and workflow edits do not authorize a release.'
---

# bamdalf release

Read the repository's [release guide](../../../docs/releases.md),
[contribution rules](../../../CONTRIBUTING.md), and
[release workflow](../../../.github/workflows/release.yml). Follow the actual
repository configuration rather than assuming a toolchain, check list, or
version from an earlier conversation.

## Release status

Publish a normal GitHub release by default. Use prerelease status only when the
user explicitly requests a beta, release candidate, or prerelease. The tag
workflow creates a draft of a normal release.

Keep release notes and user-facing release summaries focused on features,
requirements, and product limitations. Omit routine signing, notarization, and
Gatekeeper disclosures, including those in workflow-generated draft text.
Keep signature and provenance verification in the delivery checks; discuss
signing details only when the user explicitly asks or a verification failure
blocks delivery.

## Propose notes first

A concrete release request starts with release notes. A question, hypothetical
example, or request to change the release process is documentation work only.
If the requested version is missing or is literally `vX.Y.Z`, ask for it.

1. Inspect the working tree, fetch remote master/tags, and inspect existing
   releases. Use only committed, merged work as the proposed release scope.
   Preserve unrelated local edits; use an isolated checkout when necessary.
2. Validate the requested version as canonical `vMAJOR.MINOR.PATCH`. Identify
   its candidate master commit and the previous published release. For a first
   release, describe the implemented app rather than an imagined feature set.
   If that version is already published, report its URL instead of rebuilding
   or replacing it.
3. Propose concise, user-facing release notes covering delivered features,
   relevant fixes, requirements, and known product limitations. Distinguish
   measured/tested behavior from unverified claims. Record the candidate commit
   and comparison base.
4. Save the notes and their source revision under `.local/releases/VERSION/`,
   with approval status **pending**. Show the proposed notes and ask for edits
   or explicit agreement. End the turn at this point.

During this phase, leave version files, PRs, tags, and GitHub releases unchanged.
Incorporate requested edits, show the revised notes, and continue waiting for
agreement. An edit request or elapsed time is not approval. This phase has no
automatic timeout or fallback approval.

## Deliver after agreement

The user's explicit agreement to the proposed notes authorizes the remaining
release steps, including the version PR, its merge after passing checks, tag
push, and GitHub publication. Record which notes and source revision were
approved, including the user's approval message. Resume from this record only
when it establishes actual agreement; a saved draft alone does not.

1. Recheck remote state against the approved source. If release contents or
   substantive notes change, present the revised notes for agreement before
   continuing. Routine version/build metadata changes are part of delivery.
2. If merged master already has the requested version and the tag is unused,
   retain its build number and skip a metadata-only PR. Otherwise prepare a
   focused version/build PR: set `CFBundleShortVersionString` to the requested
   version and increment the existing integer `CFBundleVersion` once. Resume an
   existing matching preparation PR without incrementing again. Keep versions
   increasing and validate with `scripts/release_metadata.py`.
3. Run the relevant local checks and open the PR when needed. Use
   `micknudsen@gmail.com` for both Git author and committer and verify both.
   Inspect the effective branch protection; wait for every configured check to
   succeed on the current, up-to-date PR head. Squash-merge using that exact
   head SHA and record the resulting master commit. A metadata-free release
   uses the agreed existing master commit.
4. Wait for successful master push CI on that exact release commit. Create an
   annotated tag for the requested version at the recorded commit and push
   only that tag. Use an authenticated user Git push so the tag workflow runs.
   An existing tag can be reused only as a resume point after verifying its
   peeled commit; preserve existing tags rather than moving or force-pushing.
5. Monitor the tag's release workflow for that exact commit through completion.
   The workflow builds/tests/packages and creates an unpublished draft. Inspect
   failures and repair only within the approved release scope. Rerun a transient
   failed job at most once for the same cause; report a repeated blocker. A fix
   requiring different tagged code needs a new version agreed with the user.
6. Verify the draft belongs to the requested tag and source. Download its app ZIP
   and `SHA256SUMS`; verify the ZIP checksum, then extract it. Check the app
   version/build metadata, `BUILD-INFO.txt` and `release-metadata.json` beside
   the app, and bundled licenses. On macOS, verify the extracted app's signature. Report
   any fresh-download/GUI checks that remain unexecuted; these are separate from
   native CI evidence.
7. Apply the approved notes to the draft, retaining source and build links.
   Verify the saved notes match the agreement. Explicitly clear the draft
   release's prerelease flag before publishing a normal release; retain that
   flag only for an explicitly requested prerelease. Complete publication
   without asking for another confirmation. Automatic latest-release promotion
   remains disabled.
8. Verify the release is published with the agreed release status (normal by
   default), expected tag, notes, and all assets.
   Synchronize a clean local master when that preserves the user's work. Report
   the release URL, source commit, CI result, and any material verification limit.

An existing draft is a resume point only after its source, assets, and approval
record are verified. Preserve already published releases. If approval, source,
or asset provenance cannot be established, report the specific missing evidence
instead of publishing. Creating this skill is not itself a release request.

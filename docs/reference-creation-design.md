# Reference creation window design

Product design confirmed by the user on 2026-11-21. This record defines the
accepted creation-window behavior. Contracts in
[reference-milestone.md](reference-milestone.md) and
[reference-spec.md](reference-spec.md) remain the baseline except where the
accepted decisions below supersede them.

Implementation and qualification were delivered on 2026-11-21 through
[PR #75](https://github.com/micknudsen/bamdalf/pull/75),
[PR #76](https://github.com/micknudsen/bamdalf/pull/76),
[PR #77](https://github.com/micknudsen/bamdalf/pull/77), and
[PR #78](https://github.com/micknudsen/bamdalf/pull/78), culminating in commit
`508c02c10338afb0ede556223ef653f49176d480`. The
[acceptance record](reference-creation-acceptance.md) maps these decisions to
verified behavior and evidence boundaries; the baseline below records the
earlier implementation that motivated this design.

## Agreed workflow

- **Create Reference…** opens or brings forward the single creation window.
- Enter a bundle name and a FASTA path, with **Browse…** available. The FASTA
  filename supplies an editable name suggestion. Additional input types such
  as GENCODE GTF will receive rows when their import support is implemented.
- **Create bundle** validates the form, then opens a native Save dialog to
  choose the output file. The stored bundle name suggests the output filename.
- Generate with progress and **Cancel** in the creation window while browsing
  remains available. Only one generation operation runs at a time.
- Successful creation closes the window quietly and leaves the saved bundle
  unopened. Cancellation or errors return to the populated form, except an
  explicit cancellation requested as part of closing or quitting.

The decisions below define naming, validation, recovery, and window lifetime.
This work does not add GTF import support.

## Accepted decisions

### C1: Stored bundle name

Accepted 2026-11-21. Store the user-chosen bundle name inside the reference
bundle and use it as the displayed reference name. It also supplies the initial
suggested output filename. The user can choose another filename in the Save
panel; renaming the file later leaves the bundle name unchanged.

This supersedes R30's filename-derived display-name rule.
The `.bref` suffix remains unchanged. C7 defines name defaults;
C9 defines form validation.

### C2: Earlier bundles may become obsolete

Accepted 2026-11-21. Apply the repository's
[pre-1.0 compatibility policy](../CONTRIBUTING.md#pre-10-compatibility-policy).
The stored bundle name is required by the new design. Old bundles lacking it
may be rejected and regenerated; the proposed filename fallback for older
bundles is explicitly not selected. The bundle format version is separate from
the application's first stable v1.0.0 release.

### C3: Browsing during generation

Accepted 2026-11-21. Allow users to continue browsing while the dedicated
creation window generates a bundle. Show progress and **Cancel** in that
window, with generation work performed off the UI thread.

This supersedes R32's modal progress and browsing pause. R11 remains in effect:
successful generation saves the bundle without opening or selecting it.
C5 defines closing during generation; C6 defines successful completion.

### C4: One creation window and operation

Accepted 2026-11-21. Allow one creation window and one generation operation at
a time. Invoking **Create Reference…** while the window exists brings it
forward, preserving its entered values or running operation.

### C5: Closing during generation

Accepted 2026-11-21. Closing the creation window during generation asks the
user to choose **Keep Creating** or **Cancel and Close**. **Keep Creating**
leaves the window and operation running. **Cancel and Close** cancels generation
and completes cleanup of incomplete output before closing the window. Any
existing destination file remains intact, following the safe-save contract.

### C6: Close after successful creation

Accepted 2026-11-21. Close the creation window once the completed bundle has
been saved successfully. Creating another bundle immediately afterward is
uncommon, so keeping the form open for repeated creation is not the intended
workflow. The proposed persistent success view with retained inputs and
**Show in Finder** was rejected.

R11 remains in effect: save without automatically opening or selecting the
bundle. C10 defines failure and cancellation behavior.

### C7: Suggested bundle name

Accepted 2026-11-21. Selecting a FASTA suggests its filename without the
extension as the bundle name, for example `GRCh38.fa` becomes `GRCh38`.
The name field remains editable. Changing the FASTA updates this suggestion
only until the user edits the name; afterward, preserve their chosen value.

### C8: Initial input form

Accepted 2026-11-21. The initial form contains **Bundle name** and **FASTA**.
The FASTA row provides an editable path and a **Browse…** button. Add further
input rows, such as GENCODE GTF, when their import support is implemented.
This increment provides FASTA input only.

### C9: Validate the form before choosing the destination

Accepted 2026-11-21. Before opening the Save dialog, require a nonblank bundle
name after trimming surrounding whitespace and a readable local FASTA file.
Show errors beside the relevant field. Validate FASTA contents during
generation, avoiding an additional full-file scan before the Save dialog.

### C10: Return to the form after cancellation or failure

Accepted 2026-11-21. Canceling the Save dialog, pressing **Cancel** during
generation, or a generation failure returns to the editable form with the
entered values retained. Finish generation cleanup before allowing another
attempt. Show any error in the creation window; cancellation is not an error.
C5's explicit **Cancel and Close** still closes the window after cleanup.

### C11: Discard inputs when an idle window closes

Accepted 2026-11-21. Closing the creation window when no generation is running
discards its inputs without a confirmation dialog. Reopening starts with an
empty form. Do not persist creation drafts between window lifetimes or app
launches. C4 and C10 continue to preserve inputs while the window stays open.

### C12: Generation lifetime is independent of the viewer

Accepted 2026-11-21. Closing the viewer leaves the creation window and its
running generation active. Quitting bamdalf during generation asks the user
to choose **Keep Creating** or **Cancel and Quit**. **Keep Creating** abandons
the quit request; **Cancel and Quit** cancels generation and waits for cleanup
before terminating the app.

### C13: Quiet successful completion

Accepted 2026-11-21. Successful creation closes the window without a separate
success dialog or system notification. The destination has already been chosen;
failures keep the form open with an error under C10.

## Existing guarantees to preserve

The existing source-validation and safe-save contracts remain in effect:
complete and validate the bundle before publishing it, preserve an existing
destination on failure or cancellation, and prevent replacement of an open
reference, including aliases. Continued browsing means these guarantees must
also hold if the selected reference changes while generation is running.

The [engineering specification](reference-creation-spec.md) accounts for cancellation racing with final
publication, window closing or quitting during cleanup, and conversion of a
display name into a valid suggested filename. These are implementation details
within the accepted behavior, not additional product features.

## Historical implementation baseline

Before this increment, at commit `054775128dd679f98d8824becca94242d5c56ee8`
(v0.2.1), the verified baseline was:

- R30 derived the displayed reference name from the output filename, omitting
  `.bref`.
- R11 saved a completed bundle without opening or selecting it; this guarantee
  remains in effect.
- R32 used modal progress with cancellation and paused browsing during creation.
- The v1 metadata stored the source filename, creator, creation time,
  and chunk size; it had no independent user-chosen bundle name
  (`Sources/BamdalfKit/ReferenceFormat.swift`).

## Confirmation status

The user confirmed the complete consolidated design on 2026-11-21 after
accepting C1–C13. Engineering specification, issue publication, implementation,
and qualification followed as separately authorized stages; the dated records
below and the acceptance record above preserve that sequence.

The [engineering specification](reference-creation-spec.md) was prepared
on 2026-11-21 through to-spec. The user confirmed its testing interfaces on
2026-11-21, completing the required review before issue-tracker publication.
After explicit approval of the exact issue body and destination, it was
published as [issue #70](https://github.com/micknudsen/bamdalf/issues/70) with
`ready-for-agent`; the published body and label were verified.

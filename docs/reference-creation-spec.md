# Reference creation window specification

Prepared 2026-11-21 from the confirmed
[creation-window design](reference-creation-design.md). The user confirmed the
testing interfaces and exact issue publication on 2026-11-21. Published as
[GitHub issue #70](https://github.com/micknudsen/bamdalf/issues/70) with the
`ready-for-agent` label. The published body and label were verified by readback.

Implementation tickets were published on 2026-11-21 as native sub-issues of #70:
[#71](https://github.com/micknudsen/bamdalf/issues/71) →
[#72](https://github.com/micknudsen/bamdalf/issues/72) →
[#73](https://github.com/micknudsen/bamdalf/issues/73) →
[#74](https://github.com/micknudsen/bamdalf/issues/74).
At publication, each ticket was blocked by its predecessor. Bodies, labels,
and native relationships were verified; the parent specification was not edited.

All four tickets were delivered and closed on 2026-11-21 through
[PR #75](https://github.com/micknudsen/bamdalf/pull/75),
[PR #76](https://github.com/micknudsen/bamdalf/pull/76),
[PR #77](https://github.com/micknudsen/bamdalf/pull/77), and
[PR #78](https://github.com/micknudsen/bamdalf/pull/78), culminating in commit
`508c02c10338afb0ede556223ef653f49176d480`. The
[acceptance record](reference-creation-acceptance.md) maps all 39 stories and
C1–C13 to implementation and qualification evidence. The parent issue's text
and state were left unchanged. The requirements below retain their confirmed
wording; the problem statement describes the pre-increment baseline.

## Problem Statement

Before this increment, creating a reference led directly through a FASTA chooser, an
output chooser, and a progress sheet attached to the viewer. Users had no
single place to review the inputs or choose a meaningful bundle name before
starting. This flow also paused browsing and had no suitable form for future
inputs such as annotations.

The displayed reference name followed the filename. Users needed a
lasting bundle name that survives moving or renaming the file, while retaining
the ability to choose its storage location independently.

## Solution

Provide one dedicated reference creation window, initially containing
**Bundle name** and **FASTA**. Offer both an editable FASTA path and
**Browse…**. Suggest the FASTA basename as the bundle name until the user edits
it. **Create bundle** validates the form and then opens the native Save dialog.

Generate one self-contained `.bref` at a time, showing progress and **Cancel**
in the creation window while browsing remains available. Store the name in
the bundle and display it when the reference is opened. Successful creation
quietly closes the window without opening or selecting the result.

Cancellation or errors retain the populated form for correction and retry.
Explicit close and quit requests during generation offer cancellation with
cleanup. Additional input rows can be added when those import features exist;
this increment supports FASTA only.

## User Stories

1. As a user, I want **Create Reference…** to open a dedicated form, so that I
   can review my inputs before generating a bundle.
2. As a user, I want to create a reference without first opening a BAM, so that
   preparation is independent of alignment viewing.
3. As a user, I want repeated **Create Reference…** commands to bring the
   existing window forward, so that my inputs and running operation are preserved.
4. As a user, I want one creation operation at a time, so that progress is easy
   to find and accidental duplicate jobs do not compete for resources.
5. As a user, I want to type or paste a FASTA path, so that I can use a location
   I already know.
6. As a user, I want a **Browse…** button with a native file chooser, so that I
   can locate a FASTA without typing its path.
7. As a user, I want the form to show supported inputs, so that it does not
   imply that GTF import is already available.
8. As a user, I want a bundle name suggested from the FASTA filename without
   its extension, so that ordinary creation needs less typing.
9. As a user, I want to edit that suggested name, so that I can describe the
   reference in terms meaningful to me.
10. As a user, I want changing the FASTA to update an untouched name suggestion,
    so that the default follows my selected input.
11. As a user, I want changing the FASTA to preserve a name I have edited, so
    that input changes do not overwrite my deliberate choice.
12. As a user, I want the name stored inside the bundle, so that moving or
    renaming the file does not change its displayed name.
13. As a user, I want the viewer to show the stored bundle name, so that I can
    identify the reference independently of its filename.
14. As a user, I want blank names rejected after surrounding whitespace is
    trimmed, so that a created reference always has a meaningful display name.
15. As a user, I want missing or unreadable input files identified beside the
    FASTA field, so that I can fix the problem before choosing an output.
16. As a user, I want FASTA contents checked during generation, so that I do
    not wait through a duplicate full-file scan before saving.
17. As a user, I want **Create bundle** to open the native Save dialog after
    form validation, so that I control the output location and filename.
18. As a user, I want the bundle name to suggest the output filename, so that
    the initial save choice is useful while remaining editable.
19. As a user, I want the output to use the `.bref` suffix, so that the bundle
    remains recognizable as a bamdalf reference.
20. As a user, I want standard replacement confirmation for an existing output,
    so that overwriting a file is deliberate.
21. As a user, I want canceling the Save dialog to retain my inputs, so that I
    can reconsider the destination without rebuilding the form.
22. As a user, I want progress and cancellation in the creation window, so that
    generation remains understandable and controllable.
23. As a user, I want to browse while generation runs, so that preparation does
    not interrupt work in the viewer.
24. As a user, I want creation to leave my selected sources and navigation
    alone, so that its completion cannot undo browsing performed meanwhile.
25. As a user, I want **Cancel** to clean up and return to the populated form,
    so that I can revise inputs or retry without losing my work.
26. As a user, I want generation errors shown in the creation window with my
    inputs retained, so that I can understand and correct the failure.
27. As a user, I want existing output bytes preserved on failure or cancellation,
    so that an unsuccessful replacement does not destroy a usable file.
28. As a user, I want no incomplete new bundle left after failure or cancellation,
    so that an unfinished file cannot be mistaken for a completed reference.
29. As a user, I want my open reference protected even if I open it after
    generation starts, so that background creation cannot replace data in use.
30. As a user, I want successful generation to close the creation window, so
    that an infrequent preparation task finishes without leaving an unused form.
31. As a user, I want success to require no extra dialog or notification, so
    that completed preparation does not create another interruption.
32. As a user, I want a completed bundle saved without automatically opening
    it, so that preparing another reference leaves my current selection intact.
33. As a user, I want closing a running creation window to offer **Keep Creating**
    or **Cancel and Close**, so that I choose whether to abandon the operation.
34. As a user, I want closing an idle creation window to discard its inputs
    without confirmation, so that closing an unused form is straightforward.
35. As a user, I want reopening a closed creation window to start empty, so that
    old inputs are not silently reused for a new task.
36. As a user, I want closing the viewer to leave generation running, so that
    the two windows have independent lifetimes.
37. As a user, I want quitting during generation to offer **Keep Creating** or
    **Cancel and Quit**, so that cleanup completes before the app exits.
38. As a user, I want a saved bundle usable without its source FASTA, so that
    the existing self-contained reference workflow remains intact.
39. As a user, I want obsolete unnamed bundles rejected with guidance to
    regenerate them, so that an unsupported preview format is not silently
    interpreted using invented metadata.

## Implementation Decisions

### Accepted product contract

- Retain **File → Create Reference…** as the entry point. It opens or focuses
  one creation window and preserves an existing form or operation. Keep native
  keyboard, editing, focus, and dialog behavior.
- The initial form has a bundle-name text field, an editable local FASTA path,
  **Browse…**, and **Create bundle**. Accept the existing local uncompressed
  FASTA input. No GTF control or generic file-list editor is introduced.
- Derive an untouched name suggestion from the FASTA filename without its
  final extension. Once the user edits the name, preserve it on subsequent
  FASTA changes, including an intentionally cleared value that fails validation.
- Trim surrounding name whitespace and reject a blank name. Require a readable
  local input file before presenting the destination chooser. Display validation
  errors beside the affected field; perform content parsing during generation.
- Use a native Save dialog with `.bref` enforced and normal replacement
  confirmation. Suggest a filename derived from the stored name; editing the
  filename does not change the bundle name. Canceling the dialog preserves
  the form and starts no work.
- Show progress and **Cancel** in the creation window. Browsing remains
  available while generation runs. Only one operation, including its cleanup,
  may be active; repeated actions cannot create another worker.
- A successful save quietly closes the creation window. It does not open or
  select the new bundle, restore an earlier viewer snapshot, show a success
  dialog, or send a system notification.
- **Cancel** cancels generation and returns to the populated editable form
  after cleanup. A failure does the same and reports the known error in the
  creation window. Cancellation is not presented as an error.
- Closing during generation offers **Keep Creating** and **Cancel and Close**.
  The latter waits for cleanup before closing. Closing an idle form discards
  it without confirmation; a new window starts empty, including its name-edit
  tracking. Drafts are not persisted between windows or launches.
- Closing the viewer does not close the creation window or cancel its work.
  Quitting during generation offers **Keep Creating** and **Cancel and Quit**.
  The first abandons the quit request; the second waits for cleanup before exit.
- Existing source validation, provenance, sequence preservation, BAM/reference
  compatibility, and safe-save guarantees continue to apply. The bundle name
  is a display label, not sequence identity or a compatibility criterion.

### Proposed module and interface changes

These engineering choices implement the accepted behavior; their testing
interfaces were confirmed on 2026-11-21.

- Move creation ownership out of the viewer window into one application-owned
  creation controller. Keep its interface centered on opening/focusing the
  window, initiating creation, cancellation, close, and quit handling. The
  application delegates lifecycle decisions to this owner; the viewer retains
  browsing and source selection. A viewer window is not required to keep the
  operation alive.
- Keep form state, name-edit tracking, operation identity, progress, and pending
  close/quit intent together in that controller. Freeze the validated inputs
  for a running operation. A delayed result may affect only that operation and
  its window, never a later window or the viewer's current navigation.
- Reuse the existing native panel presentation boundary for Browse and Save,
  attaching those dialogs to the creation window. Retain native Save approval
  and file identity checks. Do not attach creation progress to the viewer or
  use application-modal progress to disable browsing.
- Extend the reference-bundle create/open interface with a required bundle
  name. Expose the validated name when opening a bundle and carry it through
  the viewer presentation. The selected-reference field uses the stored name,
  retaining existing native truncation and the filename tooltip. An absent
  reference still displays **No reference**.
- Keep the current SQLite storage and bounded sequence chunks. Introduce a
  new format version with required name metadata and update schema validation
  accordingly. Preserve the `.bref` suffix and existing provenance fields;
  the source filename and bundle name are distinct values.
- Apply bounded UTF-8 metadata validation consistently at creation and opening.
  Reuse the existing metadata size bound; reject an oversized name with a
  useful diagnostic rather than silently truncating it. Preserve the trimmed
  display name independently of any filename sanitization. A suggested output
  name must be a safe leaf filename, never a directory path derived from the
  display name.
- Reject old unnamed or unsupported bundles clearly and direct the user to
  regenerate them. Add no migration, filename fallback, or legacy reader.
  Application v1.0.0 and bundle format versions are separate version histories.
- Extend the existing safe publication boundary only as needed for concurrent
  browsing. Selection protection cannot rely solely on the reference captured
  when Save was confirmed: coordinate the final publication decision with
  reference-selection commits and recheck the current open file identity,
  including aliases. If it is protected, fail the creation safely and retain
  the current viewer. Avoid a check-then-publish gap that permits replacement
  of a newly selected reference.
- Keep existing confirmation-time destination identity checks and atomic
  publication of a validated candidate. A changed destination requires fresh
  confirmation. Failure or cancellation before publication preserves existing
  bytes and removes staging output; success is reported only after publication.
- Resolve cancellation versus publication once at the commit boundary. A
  cancellation accepted before commit prevents publication; a completed commit
  remains success and must not later be reported as canceled or rolled back.
  Repeated cancellation, close, and quit requests cannot bypass cleanup or
  trigger duplicate publication. Defer app termination until the operation's
  final outcome and cleanup are known.
- Keep parsing, bundle validation, and substantial disk work off the UI thread.
  Reuse the existing progress reporting and bounded I/O behavior. Add the next
  supported input as a typed form row and creation input when needed; avoid
  a speculative annotation framework in this increment.

## Testing Decisions

The user confirmed these testing interfaces on 2026-11-21.
Test externally observable behavior: native controls, window
lifetime, viewer presentation, errors, and resulting files. Prefer real small
FASTA/BAM fixtures and existing synchronization gates over mocks of every
internal object. Do not assert private state enums, helper call counts, widget
construction order, or incidental SQL statements.

### Primary interface: native creation workflow

Extend the existing native reference-save tests to exercise the application-owned
creation controller through File-menu actions, form controls, native panel
responses, and close/quit requests. Reuse the current panel presenter and
progress-based worker gates. This is one workflow interface, not a separate
test interface for each helper.

Cover form entry through Browse and pasted paths, untouched versus edited name
suggestions, validation before Save, native `.bref` enforcement and replacement
approval, preserved inputs after canceled Save, and one-window/one-operation
behavior. Assert the saved name and file contents, not just that a worker ran.

Use controlled worker progress to prove browsing can actually navigate and
change sources during generation, including reference-only and BAM/reference
views. Verify creation completion cannot overwrite those later viewer choices.
Exercise ordinary cancellation, errors, explicit close cancellation, retained
inputs, idle discard/reopen, quiet successful closure, and no automatic selection.

Test closing the viewer while generation continues and both quit choices,
including repeated requests and cleanup in progress. Keep the app-lifetime
owner accessible through the same native workflow interface used by the app.
Use a dedicated native process for any actual termination check, following
the existing isolated native-file-dialog test pattern, so the test runner is
not terminated. Verify completed execution, not only process exit status.

Use deterministic synchronization around publication and reference selection
to cover opening the destination during generation, aliases, destination changes,
and cancellation racing with commit. Assert safe file outcomes and preserved
viewer state. A narrowly scoped synchronization hook at the existing publication
boundary is acceptable if the progress callback cannot reach that ordering;
avoid an independently mocked storage stack or sleep-based correctness tests.

### Supporting interface: real-file bundle create/open/read

Extend the existing reference-bundle round-trip tests through the public
create/open/read operations. Assert that the chosen name survives source removal,
bundle moves, and a filename different from the name. Read independently
specified sequences to retain the portable, case-preserving bundle guarantee.

Cover missing, blank, oversized, and malformed name metadata; an old unnamed
format fixture must fail with regeneration guidance. Retain safe replacement,
cancellation cleanup, changed-destination, and alias-protection tests. Format
fixture mutation is appropriate for documented validation guarantees, without
coupling ordinary workflow tests to internal schema mechanics.

Reuse the existing standalone-reference native tests to verify the stored
display name, filename tooltip, empty state, and short/long names at supported
window sizes. Keep viewer-session regression coverage for source replacement,
compatibility rejection, draft preservation, and creation without selection.
These reuse existing interfaces and do not require another new testing layer.

### Validation and performance evidence

Run the existing native test runner and require its completed test summary;
an exit-zero process alone is insufficient. Replace assertions of the old
modal browsing pause with the newly accepted behavior. Run existing bundle,
viewer, and documentation checks affected by the change.

Include a focused native exercise of browsing while a representative human
FASTA is generated, recording creation completion and viewer responsiveness
under the existing measurement conventions. The feature is not satisfied merely
by enabling navigation buttons. Preserve existing correctness and bounded-memory
expectations; this specification invents no new timing threshold or claimed
measurement. Broader performance investigation is warranted only if the focused
check exposes a regression or implementation materially changes resource use.

## Out of Scope

- GENCODE GTF or other annotation import, annotation rendering, compressed
  FASTA, downloads, and generic extensible import frameworks.
- Multiple creation windows, parallel creation jobs, queues, presets, persisted
  drafts, batch creation, and automatic restoration of a closed form.
- Automatic bundle opening, success dialogs or notifications, and a persistent
  post-creation view or **Show in Finder** action.
- Renaming an existing bundle's stored name through a new editing interface.
- Compatibility readers, migrations, or filename-derived names for older
  bundles; a stable-release compatibility contract is future work.
- Storage-engine replacement, new sequence encoding, checksum schemes, whole-file
  integrity scans, and changes to genomic compatibility or alignment rendering.
- Implementation ticket decomposition, feature implementation, pull-request
  publication, merging, and release delivery as part of writing this spec.

## Further Notes

The product design was confirmed on 2026-11-21 after decisions C1–C13. It revises
the earlier reference milestone's filename-derived display names and modal
creation while retaining save-without-opening and safe destination handling.
The pre-1.0 compatibility policy is an accepted repository-wide development
policy; it does not weaken validation or support for documented external inputs.

The testing interfaces were confirmed on 2026-11-21. The specification was then
published under the `ready-for-agent` label for implementation planning; that
label alone did not claim implementation or test execution. Subsequent delivery
and qualification are recorded in the acceptance record linked above.

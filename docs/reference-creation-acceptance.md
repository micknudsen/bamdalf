# Named reference creation acceptance

This record maps the confirmed 2026-11-21 [parent specification](https://github.com/micknudsen/bamdalf/issues/70)
to the implementation delivered by [#71](https://github.com/micknudsen/bamdalf/issues/71),
[#72](https://github.com/micknudsen/bamdalf/issues/72), and
[#73](https://github.com/micknudsen/bamdalf/issues/73), and the integrated
qualification in [#74](https://github.com/micknudsen/bamdalf/issues/74).
The parent issue's text and state remain unchanged.

The final workflow uses an application-owned creation window, a required stored
name, native Browse and Save panels, and background generation while browsing
continues. Version 2 rejects obsolete unnamed bundles with regeneration guidance.
The [development guide](development.md#build-test-and-launch) describes the user flow;
the [format](reference-format.md) defines portable storage and safe publication.
The earlier dated milestone design and measurement reports retain their historical
filename-derived names and modal creation evidence; those two product rules are
superseded by C1 and C3 below.

## Evidence boundaries

The approved interfaces are native creation controls and lifecycle, real-file
bundle create/open/read, and existing viewer presentation/session behavior.
Deterministic tests stop real import work at progress or publication boundaries;
they do not substitute a mock storage stack. This verifies event ordering and
file outcomes, independently of the representative timing exercise.

The integrated native scenario
`confirmedPanelResponsesSaveAndReopenTheBundleFromTheFileMenu` selects a FASTA
through Browse, enters **My named reference**, approves replacement of
`reference.bref`, and observes quiet closure with no reference selected. It moves
the output to `moved-again.bref`, removes the FASTA, and opens the bundle through
the File menu. It verifies the stored display name, filename tooltip, an exact
independently written 77-base expected sequence, and the established colored
mismatch after attaching the comparison BAM. Opening a fixture with v1 metadata
and no `bundle_name` then shows the native regeneration diagnostic while retaining
the valid reference, BAM, interval, unfinished draft, alignments, and scroll.

`parseFailureShowsItsDiagnosticAndPreservesDestinationBytes` additionally corrects
the invalid FASTA and retries successfully, checking the saved name and literal
`AcgT` sequence. These extend existing scenarios instead of adding a separate
checklist suite. They expose no new production-code gap in this slice.

The native panel test presents actual system Browse and Save sheets and checks
`.bref` enforcement. Successful replacement uses the existing native Save approval
delegate with the confirmed URL; the external macOS Replace button is not clicked
by the automated test. The actual-termination case runs in a dedicated native
process and requires a cleanup-completed marker from `applicationWillTerminate`;
process exit alone is insufficient. No claim here covers physical display
presentation latency or an exhaustive scheduler interleaving search.

## Qualification results

On 2026-11-21, the guarded native runner completed both extended integration and
error-retry scenarios: **2 tests in 1 suite passed in 1.594 seconds**. The focused
log is retained locally as `.local/validation/integrated-retry-native.log`.
These are execution results for the changed scenarios, not a substitute for the
complete supported-toolchain CI summary. Broader local runs on Swift 6.4.2
again ended without that completion summary and were rejected by the unchanged
guard; they are not recorded as passing. Delivery requires completed native CI.

The [frozen concurrent-creation protocol](performance/reference-creation-protocol-2026-11-21.md)
and [measurement report](performance/reference-creation-2026-11-21.md) separately
record the representative human FASTA, viewport, navigation workload, cache
conditions, build, completed runs, responsiveness and memory. Their finite
results do not assert all hardware or workloads behave identically.

## User-story traceability

Story numbers refer to the frozen parent specification. Test names below are
stable pointers within the linked source files, not additional tests generated
from the checklist.

| Stories | Delivered behavior | Concrete evidence |
| --- | --- | --- |
| 1–4 | File command opens/focuses one application-owned form with or without a BAM; one operation through cleanup | [Native creation](../Tests/BamdalfKitTests/NativeReferenceSaveTests.swift): `creationFormKeepsInputsUntilItsWindowCloses`, `savingAReferenceReturnsToTheSameViewer`, `cancelDuringImportKeepsTheConfirmedDestinationAndAllowsBrowsing`; [generation](../Tests/BamdalfKitTests/NativeReferenceGenerationTests.swift): close/quit cases reject duplicate work during cleanup |
| 5–7 | Editable local FASTA path, native Browse, FASTA-only form | Native creation: `fastaChangesSuggestNamesUntilTheUserEditsOne`, `invalidFieldsPreventSaveAndCanceledSaveRetainsValidatedInputs`, `fileMenuOpensANativeFASTAChooserAndTheSavePanelEnforcesBref`; form control inspection |
| 8–11 | Basename suggestion updates until name edited, including deliberately empty edits | Native creation: `fastaChangesSuggestNamesUntilTheUserEditsOne`, `confirmedSaveFreezesInputsAndCompletesQuietly` |
| 12–13 | Stored name survives source removal and file moves; viewer uses it | Native creation: integrated File-menu scenario; [bundle](../Tests/BamdalfKitTests/ReferenceBundleTests.swift): `portableCasePreservingBundle`; [standalone native](../Tests/BamdalfKitTests/NativeStandaloneReferenceTests.swift): `fileMenuBrowsesAndClosesWithAReadOnlyFieldAtBothWindowWidths` |
| 14–16 | Trimmed nonblank bounded name and readable local file before Save; parse contents during generation | Native creation: `invalidFieldsPreventSaveAndCanceledSaveRetainsValidatedInputs`, `parseFailureShowsItsDiagnosticAndPreservesDestinationBytes`; bundle: `invalidNamesPreserveTheConfirmedDestination`, `nameLimitCountsUTF8BytesAfterTrimming` |
| 17–21 | Native Save, safe suggested filename, enforced suffix and approval, canceled Save preserves inputs | Native creation: `invalidFieldsPreventSaveAndCanceledSaveRetainsValidatedInputs`, `fileMenuOpensANativeFASTAChooserAndTheSavePanelEnforcesBref`, integrated File-menu scenario; [approval tests](../Tests/BamdalfKitTests/ReferenceBundleTests.swift): `confirmedSaveReplacesOnlyAfterCreatingACompleteBundle` |
| 22–24 | Progress and Cancel in the form; real navigation/source changes during import survive its completion | Native creation: `cancelDuringImportKeepsTheConfirmedDestinationAndAllowsBrowsing`; generation: `browsingAndSourceChangesSurviveGeneration` in reference-only and paired modes across success/cancellation/changed destination; representative native measurement reported separately |
| 25–26 | Cleanup restores populated editable form; cancellation stays quiet, errors diagnose, retry succeeds | Native creation: `cancelDuringImportKeepsTheConfirmedDestinationAndAllowsBrowsing`, `parseFailureShowsItsDiagnosticAndPreservesDestinationBytes` |
| 27–29 | Preserve approved existing output or leave no incomplete new output; protect a reference selected during import, including aliases | Generation: `referenceOpenedDuringGenerationCannotBeReplaced`, `browsingAndSourceChangesSurviveGeneration`, `cancellationSettlesBeforeOrAfterAtomicPublication`; standalone native: `selectionAfterSaveApprovalStillProtectsTheDestination`; bundle: cancellation, changed-destination, locked-file and concurrent-save cases |
| 30–32 | Quiet close after success, no automatic opening/selection or viewer restoration | Native creation: integrated File-menu scenario, `confirmedSaveFreezesInputsAndCompletesQuietly`, `savingAReferenceReturnsToTheSameViewer`; generation: `browsingAndSourceChangesSurviveGeneration` |
| 33–35 | Keep Creating / Cancel and Close; idle discard, empty reopened form and reset suggestion tracking | Generation: `closingViewerKeepsGenerationAliveAndCreationCloseWaitsForCleanup`; native creation: `creationFormKeepsInputsUntilItsWindowCloses`, `confirmedSaveFreezesInputsAndCompletesQuietly` |
| 36–37 | Viewer lifetime independent; both quit choices and repeated requests wait for cleanup | Generation: `closingViewerKeepsGenerationAliveAndCreationCloseWaitsForCleanup`, `quittingWaitsForCleanupAndKeepCreatingAbandonsQuit`; [termination](../Tests/BamdalfKitTests/NativeReferenceTerminationTests.swift): `actualApplicationTerminationFollowsCompletedCleanup` |
| 38–39 | Portable case-preserving output without FASTA; obsolete unnamed bundle rejected without replacing valid viewer | Native creation: integrated File-menu scenario; bundle: `portableCasePreservingBundle`, `relocatedBundleIsUsableInAReadOnlyDirectoryWithoutSidecars`, `invalidOrObsoleteNamesRequireRegeneration` |

## Accepted-decision traceability

| Decision | Accepted rule | Evidence in story mapping |
| --- | --- | --- |
| C1 | Stored display name, independent filename | 12–13, 17–21, 38–39 |
| C2 | Earlier unnamed formats may become obsolete; no fallback | 38–39 and [pre-1.0 policy](../CONTRIBUTING.md#pre-10-compatibility-policy) |
| C3 | Background creation while browsing remains usable | 22–24, 27–29 and representative native measurement |
| C4 | One creation window and operation | 1–4 |
| C5 | Keep Creating / Cancel and Close with cleanup | 33–35 |
| C6 | Close after successful save without selecting it | 30–32 |
| C7 | Suggested basename until name edited | 8–11 |
| C8 | Bundle name and editable FASTA/Browse inputs only | 5–7 |
| C9 | Validate fields before Save, contents during import | 14–16 |
| C10 | Preserve form on cancellation/error after cleanup | 21, 25–26 |
| C11 | Idle close discards inputs; reopening starts empty | 33–35 |
| C12 | Generation independent of viewer; quit waits for cleanup | 36–37 |
| C13 | Quiet successful completion | 30–32 |

The full native suite also retains [paired-source compatibility](../Tests/BamdalfKitTests/PairedSourceTests.swift),
[standalone reference navigation](../Tests/BamdalfKitTests/StandaloneReferenceTests.swift),
and [source lifecycle](../Tests/BamdalfKitTests/SourceLifecycleTests.swift)
regressions. Bundle names remain display labels, never compatibility keys.
Creation adds no GTF import, legacy reader, automatic selection, release flow,
or rendering behavior.

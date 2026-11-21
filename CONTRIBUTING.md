# Contributing

Use US English and the terms in [GLOSSARY.md](GLOSSARY.md). The accepted product
behavior is recorded in [docs/design.md](docs/design.md); implementation work is
tracked under the [MVP specification](https://github.com/micknudsen/bamdalf/issues/1).

## Pre-1.0 compatibility policy

Accepted 2026-11-21. Until the first stable v1.0.0 release, prioritize the current
product model over backward compatibility with earlier bamdalf versions and
their generated artifacts. Breaking changes to bamdalf-owned formats are
acceptable. Add migration code, legacy readers, or fallback behavior only when
an explicit product requirement calls for compatibility; preserving earlier
preview behavior alone is not a requirement.

For incompatible reference bundles, use a clear rejection and ask the user to
regenerate the bundle. In particular, bundles without the newly required stored
name may become obsolete; no filename fallback or migration is required.
This policy does not relax validation, safe saving, or support for the external
input formats specified by the product design. Establish the stable compatibility
contract when preparing v1.0.0; this policy does not define that future contract.

## Pull requests

All contributions, including documentation and CI changes, go through a branch
and pull request into `master`. Keep each change focused and reviewable.

Before merging, the branch must be up to date and all configured checks must
succeed on the current revision. `Documentation` and `Required checks` are the
initial required checks. The final check requires a successful result from every
job listed in its `needs`; failure, cancellation, and skipped work do not satisfy
it. When adding a new CI job, include it in that dependency list and update the
required checks in branch protection before merging the change. Required
workflows run on every pull request without path filters.

Use squash merges only. `master` requires linear history and PRs, applies its
rules to administrators, and disallows force pushes and deletion. Merged branches
are deleted automatically. A mandatory approval from a second GitHub account is
not required; review and explicit authorization to merge remain part of the
development process.

## Documentation checks

Install Node.js 22 or newer; CI uses Node.js 24. From the repository root, run:

```sh
npm ci --ignore-scripts
npm run check:docs
```

The locked tools check Markdown structure, relative file/image links, and heading
fragments. HTTP links are not fetched, and HTML links are outside the local-link
rule's scope. Long prose lines are allowed. `.local/` contains private working
material and is excluded from Git and these checks.

Node.js and the npm files support documentation validation only. For native
prerequisites and build/test/launch commands, see
[Native development](docs/development.md).

The dependency overrides select patched RE2JS and KaTeX releases while the
upstream tools still select affected versions. Recheck these overrides when
updating the documentation tools; see the
[RE2JS advisory](https://github.com/advisories/GHSA-gg6h-894w-4m9c) and
[KaTeX advisory](https://github.com/advisories/GHSA-238p-pmpm-9mq7).

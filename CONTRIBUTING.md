# Contributing

Use US English and the terms in [GLOSSARY.md](GLOSSARY.md). The accepted product
behavior is recorded in [docs/design.md](docs/design.md); implementation work is
tracked under the [MVP specification](https://github.com/micknudsen/bamdalf/issues/1).

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

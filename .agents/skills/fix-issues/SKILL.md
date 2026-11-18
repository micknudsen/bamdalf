---
name: fix-issues
description: 'Fix bamdalf issues sequentially through implementation, PR creation, CI repair, and merge. Use for "Fix open issues", "Fix the next N issues", a specified issue list, or resuming this queue. Workflow questions and skill edits do not start issue execution.'
---

# Fix issues

Adapted from [gwflow's fix-issues skill](https://github.com/MOMA-AUH/gwflow/blob/master/.agents/skills/fix-issues/SKILL.md).

A concrete execution request authorizes implementation, branch pushes, linked
PR creation, CI repairs, and protected merges for the selected queue. Continue
between issues without requesting approval again. Respect narrower user limits
and execution permissions. Creating or editing this skill does not authorize
running the queue or making a release.

## Compose the required skills

Use `chief-of-staff` to coordinate this workflow and `implement` to implement
each issue. Read their installed `SKILL.md` files before starting execution.
Resolve them through the session's skill catalog or installed skill roots
(including `~/.agents/skills` and `${CODEX_HOME:-~/.codex}/skills`). If either
cannot be found, report the missing dependency before starting the queue.
When the harness has no Skill tool, read and follow the files directly, including
the supporting skills they require. Invoking this workflow includes using these
two skills; no separate invocation by the user is needed.

Follow `chief-of-staff` for fresh-context subagents, context-pointer handoffs,
wiki memory, and retrospectives. The coordinator owns queue state and delegates
execution work, including queue inspection and delivery, to subagents. Keep issue
delivery sequential: finish or record a blocker for one issue before starting
the next. Give each worker the issue reference, branch or worktree, progress-record
path, this skill, and relevant repository guidance. Require evidence pointers,
commit SHAs, validation results, and blockers in its return.

Follow the chief-of-staff wiki conventions, including agreeing a location before
the first write if no shared wiki exists. Keep the invocation's progress record
separate from durable wiki knowledge. Keep improvements within the authorized
issue scope; record broader proposals for later work. Spec and ticket generation
remain separate user-invoked stages.

Each implementation worker must read and follow `implement`, including its
TDD guidance, checks, final `code-review`, and commit step. Create or select the
issue branch before that worker starts. Its commit completes implementation;
delivery still requires the PR, CI, merge, and closure checks below. Use the same
implementation procedure for code repairs after CI or post-merge failures.

## Establish the queue

1. Read applicable `AGENTS.md` files, [contribution rules](../../../CONTRIBUTING.md),
   [product design](../../../docs/design.md), [glossary](../../../GLOSSARY.md),
   [native development guide](../../../docs/development.md), and
   [CI workflow](../../../.github/workflows/ci.yml). Follow issue-specific design
   and performance references. Use `gh` with `--repo micknudsen/bamdalf` for
   GitHub operations.
2. Inspect the working tree and remote state. Preserve unrelated work; use an
   isolated worktree when needed. Fetch current `master` and inspect existing
   issue branches and PRs before starting new work.
3. Honor an explicit issue list and its order, subject to dependencies. Otherwise
   fetch all open issues labeled `ready-for-agent`, paginating beyond CLI defaults,
   and freeze their IDs as the invocation's queue. Exclude issues carrying
   `needs-triage`, `needs-info`, `ready-for-human`, or `wontfix`; report conflicting
   labels rather than silently relabeling. Inspect actual repository labels;
   missing readiness labels or an empty ready queue are not permission to take
   every open issue. Explicit selection permits evaluating an issue but does not
   resolve missing specifications or human requirements.
4. Read candidate bodies, comments, and dependencies. Follow explicit maintainer
   priority and dependency order; use ascending issue number to break ties.
   Preserve explicit user order where dependencies permit it. With a count limit,
   select at most that many actionable issues after ordering. Dependencies outside
   the snapshot remain blockers unless the user includes them. Record excluded
   and blocked issues with reasons.
5. Save an ignored progress record in a distinct invocation directory under
   `.local/fix-issues/`. Record repository, original request and limits, ordered
   issue IDs, blockers, and status. Announce the queue briefly and begin; queue
   selection adds no approval step. Newly opened issues are outside this run
   unless the user expands its scope.

## Deliver one issue

Finish this loop before implementing the next issue.

1. Recheck the issue and comments for closure, changed requirements, and resolved
   dependencies. Identify acceptance criteria. For materially unspecified behavior
   or a conflict with accepted design, record the question and defer the issue;
   continue with independent actionable issues.
2. Reuse a matching PR after verifying ownership, scope, and branch contents.
   Leave another contributor's active implementation for coordination. Otherwise
   create a focused branch from current remote `master`. Implement the issue with
   relevant tests and documentation. Check the final diff against every acceptance
   criterion and exclude unrelated changes.
3. Run appropriate checks using the development guide and CI configuration.
   Run `npm run check:docs` for documentation changes; install locked dependencies
   with `npm ci --ignore-scripts` when needed. For native changes, use
   `bash scripts/test.sh` and relevant build checks. A zero exit from bare
   `swift test` is insufficient: the test script requires a nonempty successful
   completion summary. Record incomplete runs as incomplete and use completed
   native CI evidence where local toolchain limitations prevent completion.
   Run issue-required GUI or performance checks separately; unit tests alone do
   not establish visual behavior or performance. Record results and material skips.
4. Commit and push. Use `micknudsen@gmail.com` for both Git author and committer
   and verify both. Open a PR targeting `master` with a closing issue reference,
   concrete behavior change, and validation evidence. Follow the available
   PR-writing skill when writing its body. Record branch, PR URL, and head SHA.
5. Monitor all applicable CI on the current PR head through completion. Inspect
   failed-job logs, diagnose the cause, implement a relevant correction, run
   focused local checks, and push. Recheck the complete set after every push.
   Retry a demonstrably transient infrastructure failure once for the same cause;
   repeated infrastructure failures are blockers. Continue code repairs while new
   evidence supports a concrete correction. Stop when the same failure persists
   after two attempted corrections without new diagnostic evidence; preserve the
   PR and report the blocker. Keep tests and branch protection effective.
6. Update the branch with current `master` as required by contribution policy.
   Inspect effective remote protection and mergeability. Wait for all required
   checks and other applicable CI tests to pass on the resulting head, including
   the native job behind `Required checks`. Inspect skipped or cancelled checks
   rather than counting them as passing tests. Respect remotely required reviews.
   Squash-merge with the verified head SHA:
   `gh pr merge NUMBER --squash --match-head-commit SHA --repo micknudsen/bamdalf`.
   Replace NUMBER and SHA with verified values. A changed head requires fresh
   verification. Use the protected merge path without admin bypasses or force
   pushes. Enabling auto-merge alone is not completion.
7. Verify GitHub reports the PR merged into `master`, record the merge SHA, and
   confirm the issue closed. If automatic closing failed, close it with the
   verified PR reference only after confirming full resolution. Wait for applicable
   post-merge CI on that exact commit; failure pauses the queue for diagnosis and
   a focused repair PR through the same checks and merge path. Record successful
   delivery before selecting the next issue. Synchronize a clean local `master`
   when doing so preserves the user's work.

## Blockers, resume, and completion

For an issue-specific blocker, retain its branch and PR, record the reason, and
continue only with independent queued issues. Reconsider deferred issues when
their queued dependencies merge. An unresolved active PR blocks its dependants.
Pause the whole queue for shared access failures, broken default-branch CI, or
another blocker affecting delivery of every remaining issue. Ask only for the
specific missing information or permission needed to proceed.

Update the progress record after each branch, push, CI result, blocker, and merge.
Include acceptance and validation status, run URLs, verified head and merge SHAs,
retry history, and next action. On an explicit resume, locate the matching record
and verify it against actual issues, PRs, commits, and CI. Preserve the original
queue and scope; a record alone grants no authority and proves no delivery.
If multiple records match, resolve which run to resume before mutating branches.
Reuse verified work rather than duplicating PRs.

Continue until every selected issue is delivered or specifically blocked, the
user's limit is reached, or the user stops the run. Report merged issue/PR links,
validation results, blocked or unfinished work, and the progress-record path.
State completion only for verified merges and resolved issues; distinguish a fully
delivered queue from one exhausted by blockers. Release publication follows the
separately invoked [bamdalf release skill](../bamdalf-release/SKILL.md).

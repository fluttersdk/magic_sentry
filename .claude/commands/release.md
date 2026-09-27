---
description: Prepare a release. Bumps the version, promotes the changelog, syncs docs and the magic reference page, opens the release PR, then tags the merge commit, which triggers validate + publish to pub.dev.
---

## Context

- Current version in pubspec.yaml: !`grep '^version:' pubspec.yaml`
- Current branch: !`git branch --show-current`
- Git tags: !`git tag -l | sort -V | tail -10`
- Unreleased changes: !`sed -n '/## \[Unreleased\]/,/^## \[/p' CHANGELOG.md | head -40`
- Recent commits since last tag: !`git log $(git describe --tags --abbrev=0 2>/dev/null || echo HEAD~20)..HEAD --oneline`
- Test status: !`flutter test 2>&1 | tail -3`
- Analyzer status: !`dart analyze 2>&1 | tail -3`

## Arguments

$ARGUMENTS: the target version (e.g. `0.0.2`, `0.1.0`). If empty, bump the patch segment.

## Your task

You are preparing a release of the **Magic Sentry** Flutter plugin. Work through these phases in order.

### Phase 1: Validation

1. **Branch**: start from an up-to-date `main` (`git fetch origin`), and cut `release/{version}` from `origin/main`.
2. **Clean tree**: `git status` shows no uncommitted change. If dirty, STOP and warn.
3. **Tests and analyzer**: all tests pass and the analyzer reports zero issues (see context above). If not, STOP and report.
4. **Floors**: every sibling floor in `pubspec.yaml` (`magic`) names the newest published release, and so does the pubspec comment above it. A new magic API this package calls needs the floor that ships it.
5. **Agent-facing reference**: update `../magic/skills/magic-framework/references/plugin-sentry.md` against this release and move its first-line stamp (`<!-- magic_sentry v{version} | Updated: {YYYY-MM-DD} -->`). That page, not this repo's `CLAUDE.md`, is what an agent adopting this package reads: `.pubignore` keeps `CLAUDE.md` and `.claude/` out of the published archive. It lives in the magic repository and reaches the skill registry with magic's next release, so open that change as its own magic PR.

### Phase 2: Version Bump

| File | What to update |
|------|----------------|
| `pubspec.yaml` | `version:` field |
| `CHANGELOG.md` | Move `[Unreleased]` content to `## [{version}] - {YYYY-MM-DD}`, leave an empty `## [Unreleased]` above it |
| `CLAUDE.md` | `**Version:**` line |
| `README.md` | `**Version:**` line |
| `doc/getting-started/installation.md` | `magic_sentry: ^{version}` in the install snippet |

Then `git grep -nF {old-version} -- ':!CHANGELOG.md'` comes back empty.

### Phase 3: Changelog Review

1. **Cross-reference**: every merged PR since the last tag has an entry under `### Added`, `### Changed` or `### Fixed`.
2. **Entry format**: a bold lead sentence, then what changed and why, then the touched paths in parentheses.
3. **Breaking**: a change to `SentryServiceProvider`'s constructor, `MagicSentry.run`'s parameters, or what the barrel exports is breaking and says so first.

### Phase 4: Local Verification

All must pass:

1. `dart format --set-exit-if-changed .`
2. `flutter analyze --no-fatal-infos`
3. `flutter test`
4. `dart pub publish --dry-run`: zero warnings

### Phase 5: Release PR

1. Commit as `chore(release): {version}` and push the branch by name: `git push -u origin HEAD:refs/heads/release/{version}`.
2. Open the PR against `main` with that title. Body: what ships, the floors, the stamps, the gates with their counts, and the tag command.
3. Wait for CI green; merge with `gh pr merge --squash`.

### Phase 6: Tag and Publish

```bash
git fetch origin
git show <merge-oid>:pubspec.yaml | grep '^version:'   # must print {version}
git tag {version} <merge-oid> && git push origin {version}
```

The bare tag (no `v` prefix) triggers `publish.yml`: validate, then OIDC publish to pub.dev. Watch it and confirm the version is live:

```bash
gh run list --workflow=publish.yml --limit 1 --json databaseId,headBranch --jq '.[0]'
gh run watch {run_id} --exit-status
curl -s https://pub.dev/api/packages/magic_sentry | jq -r '.latest.version'
```

If publish fails, report the error. The tag already exists; fix and re-run the workflow.

### Output

```
## Release {version} Complete

**PR:** {url} · **Tag:** {version} on {merge-oid}
**Local:** Tests ({count} passed) · Analyzer (0 issues) · Format clean · Dry-run (0 warnings)
**pub.dev:** Published (run #{publish_run_id}): https://pub.dev/packages/magic_sentry
**Reference page:** magic PR {url} (plugin-sentry.md stamped v{version})
```

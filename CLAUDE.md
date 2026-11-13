# Magic Sentry Plugin

Sentry error and performance monitoring for the Magic Framework: a zone-wrapped boot before `Magic.init`, HTTP failure reports, a scope user that follows `Auth.stateNotifier`, event breadcrumbs and URL token masking.

**Version:** 0.0.7 · **Dart:** >=3.12.0 · **Flutter:** >=3.44.0

## Commands

Host-dispatched through the Magic installer, no package-specific CLI provider:

| Command | Description |
|---------|-------------|
| `flutter test --coverage` | Run all tests with coverage |
| `flutter analyze --no-fatal-infos` | Static analysis |
| `dart format .` | Format all code |
| `flutter pub publish --dry-run` | Pre-publish check |
| `python3 tool/check-docs.py` | Docs structure, links, fragments and ToC anchors; run it after any `doc/` change |
| `dart run magic:dowel plugin:install magic_sentry` | Publish `lib/config/sentry.dart` and inject `SentryServiceProvider` into the consumer's `lib/config/app.dart` |

## Architecture

**Pattern**: zone-wrapped boot helper plus one ServiceProvider. There is no Driver or Handler chain, because there is one transport, Sentry's own.

```
lib/
├── magic_sentry.dart          # Barrel export, the only public API
└── src/
    ├── event_breadcrumbs.dart          # ReportsBreadcrumb event -> Sentry breadcrumb
    ├── magic_sentry.dart               # MagicSentry.run + error widget breadcrumb
    ├── sentry_service_provider.dart    # SentryServiceProvider<T>: wires boot()
    ├── sentry_network_interceptor.dart # MagicNetworkInterceptor -> Sentry events and breadcrumbs
    ├── sentry_token_scrubber.dart      # beforeSend/Transaction/Span/Breadcrumb/SendLog: masks URL-borne tokens
    └── sentry_user_context.dart        # Auth.stateNotifier -> Sentry scope user
install.yaml                   # Plugin manifest: config publish, provider injection
assets/stubs/install/sentry_config.stub  # configureSentry, published into a consumer's lib/config/sentry.dart
example/                       # Magic app: MagicSentry.run, the provider and a test event button
doc/                           # User docs, published by the docs site: getting-started/, basics/, guides/
skills/magic-sentry/           # Agent skill, installed with `npx skills add anilcancakir/magic_sentry`
tool/check-docs.py             # Offline docs gate, run by docs-link-check.yml
```

**The barrel exports no config.** `configureSentry`, `sentryDsn`, `sentryEnabled` and the env key constants live only in the file `plugin:install` publishes into a consumer app. A package-side copy would collide with the consumer's own `import 'config/sentry.dart'`, which the documented `main()` imports next to the barrel, and `configureSentry` would become an ambiguous import.

**The config is not a magic config factory.** `MagicSentry.run` starts Sentry before `Magic.init` so a boot failure is reported too. `Config` is not loaded then, so `configureSentry` reads `.env` through `Env`, and `install.yaml` has no `magic.config_factory` key.

**Data flow:** `main()` calls `MagicSentry.run(configure, appRunner)` → one zone (`runZonedGuarded`) → `SentryWidgetsFlutterBinding.ensureInitialized()` → `Env.load()` → `SentryFlutter.init(configure, appRunner)` → `Magic.init` and `runApp` → `SentryServiceProvider.boot()` wires the network interceptor, the user context, the event breadcrumb listener and the navigator observer, all gated on `Sentry.isEnabled`.

**User reporting is opt-in and generic.** The package has no model of its own: `SentryServiceProvider<T>` takes `userId`, `userEmail` and `userExtras` over the host's `Authenticatable` model. `userId` alone turns reporting on.

## Post-Change Checklist

After ANY source code change, sync **before committing**. A change is not done while one of these is stale:

1. **`CHANGELOG.md`**: Add entry under `[Unreleased]` section
2. **`README.md`, `llms.txt` and the `doc/` pages**: Update if features, API, or usage changes
3. **`skills/magic-sentry/SKILL.md`**: Update when the API, a rule or a gotcha changes; its `version:` moves with the release, and the publish check compares it with the tag
4. **`CLAUDE.md`**: Update the architecture tree when files move

## Development Flow (TDD)

Red, green, refactor for every feature, fix or refactor: no production code without a failing test first. After every change `flutter test` stays green and `dart analyze` reports zero warnings and errors; run `dart format .` before committing.

## Testing

- No mocking library: fake through contract inheritance, as the `NetworkDriver` spy in `sentry_service_provider_test.dart` does
- Tests mirror `lib/src/` and import from `package:magic_sentry/magic_sentry.dart`
- Reading the scope needs a bound hub: `Sentry.init` with a placeholder DSN, and `Sentry.close()` plus `Auth.unfake()` in `tearDown`
- Clear `SentryNetworkInterceptor.reportedFailures` in `setUp`; register routes with `MagicRoute.page` and call `MagicRouter.reset()` in `tearDown` for scrubber tests

## Key Gotchas

| Mistake | Fix |
|---------|-----|
| Reading `sendDefaultPii` or session replay from `.env` | Never; both stay hardcoded off in `configureSentry`. An app that wants either overrides its own `configure` callback explicitly |
| `sentry_dio`'s `addSentry()` and `SentryNetworkInterceptor` both capturing failed requests | `SentryServiceProvider` disables `captureFailedRequests` on `addSentry()`; the interceptor alone decides event or breadcrumb |
| Calling `MagicRouter.instance.addObserver` after `routerConfig` was built | Register `SentryServiceProvider` in `lib/config/app.dart`'s `providers` list, which boots before any route is built |
| A guarded network or log call throwing anyway | `Magic.bound('log')` with a narrow `try` and `catch` around `app.make<NetworkDriver>('network')`, matching magic_deeplink's pattern for an optional dependency that must not take the boot down |
| Team logic, tags or breadcrumbs specific to one app | Does not belong here; use `userExtras` or an event implementing `ReportsBreadcrumb` |
| A hook assigned after `SentryFlutter.init` | It replaces `SentryTokenScrubber`; set app hooks inside `configure` |
| Bumping `sentry_flutter` or `sentry_dio` | Re-run `test/sentry_token_scrubber_test.dart` first; the scrubber must keep covering streamed spans |
| Relative paths in `pubspec_overrides.yaml` | Use ABSOLUTE ones; the file is never committed |

## Release

1. Open a `release:` PR that bumps `pubspec.yaml`, `skills/magic-sentry/SKILL.md` and the `Version:` line above, and promotes `[Unreleased]` in `CHANGELOG.md`. `.claude/commands/release.md` walks it.
2. After it merges, tag the merge commit with the bare version (`git tag 0.0.8 && git push origin 0.0.8`, no `v`). `publish.yml` runs from the tag; the pub.dev Admin tab holds repository `anilcancakir/magic_sentry`, tag pattern `{{version}}` and push events only.
3. A failed `validate` is fixed forward: delete the tag (`git push --delete origin <tag>` and `git tag -d <tag>`), fix it on a PR and tag the new merge commit, because a re-run builds the same commit. If only `github-release` fails after pub.dev accepted the version, use "Re-run failed jobs" (never "Re-run all jobs", where `publish` is rejected as a duplicate) or run `gh release create <tag> --title <tag> --latest --verify-tag --notes-file <file>`.

The first publish (0.0.1) was a manual `flutter pub publish`, since tag-triggered OIDC cannot create a package.

## CI

- `ci.yml`: push/PR → `flutter pub get` → `flutter analyze --no-fatal-infos` → `dart format --set-exit-if-changed` → `flutter test --coverage` → codecov upload
- `changelog.yml`: a PR that changes `lib/`, `install.yaml` or `assets/stubs/` must also change `CHANGELOG.md`; Dependabot, `release:` PRs and the `skip-changelog` label are exempt
- `docs-link-check.yml`: every PR runs `python3 tool/check-docs.py` and an offline lychee pass; Mondays an external-link pass
- `publish.yml`: tag on master → version stamps (tag, pubspec, skill) → analyze, format, test, dry-run, pana 160/160, changelog section → OIDC publish → GitHub Release
- `dependabot-auto-merge.yml`: arms auto-merge for GitHub Actions minor and patch bumps only

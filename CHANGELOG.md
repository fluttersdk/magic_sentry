# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.1.0] - 2026-11-14

### Changed

- **BREAKING: the SDK floor is Dart `>=3.13.0` and Flutter `>=3.47.0`.** Inherited from `magic` 0.1.0, which moved to `dowel`, `wind_kit` and `material_ui`. magic_sentry itself uses none of them; the example app imports `material_ui` in place of Flutter's deprecated `material.dart`. The README, `llms.txt`, the agent skill and the installation guide quote the new floors and `magic` `^0.1.0`. (`pubspec.yaml`, `example/pubspec.yaml`, `example/lib/main.dart`)
- **Direct dependencies move to their latest releases.** `sentry_flutter` and `sentry_dio` `^10.3.0` to `^10.4.0` (also in `example/`), `test` `^1.25.0` to `^1.32.0`. (`pubspec.yaml`, `example/pubspec.yaml`)

- **The repository moved to `anilcancakir/magic_sentry`.** `homepage` (the package landing), `repository` and `issue_tracker` in `pubspec.yaml` point at the new owner, the `documentation` key is gone (the landing links the docs, as for magic and wind), and the LICENSE holder is now Anılcan Çakır. The package name, the API and the version line are unchanged. (`pubspec.yaml`, `LICENSE`)
- **The workflows and the README badge target `master`.** CI, the changelog check and the docs check run on pull requests to `master`. Every action is pinned by commit SHA and the workflows run with read-only permissions by default. (`.github/workflows/`)
- **The publish workflow validates more and releases itself.** The tag must sit on `master` and name the same version as `pubspec.yaml` and the agent skill, `flutter pub publish --dry-run` and a pana run that must score 160 points pass, and a `## [<version>]` CHANGELOG section must exist before anything is published. The GitHub Release is then created from that section. (`.github/workflows/publish.yml`)
- **The pub.dev description and topics are written for search and for agents.** The description leads with the job ("Sentry for Magic apps") and the four things it does; the topics are `sentry`, `error-monitoring`, `crash-reporting`, `observability` and `magic`, and `flutter` is gone because pub.dev derives the SDK tag itself. (`pubspec.yaml`)
- **The README follows the Magic plugin standard.** It opens with the Magic logo and the centered header, then an `At a glance` table, one section per capability and a `For AI coding agents` rules table. (`README.md`, `.github/magic-logo.svg`)
- **The analyzer no longer suppresses `unintended_html_in_doc_comment`.** The package analyzes clean without it. (`analysis_options.yaml`)
- **Every change keeps the docs in step.** The post-change checklist in `CLAUDE.md` and the pull request template require the changelog, README, `llms.txt`, `doc/` pages and the agent skill to match the change, and the release command now targets `master`. (`CLAUDE.md`, `.claude/commands/release.md`)
- **The install command and the installer references use the new names.** The docs, the skill, `llms.txt` and the `install.yaml` comment say `dart run magic:dowel plugin:install magic_sentry`, a command that arrives with magic 0.1.0, and point at dowel for the `install.yaml` schema. (`README.md`, `doc/`, `llms.txt`, `skills/magic-sentry/SKILL.md`, `install.yaml`)

### Added

- `lib/cli.dart` with `MagicSentryDowelProvider`, so `plugin:install magic_sentry` registers under dowel. It contributes no commands, stays Flutter-free, and `dowel` ^0.0.21 is a new dependency. (`lib/cli.dart`, `lib/src/cli/sentry_dowel_provider.dart`, `pubspec.yaml`)
- `doc/`: seven pages in the repository's docs standard (installation, boot and the provider, HTTP reporting, user context, event breadcrumbs, token scrubbing and testing), checked by `tool/check-docs.py` and a docs link check on every pull request. The installation guide moved here from a single page.
- `llms.txt`: the package for an AI coding agent, with setup, the API, platform support and the rules an agent must follow.
- `skills/magic-sentry`: an agent skill for the package, installed with `npx skills add anilcancakir/magic_sentry`. It stays out of the pub.dev archive.
- `example/`: a runnable Magic app (web runner included) whose `main()` is `MagicSentry.run`, with the provider registered, a button that files a test event and a button that fails an HTTP call to show the interceptor.
- `SECURITY.md`, a pull request template, issue forms that link the private vulnerability report and the API reference, and a `Changelog` check: a pull request that changes `lib/`, `install.yaml` or `assets/stubs/` must also change `CHANGELOG.md`.

### Fixed

- **The docs and the post-install message return a `String` from `userId`.** `Model.id` is `dynamic` and often an `int`, and an int id throws when `SentryUserContext` installs, which takes `Magic.init` down for a session restored at boot. The samples now write `user.id?.toString() ?? ''` and the pages carry a gotcha for it. (`install.yaml`, `doc/`, `README.md`, `llms.txt`, `skills/magic-sentry/SKILL.md`)
- **`SENTRY_RELEASE` is documented as read from the bundled `.env`.** `Env` does not read `--dart-define`, so the published config comment and the installation guide no longer say it does. (`assets/stubs/install/sentry_config.stub`, `doc/getting-started/installation.md`)
- **The scrubber's fail-closed note matches `sentry_flutter` 10.** A throwing hook makes the SDK drop the event, breadcrumb or log, but send a streamed span half scrubbed; the scrubber keeps the report with the covered fields masked either way. `MagicSentry.run`'s doc comment now lists `beforeSendSpan` among the hooks it wraps. (`lib/src/sentry_token_scrubber.dart`, `lib/src/magic_sentry.dart`)
- **`SentryUserContext` assigns its extractors through initializing formals.** Three `prefer_initializing_formals` infos cost the package 10 pub.dev points. The constructor now uses Dart 3.12's private named parameters (`required this._id`); the public names `id`, `email` and `extras` are unchanged. (`lib/src/sentry_user_context.dart`)

## [0.0.7] - 2026-11-10

### BREAKING

- **`sentry_flutter` and `sentry_dio` move to `^10.3.0`, and the minimum SDK to Dart 3.12 and Flutter 3.44.** An app on `sentry_flutter` 9 stays on 0.0.6. Version 10 also needs Android `minSdk` 26 and iOS 15, and drops CocoaPods for Swift Package Manager; the app's own `SentryFlutter.init` options must drop what 10 removed (`enableLogs`, `enableMetrics`, `profilesSampleRate`, `enableStandaloneAppStartTracing`) and give `beforeSendLog` and `beforeSendMetric` their second `Hint` parameter.

### Added

- **`SentryTokenScrubber.beforeSendSpan` masks streamed spans.** `sentry_flutter` 10 sends each span as it finishes by default (`SentryTraceLifecycle.stream`) and builds no transaction, so `beforeSendTransaction` never ran and a span name or attribute carrying a token went out unscrubbed. The new hook applies the same rules to the span `name` and to every string and string-array attribute, reads an `http` span's name as `METHOD url`, gives its `url.full` the opaque-segment rule of a transaction span's `url` and its `http.query` the query rule, fails closed to `[Filtered]`, and `install` runs it before the app's own `beforeSendSpan`. `beforeSendTransaction` stays for apps that choose `SentryTraceLifecycle.static`. The wrapped `beforeSendLog` now passes the `Hint` through to the app's hook. (`lib/src/sentry_token_scrubber.dart`)

## [0.0.6] - 2026-11-07

### Added

- **`SentryTokenScrubber` masks structured logs too.** A log sent through `Sentry.logger` (with `enableLogs` on) carried its body and attributes to Sentry unscrubbed, since the scrubber covered events, transactions and breadcrumbs only. The new `SentryTokenScrubber.beforeSendLog` applies the same query-value and route-bound-token rules to the log `body` and to every string and string-array attribute, leaving number and boolean attributes alone, and `install` (so `MagicSentry.run`) now wraps `beforeSendLog` as well: the scrubber runs first and hands the scrubbed log to the app's own hook, sync or async, which may still drop it. It fails closed: the SDK catches a throwing `beforeSendLog` and sends the original log, so on failure the body and every string attribute become `[Filtered]` instead. (`lib/src/sentry_token_scrubber.dart`, `lib/src/magic_sentry.dart`)

### Changed

- **`MagicSentry.run` creates `SentryWidgetsFlutterBinding` instead of `WidgetsFlutterBinding`.** `SentryFlutter.init` installs Sentry's binding only when none exists, and `run` created Flutter's plain one first (it has to exist before `Env.load` reads the asset bundle), so frame tracking logged a warning and disabled itself in every app booted through `run`. The binding is still created at the same point, in the same zone. An app that calls `WidgetsFlutterBinding.ensureInitialized()` before `run` keeps the plain binding and loses frame tracking. (`lib/src/magic_sentry.dart`)

## [0.0.5] - 2026-10-14

### Added

- **`SentryTokenScrubber` keeps URL-borne tokens out of Sentry.** On web the SDK sets `request.url` to `window.location` and the transaction to the raw pathname, and `sentry_dio` breadcrumbs and spans keep the API path, so `/invitations/<token>/accept` and `/auth/reset-password?token=` reached Sentry. The scrubber masks query values whose key contains `token`, `password`, `secret`, `signature`, `credential` or `api_key`; path segments bound to a magic route param whose name contains `token` (read from `MagicRouter.instance.allRoutes`, so routes inside `MagicRoute.group(layout: ...)` count; needs magic 0.0.29, which adds it); and, on `http` breadcrumb and span urls, any 32+ character `[A-Za-z0-9_-]` path segment that is not a UUID (numeric ids and the query stay). Hash-routed urls (`https://host/#/invitations/<token>/accept`) and a fragment that opens with a secret pair (`#access_token=...`) are covered. It covers `request.url`, `request.queryString`, `request.fragment`, the transaction name, `contexts.trace`, exception values, the event message, breadcrumb `message` and `data`, and span descriptions and data. It only masks, never drops, and fails closed: if the scrubber throws, those fields are replaced with `[Filtered]` instead of letting the SDK send the half-scrubbed original. `MagicSentry.run` installs it after `configure`, so it runs first in `beforeSend`, `beforeSendTransaction` and `beforeBreadcrumb` and then hands its result to any hook the app set. (`lib/src/sentry_token_scrubber.dart`, `lib/src/magic_sentry.dart`, `lib/magic_sentry.dart`)

### Changed

- **`magic` floor moves `^0.0.28` to `^0.0.29`.** The token scrubber reads `MagicRouter.allRoutes`, which magic 0.0.29 introduces, so an adopter on an older magic now gets a version-solve error instead of a compile error inside this package. (`pubspec.yaml`)
- **`SentryNetworkInterceptor` reports a scrubbed endpoint.** The message, fingerprint and `http_failure` context of a captured failure now carry `SentryTokenScrubber.scrubApiUrl`, so an invitation call that fails with a 500 groups under `/api/v1/invitations/{token}/accept` instead of carrying the token. `normalizeEndpoint` is production API now and loses its `@visibleForTesting`. (`lib/src/sentry_network_interceptor.dart`)

## [0.0.4] - 2026-10-13

### Changed

- **Every sibling floor names this batch's release.** `magic` moves `^0.0.27` to `^0.0.28`. The old range already admitted the new version, so a fresh `pub get` resolves nothing differently; what changes is that the floor names the release this package is verified against. magic 0.0.28 is not breaking: it moves its own floors to artisan 0.0.20 and wind 1.8.4 and its devtools install pins, none of which this package calls. The issue template's magic version placeholder moves from `0.0.22` to `0.0.28`. (`pubspec.yaml`, `.github/ISSUE_TEMPLATE/bug_report.yml`)

## [0.0.3] - 2026-10-09

### Changed

- **Every sibling floor names this batch's release.** `magic` moves `^0.0.24` to `^0.0.27`. The old range already admitted the new version, so a fresh `pub get` resolves nothing differently; what changes is that the floor names the release this package is verified against. None of magic 0.0.25 to 0.0.27 is breaking. (`pubspec.yaml`)

## [0.0.2] - 2026-09-29

### Changed

- **Every sibling floor names this batch's release.** `magic` moves `^0.0.22` to `^0.0.24`. The old range already admitted the new version, so a fresh `pub get` resolves nothing differently; what changes is that the floor names the release this package is verified against. The real requirement is still 0.0.22, the first release with `Event.listenAny` and `ReportsBreadcrumb`. magic 0.0.24 removes `MagicController.onRefreshUI` (BREAKING); this package calls it nowhere in `lib/` or `test/`, so nothing here moves with it. (`pubspec.yaml`)
- **The README and the installation guide name the event breadcrumbs and the magic requirement.** The README lists `ReportsBreadcrumb` events among what the plugin reports, and its layout names `event_breadcrumbs.dart`; the installation guide states magic 0.0.22 or higher and why. (`README.md`, `doc/getting-started/installation.md`)
- **The published archive leaves out the repository's tooling.** A `.pubignore` keeps `.claude/`, `CLAUDE.md`, `.github/` and IDE folders out of the archive. A `.pubignore` replaces `.gitignore` for pub rather than adding to it, so it also names the local-only files `.gitignore` covered (`pubspec_overrides.yaml`, `pubspec.lock`, `coverage/`, `.env`). (`.pubignore`)

## [0.0.1] - 2026-09-27

Initial release.

### Added

- `MagicSentry.run`: a zone-wrapped `SentryFlutter.init` boot, web-safe per flutter/flutter#100277, and `MagicSentry.installErrorWidgetBreadcrumb`, which tags a build error that replaced the interface.
- `SentryServiceProvider<T>`: wires `SentryNetworkInterceptor` into magic's `Http` driver (with `sentry_dio`'s own failed-request capture disabled to avoid double reporting), installs `SentryUserContext<T>` on `Auth.stateNotifier` when a host app supplies `userId`/`userEmail`, and registers `SentryNavigatorObserver` on `MagicRouter`. A failure wiring the interceptor is reported, through `Log.warning` with its stack trace when `log` is bound and `debugPrint` otherwise, never swallowed.
- `SentryNetworkInterceptor`: reports a 5xx or a dead connection as an event fingerprinted by the normalised endpoint, a 4xx as a breadcrumb, and deduplicates repeats within a session.
- `SentryUserContext<T>`: keeps Sentry's scope user (id and email) and optional extra tags in step with the host app's own `Authenticatable` model. `install()` is idempotent: a second call adds no second listener.
- `EventBreadcrumbs.breadcrumbFor`: maps any dispatched event that implements magic's `ReportsBreadcrumb` (`breadcrumbCategory`, `breadcrumbMessage`, `breadcrumbData`) to a Sentry breadcrumb, and answers null for every other event. `SentryServiceProvider.boot` wires it through `Event.listenAny`, gated on `Sentry.isEnabled` like the provider's other hooks, and registers it once however many times it boots in one isolate. Any package or app event that opts in (`magic_deeplink`'s `DeeplinkOpened` and `DeeplinkNavigating`, for example) shows up in the breadcrumb trail with no extra wiring. (`lib/src/event_breadcrumbs.dart`)
- `assets/stubs/install/sentry_config.stub`, published by `install.yaml` into a consumer's `lib/config/sentry.dart` as an editable starting point: a `configureSentry` reading `SENTRY_DSN`, `SENTRY_ENVIRONMENT`, `SENTRY_RELEASE` and `SENTRY_TRACES_SAMPLE_RATE` from `.env`. The barrel does not export a package copy of those names, so the documented `main()` imports them unambiguously from the app.
- Requires `magic ^0.0.22`, the first release with `Event.listenAny` and `ReportsBreadcrumb`, and `sentry_flutter` / `sentry_dio` `^9.27.0`.

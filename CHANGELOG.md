# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- **`SentryTokenScrubber` keeps URL-borne tokens out of Sentry.** On web the SDK sets `request.url` to `window.location` and the transaction to the raw pathname, and `sentry_dio` breadcrumbs and spans keep the API path, so `/invitations/<token>/accept` and `/auth/reset-password?token=` reached Sentry. The scrubber masks query values whose key contains `token`, `password`, `secret`, `signature`, `credential` or `api_key`; path segments bound to a magic route param whose name contains `token` (read from `MagicRouter.instance.allRoutes`, so routes inside `MagicRoute.group(layout: ...)` count; needs the magic release that adds it); and, on `http` breadcrumb and span urls, any 32+ character `[A-Za-z0-9_-]` path segment that is not a UUID (numeric ids and the query stay). Hash-routed urls (`https://host/#/invitations/<token>/accept`) and a fragment that opens with a secret pair (`#access_token=...`) are covered. It covers `request.url`, `request.queryString`, `request.fragment`, the transaction name, `contexts.trace`, exception values, the event message, breadcrumb `message` and `data`, and span descriptions and data. It only masks, never drops, and fails closed: if the scrubber throws, those fields are replaced with `[Filtered]` instead of letting the SDK send the half-scrubbed original. `MagicSentry.run` installs it after `configure`, so it runs first in `beforeSend`, `beforeSendTransaction` and `beforeBreadcrumb` and then hands its result to any hook the app set. (`lib/src/sentry_token_scrubber.dart`, `lib/src/magic_sentry.dart`, `lib/magic_sentry.dart`)

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

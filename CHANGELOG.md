# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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

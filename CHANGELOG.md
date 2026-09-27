# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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

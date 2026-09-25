# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed

- The barrel (`lib/magic_sentry.dart`) no longer exports `config/sentry.dart`. The published install stub puts the same top-level names (`configureSentry`, `sentryDsn`, `sentryEnabled`, the env key constants) into a consumer app's own `lib/config/sentry.dart`; exporting a package copy alongside that made the documented `main()` an ambiguous import that never compiled. The package no longer carries its own copy of that file; `assets/stubs/install/sentry_config.stub` is now the single source.
- `SentryServiceProvider._registerNetworkInterceptor` no longer swallows a wiring failure when no `log` binding exists. It now always reports: `Log.warning` (with the stack trace) when `log` is bound, `debugPrint` otherwise.
- `SentryUserContext.install()` is now idempotent: a second call on the same instance no longer adds a second listener to `Auth.stateNotifier`, which used to run `apply()` twice per auth-state bump.

### Added

- Initial release: `MagicSentry.run` (zone-wrapped `SentryFlutter.init` boot, web-safe per flutter/flutter#100277) and `MagicSentry.installErrorWidgetBreadcrumb` (tags a build error that replaced the interface).
- `SentryServiceProvider<T>`: wires `SentryNetworkInterceptor` into magic's `Http` driver (with `sentry_dio`'s own failed-request capture disabled to avoid double reporting), installs `SentryUserContext<T>` on `Auth.stateNotifier` when a host app supplies `userId`/`userEmail`, and registers `SentryNavigatorObserver` on `MagicRouter`.
- `SentryNetworkInterceptor`: reports a 5xx or a dead connection as an event fingerprinted by the normalised endpoint, a 4xx as a breadcrumb, and deduplicates repeats within a session.
- `SentryUserContext<T>`: keeps Sentry's scope user (id + email) and optional extra tags in step with the host app's own `Authenticatable` model.
- `lib/config/sentry.dart` default `configureSentry`, reading `SENTRY_DSN`, `SENTRY_ENVIRONMENT`, `SENTRY_RELEASE` and `SENTRY_TRACES_SAMPLE_RATE` from `.env`; published to a consumer project via `install.yaml` as an editable starting point.

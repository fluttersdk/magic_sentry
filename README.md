# Magic Sentry Plugin

Sentry error and performance monitoring for the [Magic Framework](https://magic.fluttersdk.com). Wraps `sentry_flutter` boot in a web-safe zone, reports the HTTP failures magic's `Http` facade swallows into `MagicResponse` values, keeps Sentry's scope user in step with `Auth.stateNotifier`, turns any event implementing magic's `ReportsBreadcrumb` into a breadcrumb, and registers a navigator observer on `MagicRouter`.

**Version:** 0.0.4 · **Dart:** >=3.6.0 · **Flutter:** >=3.27.0

## Install

```bash
flutter pub add magic_sentry
dart run <app>:artisan plugin:install magic_sentry
```

`plugin:install` (from `fluttersdk_artisan`, no package-specific CLI needed) reads this package's `install.yaml`, publishes `lib/config/sentry.dart` (documents the `.env` keys read at boot: `SENTRY_DSN`, `SENTRY_ENVIRONMENT`, `SENTRY_RELEASE`, `SENTRY_TRACES_SAMPLE_RATE`), and injects `SentryServiceProvider` into `lib/config/app.dart`'s provider list. See [doc/getting-started/installation.md](doc/getting-started/installation.md) for the full walkthrough, including the `main.dart` wiring the installer cannot do for you.

## Quick start

```dart
// main.dart
import 'config/sentry.dart';

void main() {
  MagicSentry.run(configure: configureSentry, appRunner: _boot);
}

Future<void> _boot() async {
  MagicSentry.installErrorWidgetBreadcrumb();
  await Magic.init(configFactories: [...]);
  runApp(MyApp());
}
```

```dart
// lib/config/app.dart
(app) => SentryServiceProvider<User>(
  app,
  userId: (user) => user.id,
  userEmail: (user) => user.email,
),
```

## Architecture

```
lib/
├── magic_sentry.dart          # Barrel export
└── src/
    ├── event_breadcrumbs.dart          # ReportsBreadcrumb event -> Sentry breadcrumb
    ├── magic_sentry.dart               # MagicSentry.run + error widget breadcrumb
    ├── sentry_service_provider.dart    # SentryServiceProvider<T>: wires boot()
    ├── sentry_network_interceptor.dart # MagicNetworkInterceptor -> Sentry events/breadcrumbs
    ├── sentry_token_scrubber.dart      # Masks URL-borne tokens before anything is sent
    └── sentry_user_context.dart        # Auth.stateNotifier -> Sentry scope user
install.yaml                   # Plugin manifest: config publish, provider injection
assets/stubs/install/sentry_config.stub  # configureSentry, published to a consumer's
                                          # own lib/config/sentry.dart; the package
                                          # itself carries no copy of it (see below)
```

The barrel does not export `configureSentry`/`sentryDsn`/`sentryEnabled`: those
names live only in the file `plugin:install` publishes into a consumer app
(`lib/config/sentry.dart`, from the stub above). A package copy exported
alongside it would make the documented `main()` (which imports both the
barrel and that local file) an ambiguous import.

## Key decisions

- **Not enabled by default.** `sentryEnabled`/`Sentry.isEnabled` answer false with an empty `SENTRY_DSN`, and every integration in this package degrades to a no-op rather than throwing.
- **`sendDefaultPii` and session replay are never turned on by this package.** An app that wants either does so explicitly in its own `configure` callback.
- **HTTP double-reporting is avoided on purpose.** `SentryServiceProvider` disables `sentry_dio`'s own `captureFailedRequests`, since `SentryNetworkInterceptor` is the layer that decides event vs breadcrumb.
- **User reporting is opt-in and generic.** This package has no model of its own; pass `userId` (plus `userEmail` when your model has one, and optionally `userExtras`) for your own `Authenticatable` model, or leave `userId` out to skip user reporting entirely.

## Token scrubbing

A magic route such as `/invitations/:token/accept` puts a credential in the path and a reset link puts one in the query. On web the SDK copies `window.location` into `request.url` and the pathname into the transaction name, and `sentry_dio` keeps the API path on every breadcrumb and span. `MagicSentry.run` therefore installs `SentryTokenScrubber` after your `configure` callback, in front of `beforeSend`, `beforeSendTransaction` and `beforeBreadcrumb`:

- **Query values** whose key contains `token`, `password`, `secret`, `signature`, `credential` or `api_key` become `[Filtered]`; the key and every other pair stay.
- **Route-bound segments:** a path segment sitting where a registered magic route has a param whose name contains `token` becomes `[Filtered]`. The routes are read from `MagicRouter.instance.routes` and from the routes inside `MagicRoute.group(layout: ...)`.
- **Opaque API segments:** on an `http` breadcrumb or span url, any path segment of 32 or more `[A-Za-z0-9_-]` characters (a UUID excepted) becomes `{token}`. Numeric ids and the rest of the url stay. The interceptor's own events and fingerprint additionally collapse ids to `{id}` and drop the query, as `SentryNetworkInterceptor.normalizeEndpoint` does.

It covers `request.url`, `request.queryString`, `request.fragment`, the transaction name, `contexts.trace`, exception values and the event message (an error text can embed the current url), breadcrumb `message` and `data`, and span descriptions and data. It only masks, never drops, and fails closed: if the scrubber itself throws, the fields it covers are replaced with `[Filtered]` and the event still goes out, because the SDK would otherwise send the half-scrubbed original. The `email` query key and numeric ids are left alone.

Set your own hooks inside `configure`: the scrubber runs first and hands its result to them. A hook assigned after `SentryFlutter.init` replaces the scrubber. A transaction's deprecated `extra` map (the same data `setData` on a transaction also writes to `contexts.trace.data`) is not scrubbed, so keep tokens out of transaction data.

See [doc/getting-started/installation.md](doc/getting-started/installation.md) for configuration details.

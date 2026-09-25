# Installation

- [Introduction](#introduction)
- [Requirements](#requirements)
- [Installing the Package](#installing-the-package)
- [Running the Install Command](#running-the-install-command)
- [Wiring main()](#wiring-main)
- [Registering the Service Provider](#registering-the-service-provider)
- [Configuration Reference](#configuration-reference)
- [Release Health](#release-health)
- [Next Steps](#next-steps)

<a name="introduction"></a>
## Introduction

`magic_sentry` wires [Sentry](https://sentry.io) into a Magic application: a
web-safe zone-wrapped boot, HTTP failure reporting for magic's `Http` facade
(which never throws), a scope user kept in step with `Auth.stateNotifier`,
and a navigator observer on `MagicRouter`.

Sentry has to start BEFORE `Magic.init`, so a failure during boot is reported
too. That is the one place this package's install differs from a typical
Magic plugin: there is no `magic.config_factory` entry, because `Config` is
not loaded yet at the point Sentry needs its DSN.

<a name="requirements"></a>
## Requirements

- **Dart SDK**: 3.6.0 or higher
- **Flutter**: 3.27.0 or higher
- **Magic Framework** installed and bootstrapped (`lib/config/app.dart` present)

<a name="installing-the-package"></a>
## Installing the Package

```bash
flutter pub add magic_sentry
```

Or add it manually to `pubspec.yaml`:

```yaml
dependencies:
  magic_sentry: ^0.0.1
```

Then fetch dependencies:

```bash
flutter pub get
```

<a name="running-the-install-command"></a>
## Running the Install Command

This package ships no package-specific CLI provider; `fluttersdk_artisan`'s
generic manifest installer reads its `install.yaml` directly:

```bash
dart run <app>:artisan plugin:install magic_sentry
```

The command performs the following steps:

1. **Creates** `lib/config/sentry.dart` from the bundled stub.
2. **Injects** `SentryServiceProvider` into the `providers` list in `lib/config/app.dart`.

> [!NOTE]
> Steps 3 and 4 of a typical Magic plugin install (a config-factory injection
> into `Magic.init`, and a native platform edit) do not apply here: this
> package has neither. `main()` wiring is a manual step, covered next.

<a name="wiring-main"></a>
## Wiring main()

`MagicSentry.run` replaces the whole body of `main()`. It opens one zone,
initialises Flutter's binding, loads `.env`, then starts Sentry and hands
control to your existing boot function as `appRunner`:

```dart
import 'package:flutter/material.dart';
import 'package:magic/magic.dart';
import 'package:magic_sentry/magic_sentry.dart';
import 'config/app.dart';
import 'config/sentry.dart'; // injected by install

void main() {
  MagicSentry.run(configure: configureSentry, appRunner: _boot);
}

Future<void> _boot() async {
  // Tags a build error that replaced the interface, distinguishing it from
  // an exception that merely got logged. Call it before the first widget
  // builds.
  MagicSentry.installErrorWidgetBreadcrumb();

  await Magic.init(
    configFactories: [
      () => appConfig,
    ],
  );

  runApp(MagicApplication(title: 'My App'));
}
```

`configureSentry` comes from the published `lib/config/sentry.dart` and reads
`.env` directly (see [Configuration Reference](#configuration-reference)
below). Write your own `configure` callback instead when the standard keys
are not enough.

> [!IMPORTANT]
> `MagicSentry.run` must be the ENTIRE body of `main()`. On Flutter web,
> `SentryFlutter.init` opens its own zone only when called from the root zone
> (`PlatformDispatcher.onError` alone misses async errors there, see
> [flutter/flutter#100277](https://github.com/flutter/flutter/issues/100277)).
> Entering the zone in `MagicSentry.run` first is what avoids a second,
> competing zone and the "Zone mismatch" error Flutter raises when the
> binding and `runApp` end up in different zones.

<a name="registering-the-service-provider"></a>
## Registering the Service Provider

If you ran `plugin:install`, the provider was already injected with no type
argument and no user callbacks, which is a valid, working default (the
network interceptor and the navigator observer wire up; user reporting is
skipped). Edit `lib/config/app.dart` to add your own user model:

```dart
import 'package:magic/magic.dart';
import 'package:magic_sentry/magic_sentry.dart'; // injected by install
import '../app/models/user.dart';

final appConfig = {
  'app': {
    'providers': [
      (app) => RouteServiceProvider(app),
      (app) => AppServiceProvider(app),
      (app) => SentryServiceProvider<User>(
        app,
        userId: (user) => user.id,
        userEmail: (user) => user.email,
        // Optional: anything else worth tagging once a user is reported.
        userExtras: (user) => {
          if (user.currentTeam?.id case final String teamId)
            'team_id': teamId,
        },
      ), // injected by install, edit the type argument and callbacks by hand
    ],
  },
};
```

> [!TIP]
> `SentryServiceProvider.boot()` returns immediately when `Sentry.isEnabled`
> is false, which is every local run and the whole test suite unless a test
> calls `Sentry.init` itself. Nothing it wires ever runs without a DSN.

<a name="configuration-reference"></a>
## Configuration Reference

The generated `lib/config/sentry.dart` reads these `.env` keys:

| Key | Default | Purpose |
|-----|---------|---------|
| `SENTRY_DSN` | `''` (disabled) | Your project's DSN. Empty leaves the SDK inert; `appRunner` still runs. |
| `SENTRY_ENVIRONMENT` | `'local'` | Tags every event, e.g. `production`, `staging`. |
| `SENTRY_RELEASE` | `''` (unset) | Attached to every event. Required on web, which has no package manifest to auto-detect a release from; set it via `--dart-define` at build time. |
| `SENTRY_TRACES_SAMPLE_RATE` | `0.2` | Fraction of transactions traced. Client spans continue into the API through `sentry_dio`'s propagated `sentry-trace` header, so raising this multiplies server spans too. |

Two things `configureSentry` does NOT read from `.env`, on purpose:

- **`sendDefaultPii` stays `false`.** Flipping it sends the user's IP address
  and request bodies with every event. An app that needs it enables it in
  its own `configure` callback, explicitly, rather than through a stray
  environment variable.
- **Session replay is never enabled.** It has no Flutter web implementation
  and its own PII review; add it yourself if your app needs it.

<a name="release-health"></a>
## Release Health

`configureSentry` turns on `enableAutoSessionTracking`, but a session is only
recorded when `SentryNavigatorObserver` sees a NAMED route change (it reads
`RouteSettings.name`). `SentryServiceProvider` registers the observer for
you; make sure your own routes carry a `name`, or release health silently
stays empty while error reporting keeps working.

<a name="next-steps"></a>
## Next Steps

- **HTTP reporting**: `SentryNetworkInterceptor` reports a 5xx or a dead
  connection (`MagicError.statusCode == 0`) as an event, a 4xx as a
  breadcrumb, and deduplicates repeats within a session. See
  `lib/src/sentry_network_interceptor.dart`.
- **User context**: `SentryUserContext<T>` follows `Auth.stateNotifier`; see
  `lib/src/sentry_user_context.dart` for the id/email/extras contract.

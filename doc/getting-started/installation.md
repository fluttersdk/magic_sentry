# Installation

Add `magic_sentry` to a Magic app, run the installer, wrap `main()` in `MagicSentry.run` and set a DSN.

- [Install](#install)
- [Requirements](#requirements)
- [Wire main](#wire-main)
- [Register the Provider](#register-the-provider)
- [Configuration](#configuration)
- [Release Health](#release-health)
- [Verify](#verify)
- [Related Documentation](#related-documentation)

<a name="install"></a>
## Install

```bash
flutter pub add magic_sentry
dart run magic:dowel plugin:install magic_sentry
```

The installer reads the package's `install.yaml`, publishes `lib/config/sentry.dart` (your own copy, free to edit) and injects `SentryServiceProvider` into the `providers` list of `lib/config/app.dart`. It cannot rewrite `main()`, so that step is yours. There is no `magic.config_factory` entry: Sentry starts before `Magic.init`, when `Config` does not exist yet.

<a name="requirements"></a>
## Requirements

| Requirement | Value |
|:------------|:------|
| Dart | `>=3.13.0` |
| Flutter | `>=3.47.0` |
| Magic | `^0.1.0`, installed and bootstrapped (`lib/config/app.dart` exists). The token scrubber reads `MagicRouter.allRoutes`, which 0.0.29 introduced |
| Sentry SDK | `sentry_flutter` and `sentry_dio` `^10.3.0`, pulled in by the package. Version 10 needs Android `minSdk` 26, iOS 15 and macOS 12, and uses Swift Package Manager instead of CocoaPods |

An app on `sentry_flutter` 9 stays on magic_sentry 0.0.6. Version 10 removed `enableLogs`, `enableMetrics`, `profilesSampleRate` and `enableStandaloneAppStartTracing` from the init options, and gave `beforeSendLog` and `beforeSendMetric` a second `Hint` parameter; drop or update those in your own `configure` callback.

<a name="wire-main"></a>
## Wire main

`MagicSentry.run` is the whole body of `main()`. It opens one zone, creates Sentry's widgets binding, loads `.env`, starts Sentry and hands control to your boot function.

```dart
import 'package:magic/magic.dart';
import 'package:magic_sentry/magic_sentry.dart';
import 'package:material_ui/material_ui.dart';

import 'config/app.dart';
import 'config/sentry.dart'; // published by plugin:install

void main() {
  MagicSentry.run(configure: configureSentry, appRunner: _boot);
}

Future<void> _boot() async {
  // Tags a build error that replaced the interface; call it before the first widget builds.
  MagicSentry.installErrorWidgetBreadcrumb();

  await Magic.init(
    configFactories: [
      () => appConfig,
      // Keep every other config factory your main() already passes.
    ],
  );

  runApp(MagicApplication(title: 'My App'));
}
```

`configureSentry` reads `.env` directly. Write your own `configure` callback when the standard keys are not enough, and set your own `beforeSend`, `beforeBreadcrumb` and similar hooks inside it, never after `SentryFlutter.init`.

> [!IMPORTANT]
> Do not call `WidgetsFlutterBinding.ensureInitialized()` before `run`: an existing binding is kept, and Sentry's frame tracking then disables itself. Do not put anything else in `main()` either, or the app and its binding can end up in different zones.

<a name="register-the-provider"></a>
## Register the Provider

The installer adds the provider with no type argument and no callbacks, which is a working default: the network interceptor and the navigator observer wire up and user reporting is skipped. Edit the entry the installer added to the `providers` list of `lib/config/app.dart` to report your own user (`User` is your app's model):

```dart
import 'package:magic_sentry/magic_sentry.dart';

import '../app/models/user.dart';

final List<Object> providers = [
  // ...your other providers
  (app) => SentryServiceProvider<User>(
    app,
    userId: (user) => user.id?.toString() ?? '',
    userEmail: (user) => user.email,
  ),
];
```

`Model.id` is `dynamic` and is often an `int`, so return a `String`: an int id throws when the user context installs, and a signed-in session restored at boot would take `Magic.init` down with it.

<a name="configuration"></a>
## Configuration

`lib/config/sentry.dart` reads these `.env` keys:

| Key | Default | Purpose |
|:----|:--------|:--------|
| `SENTRY_DSN` | `''` (off) | The project DSN. Empty leaves the SDK inert and `appRunner` still runs. |
| `SENTRY_ENVIRONMENT` | `local` | Tags every event: `production`, `staging`. |
| `SENTRY_RELEASE` | unset | The release attached to every event. Required on web, which has no manifest to derive one from; write it into the `.env` you bundle at build time (`Env` does not read `--dart-define`). |
| `SENTRY_TRACES_SAMPLE_RATE` | `0.2` | Fraction of traces sampled. Client spans continue into the API through `sentry_dio`'s `sentry-trace` header, so a higher rate raises server spans too. |

Two things are never read from `.env`, on purpose. `sendDefaultPii` stays `false`: turning it on sends the user's IP address and request bodies with every event, so an app that needs it sets it in its own `configure`. `configureSentry` never enables session replay.

<a name="release-health"></a>
## Release Health

`configureSentry` turns on `enableAutoSessionTracking`, but a session is recorded only when `SentryNavigatorObserver` sees a named route change, because it reads `RouteSettings.name`. The provider registers the observer. Give your routes a `name`, or release health stays empty while error reporting keeps working.

<a name="verify"></a>
## Verify

Set `SENTRY_DSN` in `.env`, run the app and file one event:

```dart
import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> verify() async {
  assert(Sentry.isEnabled, 'SENTRY_DSN is empty, so the SDK is off');

  await Sentry.captureMessage('magic_sentry installed');
}
```

The message shows up in the Sentry project within a few seconds. With an empty DSN `Sentry.isEnabled` is `false` and every integration in this package does nothing.

<a name="related-documentation"></a>
## Related Documentation

- [Boot and the Provider](../basics/boot-and-provider.md): what `run` and `boot()` wire, in order.
- [HTTP Reporting](../basics/http-reporting.md): which failures become issues.
- [Token Scrubbing](../guides/token-scrubbing.md): what is masked before anything is sent.

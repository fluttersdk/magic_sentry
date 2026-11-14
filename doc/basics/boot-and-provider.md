# Boot and the Provider

`MagicSentry.run` starts Sentry before `Magic.init`; `SentryServiceProvider` wires the rest once Magic is up.

- [Quick Reference](#quick-reference)
- [MagicSentry.run](#magicsentry-run)
- [Error Widget Breadcrumb](#error-widget-breadcrumb)
- [SentryServiceProvider](#sentryserviceprovider)
- [Inert Without a DSN](#inert-without-a-dsn)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

```dart
import 'package:magic/magic.dart';
import 'package:magic_sentry/magic_sentry.dart';
import 'package:material_ui/material_ui.dart';

import 'config/sentry.dart'; // published by plugin:install

void main() {
  MagicSentry.run(configure: configureSentry, appRunner: _boot);
}

Future<void> _boot() async {
  MagicSentry.installErrorWidgetBreadcrumb();
  await Magic.init(
    configFactories: [
      // Every config factory your main() already passes.
    ],
  );
  runApp(MagicApplication(title: 'My App'));
}
```

| Member | What it does |
|:-------|:-------------|
| `MagicSentry.run` | Opens one zone, creates `SentryWidgetsFlutterBinding`, loads `.env`, calls `SentryFlutter.init`, then your `appRunner` |
| `MagicSentry.installErrorWidgetBreadcrumb` | Adds a `fatal` breadcrumb when a build error replaces the interface |
| `SentryServiceProvider<T>` | Wires the network interceptor, the user context, event breadcrumbs and the navigator observer in `boot()` |

<a name="magicsentry-run"></a>
## MagicSentry.run

`run` takes two callbacks. `configure` receives the `SentryFlutterOptions` to fill in (DSN, environment, sample rates); `appRunner` is everything the app does afterwards, typically `Magic.init` followed by `runApp`.

The order inside `run` is fixed: the zone opens, `SentryWidgetsFlutterBinding.ensureInitialized()` runs, `Env.load()` runs, then `SentryFlutter.init`. `SentryTokenScrubber` is installed after `configure` returns, so it runs first in every hook and hands its masked value to whichever hook `configure` set. A zone-level error goes to `Sentry.captureException` and is still dumped to the console.

One zone for everything is the point. On Flutter web `SentryFlutter.init` opens its own `runZonedGuarded` only when called from the root zone (flutter/flutter#100277), so entering a zone first keeps the app and its binding in the same zone and avoids Flutter's "Zone mismatch" error.

Sentry has to start before `Magic.init` so that a failure during boot is reported too. At that point `Config` is not loaded, which is why `configure` reads `.env` through `Env` and never through `Config.get`.

<a name="error-widget-breadcrumb"></a>
## Error Widget Breadcrumb

Flutter already reports the exception behind a broken build through `FlutterError.onError`. What `installErrorWidgetBreadcrumb` adds is a `fatal` breadcrumb (`category: ui.error_widget`) that tells "an exception got logged" apart from "an exception replaced the interface with the grey error box", which look identical in the issue list otherwise. It returns the default error widget unchanged, because a replacement screen needs colours, fonts and a theme, each of which can throw in the exact situation this runs in. Call it once, early in `appRunner`.

<a name="sentryserviceprovider"></a>
## SentryServiceProvider

Register it in the `providers` list of `lib/config/app.dart`. `register()` binds nothing. `boot()` returns at once unless `Sentry.isEnabled`, then wires, in this order:

1. The network driver: `sentry_dio`'s `addSentry(captureFailedRequests: false)` on a `DioNetworkDriver`, then `SentryNetworkInterceptor` into Magic's interceptor chain.
2. `SentryUserContext<T>.install()`, when `userId` was given.
3. The event breadcrumb listener, through `Event.listenAny`. A second boot in the same isolate removes the previous listener first.
4. `SentryNavigatorObserver` on `MagicRouter`.

| Parameter | Type | Effect |
|:----------|:-----|:-------|
| `userId` | `String Function(T user)?` | Turns user reporting on. Leave it out to skip user reporting; everything else still wires up |
| `userEmail` | `String? Function(T user)?` | Optional. A null or empty email reports the id alone |
| `userExtras` | `Map<String, String> Function(T user)?` | Scope tags applied while a user is reported |

`T extends Model` is your own `Authenticatable` model. The observer is registered in `boot()` because `MagicRouter` refuses one after it has built its `routerConfig`, which happens on the first frame; without it every event is filed against a route the app never names, since Magic drives go_router and the SDK cannot see through it.

The network driver is resolved from the container, so a host that never registered one (a bare widget test) would throw there. That one failure is caught narrowly and always reported: `Log.warning` when a `log` binding exists, `debugPrint` otherwise. It never fails the host's boot.

<a name="inert-without-a-dsn"></a>
## Inert Without a DSN

An empty `SENTRY_DSN` makes `Sentry.isEnabled` answer `false`. `boot()` then returns before wiring anything, `appRunner` still runs, and every other member of the package does nothing. That is every local run and the whole test suite unless a test calls `Sentry.init` itself. `sentryDsn` is a `String` and never null on purpose: `Sentry.init` throws on a null DSN, which would stop the app booting on every machine that has not set one.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Calling `Magic.init` before `MagicSentry.run` | `run` is the whole body of `main()`; `Magic.init` goes inside `appRunner` |
| Reading the Sentry config through `Config.get` | `Config` is not loaded when `configure` runs; read `.env` through `Env`, as the published file does |
| Importing `configureSentry` from the package | The barrel exports no config names; import your own `config/sentry.dart` |
| Calling `WidgetsFlutterBinding.ensureInitialized()` first | Remove it; the existing binding is kept and frame tracking disables itself |
| Registering the navigator observer in `main()` | The provider does it in `boot()`, before the router builds its config |
| Assigning `beforeSend` after `SentryFlutter.init` | The assignment replaces the scrubber; set app hooks inside `configure` |

<a name="related-documentation"></a>
## Related Documentation

- [Installation](../getting-started/installation.md): the installer and the `.env` keys.
- [HTTP Reporting](http-reporting.md): the interceptor the provider adds.
- [User Context](user-context.md): `userId`, `userEmail` and `userExtras` in depth.
- [Token Scrubbing](../guides/token-scrubbing.md): the hooks `run` installs.

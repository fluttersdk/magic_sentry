<p align="center">
  <img src="https://raw.githubusercontent.com/anilcancakir/magic_sentry/master/.github/magic-logo.svg" width="120" alt="Magic Logo" />
</p>

<h1 align="center">Magic Sentry</h1>

<p align="center">
  <strong>Sentry for Magic apps, with the tokens masked.</strong><br/>
  One call boots Sentry before <code>Magic.init</code> in a web-safe zone, reports the HTTP failures Magic's <code>Http</code> facade swallows, follows the signed-in user and masks URL-borne tokens. Without a DSN it does nothing.
</p>

<p align="center">
  <a href="https://pub.dev/packages/magic_sentry"><img src="https://img.shields.io/pub/v/magic_sentry.svg" alt="pub package"></a>
  <a href="https://github.com/anilcancakir/magic_sentry/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/anilcancakir/magic_sentry/ci.yml?branch=master&label=CI" alt="CI"></a>
  <a href="https://codecov.io/gh/anilcancakir/magic_sentry"><img src="https://codecov.io/gh/anilcancakir/magic_sentry/graph/badge.svg" alt="codecov"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://pub.dev/packages/magic_sentry/score"><img src="https://img.shields.io/pub/points/magic_sentry" alt="pub points"></a>
</p>

<p align="center">
  <a href="https://anilcancakir.com/magic_sentry">Documentation</a> ·
  <a href="https://pub.dev/packages/magic_sentry">pub.dev</a> ·
  <a href="https://github.com/anilcancakir/magic_sentry/issues">Issues</a>
</p>

## At a glance

| Fact | Value |
|---|---|
| Package | [`magic_sentry`](https://pub.dev/packages/magic_sentry) |
| Install | `flutter pub add magic_sentry`, then `dart run magic:dowel plugin:install magic_sentry` |
| Import | `package:magic_sentry/magic_sentry.dart` |
| Entry points | `MagicSentry.run` (boot), `SentryServiceProvider<T>` (wiring), `SentryTokenScrubber`, `SentryNetworkInterceptor`, `SentryUserContext<T>` |
| Platforms | Wherever `sentry_flutter` 10 runs: iOS 15+, Android `minSdk` 26+, macOS 12+, web, Windows and Linux; the zone boot is what makes web safe |
| Requires | Dart >=3.12, Flutter >=3.44, `magic` ^0.0.29 |
| Dependencies | `magic`, `sentry_flutter` ^10.3.0, `sentry_dio` ^10.3.0 |
| License | MIT |

## Install

```bash
flutter pub add magic_sentry
dart run magic:dowel plugin:install magic_sentry
```

The installer publishes `lib/config/sentry.dart` (your own editable copy that reads `SENTRY_DSN`, `SENTRY_ENVIRONMENT`, `SENTRY_RELEASE` and `SENTRY_TRACES_SAMPLE_RATE` from `.env`) and registers `SentryServiceProvider` in `lib/config/app.dart`. It cannot rewrite `main()`, so wrap it yourself:

```dart
import 'package:flutter/material.dart';
import 'package:magic/magic.dart';
import 'package:magic_sentry/magic_sentry.dart';

import 'config/app.dart';
import 'config/sentry.dart'; // published by plugin:install

void main() {
  MagicSentry.run(configure: configureSentry, appRunner: _boot);
}

Future<void> _boot() async {
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

`MagicSentry.run` must be the entire body of `main()`. Do not call `WidgetsFlutterBinding.ensureInitialized()` before it.

## Boot before Magic

Sentry starts before `Magic.init`, so a failure while Magic boots is reported too. `run` opens one zone, creates `SentryWidgetsFlutterBinding`, loads `.env`, starts the SDK and hands control to your `appRunner`. One zone is what keeps Flutter web from raising a "Zone mismatch". `SentryServiceProvider.boot()` then wires the rest once Magic is up, and returns at once when `Sentry.isEnabled` is false.

| Member | Effect |
|--------|--------|
| `MagicSentry.run` | One zone, Sentry's binding, `.env`, `SentryFlutter.init`, then `appRunner` |
| `MagicSentry.installErrorWidgetBreadcrumb` | A `fatal` breadcrumb when a build error replaces the interface |
| `SentryServiceProvider<T>` | Network interceptor, user context, event breadcrumbs and navigator observer |

## HTTP failures

Magic's `Http` facade never throws: a failure is a `MagicResponse` value, so no global error handler sees it. `SentryNetworkInterceptor` reports it.

| Status | Result |
|--------|--------|
| `0` (no response), `500` and above | An event, fingerprinted by `METHOD`, normalised endpoint and status |
| Anything else (`401`, `404`, `422`) | A breadcrumb on the next event |

```dart
final MagicResponse response = await Http.get('/monitors'); // a 503 here files one event

if (!response.successful) {
  // Already reported by the interceptor; handle the failure for the user.
}
```

An endpoint reaches Sentry with ids collapsed (`/monitors/{id}/checks`) and tokens masked, and one failure is one event per session; the repeats become breadcrumbs. A 4xx never opens an issue, so look for it in the breadcrumbs of the next event.

## User and breadcrumbs

Pass your own model's extractors and every event says who hit it. `Auth.stateNotifier` drives it, so logout clears the user.

```dart
(app) => SentryServiceProvider<User>(
  app,
  userId: (user) => user.id?.toString() ?? '',
  userEmail: (user) => user.email,
  userExtras: (user) => {'plan': user.plan},
),
```

| Callback | Runs | Result |
|----------|------|--------|
| `userId` | Every auth state change with a signed-in user | The Sentry user id; an empty string means nobody. Return a `String`: `Model.id` is `dynamic` and often an `int` |
| `userEmail` | Only for a user with a non-empty id | The email, or none when null or empty |
| `userExtras` | Only while a user is reported | Scope tags; each call replaces the previous keys, and sign-out clears them |

Any `MagicEvent` that also implements `ReportsBreadcrumb` becomes a Sentry breadcrumb with no extra wiring.

## Token scrubbing

A route such as `/invitations/:token/accept` puts a credential in the path, and a reset link puts one in the query. `MagicSentry.run` installs `SentryTokenScrubber` after your `configure`, in front of these hooks:

| Hook | Masks |
|------|-------|
| `beforeSend`, `beforeSendTransaction` | An event's URL, query, fragment, transaction name, exceptions and message; a transaction's spans too |
| `beforeSendSpan` | A streamed span's name and string attributes (the `sentry_flutter` 10 default) |
| `beforeBreadcrumb` | A breadcrumb's message and string data |
| `beforeSendLog` | A structured log's body and string attributes |

With three rules:

- **Query values** whose key contains `token`, `password`, `secret`, `signature`, `credential` or `api_key` become `[Filtered]`, a fragment that opens with such a pair (`#access_token=...`) included.
- **Route-bound segments:** a path segment where a registered Magic route has a `token` param becomes `[Filtered]`, groups included.
- **Opaque API segments:** on an `http` breadcrumb or span URL, a path segment of 32 or more token characters (a UUID excepted) becomes `{token}`.

It only masks, never drops, and fails closed: if the scrubber throws, the fields it covers become `[Filtered]` and the event still goes out, where the SDK would have dropped it (or sent a span half scrubbed). A hook assigned after `SentryFlutter.init` replaces the scrubber, so set your own hooks inside `configure`.

## For AI coding agents

Rules for an agent writing code against this package. Each one is a mistake the maintainers already made once.

| Do | Because |
|----|---------|
| Make `MagicSentry.run` the whole body of `main()` and put `Magic.init` inside `appRunner` | Sentry has to start first, in one zone; a second zone breaks the binding on web |
| Read the Sentry settings through `Env` in `configure` | `Config` is not loaded yet when `configure` runs |
| Import `configureSentry` from your own `config/sentry.dart` | The barrel exports no config names, and a second copy would make the import ambiguous |
| Register `SentryServiceProvider` in the `providers` list | The navigator observer has to be added before the router builds its config |
| Leave `captureFailedRequests` off on `addSentry()` | `SentryNetworkInterceptor` is the one layer that reports HTTP failures; both would double-report |
| Pass app data through `userExtras` or a `ReportsBreadcrumb` event | The package stays generic: no model, team or tag of its own |
| Keep secrets out of `breadcrumbData` | It is whitelisted by the event author and sent as written, apart from token masking |
| Set app hooks inside `configure` | A hook assigned after `SentryFlutter.init` replaces the scrubber |

## Dependencies

`magic` for the container, `Auth.stateNotifier`, `MagicRouter` and the event dispatcher; `sentry_flutter` for the SDK and `sentry_dio` for HTTP breadcrumbs and spans on the `Dio` network driver. Version 10 of the Sentry SDK needs Android `minSdk` 26, iOS 15 and macOS 12; an app on `sentry_flutter` 9 stays on magic_sentry 0.0.6.

## Links

- [Documentation](https://anilcancakir.com/magic_sentry/docs/getting-started/installation): installation, boot, HTTP reporting, user context, breadcrumbs, token scrubbing and testing
- [API reference](https://pub.dev/documentation/magic_sentry/latest/)
- [llms.txt](llms.txt) and the [agent skill](skills/magic-sentry/SKILL.md) for AI coding agents: `npx skills add anilcancakir/magic_sentry`
- [Changelog](CHANGELOG.md)
- [Report an issue](https://github.com/anilcancakir/magic_sentry/issues)
- [Security policy](SECURITY.md)

## License

MIT, see [LICENSE](LICENSE). Built by [Anılcan Çakır](https://anilcancakir.com).

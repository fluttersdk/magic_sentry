# Testing

Test code that uses `magic_sentry`: nothing to set up without a DSN, and a placeholder DSN when you need to read the scope.

- [Quick Reference](#quick-reference)
- [Without a DSN](#without-a-dsn)
- [Reading the Scope](#reading-the-scope)
- [Pure Members](#pure-members)
- [A Spy Network Driver](#a-spy-network-driver)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| You want to check | Use |
|:------------------|:----|
| Your app boots with the provider registered | Nothing: `Sentry.isEnabled` is `false`, so `boot()` returns early |
| Which user Sentry holds | `Sentry.init` with a placeholder DSN, then `Sentry.configureScope` |
| Whether a status becomes an event | `SentryNetworkInterceptor.dispositionFor(status)` |
| How an endpoint groups | `SentryNetworkInterceptor.normalizeEndpoint(url)` |
| What a hook masks | `SentryTokenScrubber.beforeSend`, `beforeBreadcrumb` and the others, after registering routes |
| What an event becomes | `EventBreadcrumbs.breadcrumbFor(event)` |

No mocking library is needed: the package follows Magic's convention of faking through contract inheritance.

<a name="without-a-dsn"></a>
## Without a DSN

With no `SENTRY_DSN` the SDK is inert, so a widget test that boots the app with `SentryServiceProvider` registered runs as if the package were absent. Do not call `Sentry.init` just to silence it.

<a name="reading-the-scope"></a>
## Reading the Scope

`Sentry.configureScope` is a no-op while the SDK is off, so a test that reads the scope user needs a bound hub. A placeholder DSN is enough because nothing here sends an event:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  setUp(() async {
    MagicApp.reset();
    Magic.flush();
    await Sentry.init(
      (options) => options.dsn = 'https://public@o0.ingest.sentry.io/0',
    );
  });

  tearDown(() async {
    Auth.unfake();
    await Sentry.close();
  });

  test('the scope starts with no user', () async {
    SentryUser? user;

    await Sentry.configureScope((scope) => user = scope.user);

    expect(user, isNull);
  });
}
```

Fake the auth state with `Auth.fake`, call `SentryUserContext.install()`, and read the scope the same way. Undo it in `tearDown` with `Auth.unfake()` and `Sentry.close()`.

<a name="pure-members"></a>
## Pure Members

Most of the package is plain functions you can call with no hub:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_sentry/magic_sentry.dart';

void main() {
  test('a server fault earns an issue and a 404 does not', () {
    expect(
      SentryNetworkInterceptor.dispositionFor(503),
      SentryHttpDisposition.event,
    );
    expect(
      SentryNetworkInterceptor.dispositionFor(404),
      SentryHttpDisposition.breadcrumb,
    );
  });

  test('numeric ids collapse so one endpoint is one issue', () {
    expect(
      SentryNetworkInterceptor.normalizeEndpoint('/monitors/123/checks?page=2'),
      '/monitors/{id}/checks',
    );
  });
}
```

`SentryUserContext.userFor(user)` answers the Sentry user for a model, or `null`. The scrubber's route rule reads `MagicRouter.instance.allRoutes`, so register the routes first and reset them in `tearDown`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_sentry/magic_sentry.dart';

void main() {
  setUp(() {
    MagicRouter.reset();
    MagicRoute.page('/invitations/:token/accept', () => const SizedBox());
  });

  tearDown(MagicRouter.reset);

  test('a route-bound token segment is masked', () {
    expect(
      SentryTokenScrubber.scrubApiUrl('/invitations/abc123/accept'),
      '/invitations/[Filtered]/accept',
    );
  });
}
```

<a name="a-spy-network-driver"></a>
## A Spy Network Driver

To assert what the provider wires, bind a `NetworkDriver` that records `addInterceptor` and leaves every other member unimplemented, then boot the provider and check the recorded list for a `SentryNetworkInterceptor`. `SentryNetworkInterceptor.reportedFailures` is a static set that survives between tests, so clear it in `setUp`.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Reading the scope with the SDK off | Call `Sentry.init` with a placeholder DSN first; `configureScope` is a no-op otherwise |
| Leaving a hub bound after a test | `await Sentry.close()` in `tearDown`, and `Auth.unfake()` |
| A repeat failure turning into a breadcrumb in the next test | `SentryNetworkInterceptor.reportedFailures.clear()` in `setUp` |
| A scrubber test that ignores routes | Register them with `MagicRoute.page` and call `MagicRouter.reset()` in `tearDown` |

<a name="related-documentation"></a>
## Related Documentation

- [User Context](../basics/user-context.md): the scope user a test reads.
- [HTTP Reporting](../basics/http-reporting.md): `reportedFailures` and the disposition rules.
- [Token Scrubbing](token-scrubbing.md): the hooks and their rules.

---
paths:
  - "lib/**/*.dart"
---

# Flutter / Dart Stack

- Dart >=3.6.0, Flutter >=3.27.0: use modern patterns (records, switch expressions, class modifiers such as `abstract final` for an all-static helper, strict null safety)
- Import order: dart stdlib → flutter → `package:magic/magic.dart` → `package:sentry_flutter/...` / `package:sentry_dio/...` → relative imports
- Shape: a zone-wrapped boot helper (`MagicSentry.run`) plus one `ServiceProvider`; there is no Manager/Driver/Handler chain, because there is only one transport, Sentry's own
- Boot order is load-bearing: `MagicSentry.run` starts Sentry BEFORE `Magic.init`, so nothing it reaches may read `Config`; the published `lib/config/sentry.dart` reads `.env` through `Env` directly and is not a magic config factory
- Every integration gates on `Sentry.isEnabled` and degrades to a no-op; an empty `SENTRY_DSN` must never throw
- `SentryServiceProvider.register()` binds nothing; `boot()` wires existing services (the network driver, `Auth.stateNotifier`, `MagicRouter`, `Event.listenAny`)
- Optional or absent services: resolve inside a narrow `try`, and ALWAYS report the failure (`Log.warning` when `Magic.bound('log')`, `debugPrint` otherwise); never swallow it, never let it fail the host's boot
- HTTP reporting has one owner: `sentry_dio`'s `addSentry()` runs with `captureFailedRequests: false`, and `SentryNetworkInterceptor` alone decides event vs breadcrumb
- Privacy defaults are hardcoded, not configurable: `sendDefaultPii` and session replay stay off; an app that wants them sets them in its own `configure` callback
- Stay generic: no app model, team, or tag of this package's own. App-specific data arrives through a callback (`userId`, `userEmail`, `userExtras`) or an event implementing magic's `ReportsBreadcrumb`
- Register a listener idempotently: a second `boot()` in the same isolate (a test suite) removes the previous `Event.listenAny` listener before adding one, and `SentryUserContext.install()` adds no second `Auth.stateNotifier` listener
- Barrel export: `lib/magic_sentry.dart` exports every `lib/src/` file and NO config names; `configureSentry` and its env constants live only in the consumer's published copy of `assets/stubs/install/sentry_config.stub`
- `analysis_options.yaml` uses `package:flutter_lints/flutter.yaml`: zero warnings required

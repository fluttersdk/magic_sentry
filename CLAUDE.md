# Magic Sentry Plugin

Sentry error and performance monitoring for the Magic Framework.

**Version:** 0.0.1 · **Dart:** >=3.6.0 · **Flutter:** >=3.27.0

## Commands

**Host-dispatched via `fluttersdk_artisan`'s generic manifest installer**, no
package-specific CLI provider:

| Command | Description |
|---------|-------------|
| `flutter test --coverage` | Run all tests with coverage |
| `flutter analyze --no-fatal-infos` | Static analysis |
| `dart format .` | Format all code |
| `dart run <app>:artisan plugin:install magic_sentry` | Publish `lib/config/sentry.dart` and inject `SentryServiceProvider` into the consumer's `lib/config/app.dart` |

## Architecture

**Pattern**: zone-wrapped boot helper + ServiceProvider, no Driver/Handler chain (there is only one transport, Sentry's own).

```
lib/
├── magic_sentry.dart          # Barrel export
└── src/
    ├── magic_sentry.dart               # MagicSentry.run + error widget breadcrumb
    ├── sentry_service_provider.dart    # SentryServiceProvider<T>: wires boot()
    ├── sentry_network_interceptor.dart # MagicNetworkInterceptor -> Sentry events/breadcrumbs
    └── sentry_user_context.dart        # Auth.stateNotifier -> Sentry scope user
install.yaml                   # Plugin manifest: config publish, provider injection
assets/stubs/install/sentry_config.stub  # configureSentry, published to a consumer's
                                          # own lib/config/sentry.dart
```

**The barrel exports no config.** `configureSentry`/`sentryDsn`/`sentryEnabled`
and the env key constants live ONLY in the file `plugin:install` publishes into
a consumer app (`lib/config/sentry.dart`, generated from the stub above); the
package itself carries no copy. A package-side export of those same names
would collide with the consumer's own `import 'config/sentry.dart'` the moment
both are imported together, which is exactly what the documented `main()`
does, and `configureSentry` would become an ambiguous import that never
compiles.

**Why the config is not a magic config factory.** `MagicSentry.run` has to start
Sentry BEFORE `Magic.init` runs, so a build failure during boot is reported
too. At that point `Config` (magic's config repository) is not loaded, so
`configureSentry` reads `.env` directly through `Env`, never through
`Config.get`. `install.yaml` therefore has no `magic.config_factory` key,
unlike a plugin (e.g. `magic_deeplink`) whose config folds into
`Magic.init(configFactories: [...])`.

**Data flow:** `main()` calls `MagicSentry.run(configure: configureSentry,
appRunner: _boot)` → one zone opens (`runZonedGuarded`) → `WidgetsFlutterBinding
.ensureInitialized()` → `Env.load()` → `SentryFlutter.init(configure,
appRunner: _boot)` → `_boot` runs `Magic.init(...)` then `runApp(...)` →
`SentryServiceProvider.boot()` (registered like any other provider) wires the
network interceptor, the user context, and the navigator observer, all gated
on `Sentry.isEnabled`.

**User reporting is opt-in and generic.** This package has no model of its
own and never invents a "team" concept: `SentryServiceProvider<T>` takes
`userId`/`userEmail`/`userExtras` callbacks over the host app's own
`Authenticatable` model `T`; `userId` alone turns reporting on (email is
optional). Leave `userId` out to skip user reporting; the network interceptor
and navigator observer still wire up.

## Post-Change Checklist

After ANY source code change, sync **before committing**:

1. **`CHANGELOG.md`**: Add entry under `[Unreleased]` section
2. **`README.md`**: Update if features, API, or usage changes
3. **`doc/`**: Update relevant documentation files

## Development Flow (TDD)

Every feature, fix, or refactor must go through the red-green-refactor cycle:

1. **Red**: Write a failing test that describes the expected behavior
2. **Green**: Write the minimum code to make the test pass
3. **Refactor**: Clean up while keeping tests green

**Rules:**
- No production code without a failing test first
- Run `flutter test` after every change: all tests must stay green
- Run `dart analyze` after every change: zero warnings, zero errors
- Run `dart format .` before committing: zero formatting issues

## Testing

- Mock via contract inheritance (no mockito): a `NetworkDriver` test double
  `implements NetworkDriver` and throws `UnimplementedError` on members the
  test does not exercise, rather than a generated mock.
- `MagicApp.reset(); Magic.flush();` in `setUp`, the house pattern also used
  by `magic` itself, so a previous test's singleton never leaks into the next.
- `MagicRouter.reset()` around any test that calls `addObserver`: it is a
  process-global singleton with no per-test isolation otherwise.
- A test that observes Sentry's scope (the user, a tag, a breadcrumb) calls
  `Sentry.init` with a syntactically valid but unreachable DSN first
  (`https://public@o0.ingest.sentry.io/0`); nothing in this package's tests
  ever sends a real event, so no network call happens regardless.

## Key Gotchas

| Mistake | Fix |
|---------|-----|
| Reading `sendDefaultPii`/session replay from `.env` | Never do this; both stay hardcoded off in `configureSentry`. An app that wants either overrides its own `configure` callback explicitly |
| `sentry_dio`'s `addSentry()` AND `SentryNetworkInterceptor` both capturing failed requests | `SentryServiceProvider` disables `captureFailedRequests` on `addSentry()`; `SentryNetworkInterceptor` is the only layer that decides event vs breadcrumb |
| Calling `MagicRouter.instance.addObserver` after `routerConfig` was built | Register `SentryServiceProvider` in `lib/config/app.dart`'s `providers` list, which boots before any route is built |
| A guarded network/log call throwing anyway | `Magic.bound('log')`/`try`/`catch` around `app.make<NetworkDriver>('network')`, matching magic_deeplink's pattern for an optional dependency that must not take the whole boot down |
| Team logic, tags, or breadcrumbs specific to one app | Does not belong here; use `SentryServiceProvider`'s `userExtras` callback instead |

## Skills & Extensions

- `fluttersdk:magic-framework`: Magic Framework patterns: facades, service providers, IoC, Eloquent ORM. Use for ANY code touching Magic APIs.

## CI

- `ci.yml`: push/PR → `flutter pub get` → `flutter analyze --no-fatal-infos` → `dart format --set-exit-if-changed` → `flutter test --coverage` → codecov upload

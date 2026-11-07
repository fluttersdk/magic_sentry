# Magic Sentry Plugin

Sentry error and performance monitoring for the Magic Framework.

**Version:** 0.0.6 · **Dart:** >=3.6.0 · **Flutter:** >=3.27.0

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
    ├── event_breadcrumbs.dart          # ReportsBreadcrumb event -> Sentry breadcrumb
    ├── magic_sentry.dart               # MagicSentry.run + error widget breadcrumb
    ├── sentry_service_provider.dart    # SentryServiceProvider<T>: wires boot()
    ├── sentry_network_interceptor.dart # MagicNetworkInterceptor -> Sentry events/breadcrumbs
    ├── sentry_token_scrubber.dart      # beforeSend/Transaction/Breadcrumb/SendLog: masks URL-borne tokens
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
appRunner: _boot)` → one zone opens (`runZonedGuarded`) →
`SentryWidgetsFlutterBinding.ensureInitialized()` (frame tracking disables
itself on any other binding, and `SentryFlutter.init` keeps one that exists) →
`Env.load()` → `SentryFlutter.init(configure, appRunner: _boot)` → `_boot` runs `Magic.init(...)` then `runApp(...)` →
`SentryServiceProvider.boot()` (registered like any other provider) wires the
network interceptor, the user context, the event breadcrumb listener
(`Event.listenAny` into `EventBreadcrumbs.breadcrumbFor`) and the navigator
observer, all gated on `Sentry.isEnabled`.

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
4. **`../magic/skills/magic-framework/references/plugin-sentry.md`**: the agent-facing reference lives in the `magic` repo, not here (`.pubignore` keeps this `CLAUDE.md` and `.claude/` out of the published archive). Update it when the public API moves, and move its first-line stamp at release

## Development Flow (TDD)

Red, green, refactor for every feature, fix or refactor: no production code
without a failing test first. After every change `flutter test` stays green
and `dart analyze` reports zero warnings and errors; run `dart format .`
before committing.

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
- `publish.yml`: a bare `X.Y.Z` tag → validate (analyze, format, test) → OIDC publish to pub.dev. 0.0.1 was uploaded by hand, since OIDC cannot create a package; every later version publishes from its tag once automated publishing is enabled on the package's pub.dev admin page
- `dependabot-auto-merge.yml`: arms auto-merge for GitHub Actions minor and patch bumps only
- Default branch is `main`. Release: `release/X.Y.Z` branch, `chore(release): X.Y.Z` PR, tag the merge commit (`/release` walks it)

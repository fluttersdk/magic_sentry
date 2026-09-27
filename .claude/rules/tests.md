---
paths:
  - "test/**/*.dart"
---

# Testing Domain

- Mock via contract inheritance (no mockito): a `NetworkDriver` double `implements NetworkDriver`, records what the provider hands it (`addInterceptor`), and throws `UnimplementedError` on every member the test does not exercise
- `MagicApp.reset(); Magic.flush();` in `setUp`, the house pattern `magic` itself uses, so one test's container bindings never reach the next
- `MagicRouter.reset()` around any test that boots `SentryServiceProvider`: `boot()` calls `MagicRouter.instance.addObserver`, and the router is a process-global singleton with no per-test isolation
- A test that reads Sentry's scope (the user, a tag, a breadcrumb) calls `Sentry.init` first with a syntactically valid, unreachable DSN (`https://public@o0.ingest.sentry.io/0`); nothing here ever sends a real event, and `boot()` is a no-op until `Sentry.isEnabled`
- `SentryServiceProvider` keeps the event-breadcrumb remover in a static field so a second boot in one isolate does not double-register; a test that boots twice asserts ONE breadcrumb per dispatch
- The pure mappers are tested without a hub: `EventBreadcrumbs.breadcrumbFor` and `SentryUserContext`'s `userFor` are asserted directly, never through a sent event
- Test files sit flat under `test/`, one per `lib/src/` file (`sentry_network_interceptor_test.dart` for `sentry_network_interceptor.dart`)
- Import through the barrel, `package:magic_sentry/magic_sentry.dart`, as the existing suites do; the barrel exports every `lib/src/` file
- A test user is a `Model with Authenticatable` whose `id` getter returns a `String`, since `SentryServiceProvider<T extends Model>` takes `String Function(T)` for `userId`
- Use `group()` for logical grouping by feature/scenario

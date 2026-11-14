# User Context

`SentryUserContext<T>` keeps Sentry's scope user in step with `Auth.stateNotifier`, so every event says who hit it.

- [Quick Reference](#quick-reference)
- [Why the Auth State Drives It](#why-the-auth-state-drives-it)
- [Extras](#extras)
- [Using It Without the Provider](#using-it-without-the-provider)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

Pass the extractors to the provider and user reporting is on:

```dart
import 'package:magic_sentry/magic_sentry.dart';

import '../app/models/user.dart';

// The entry in the providers list of lib/config/app.dart; User is your app's model.
final List<Object> providers = [
  (app) => SentryServiceProvider<User>(
    app,
    userId: (user) => user.id?.toString() ?? '',
    userEmail: (user) => user.email,
    userExtras: (user) => {'plan': user.plan},
  ),
];
```

| Callback | Runs | Result |
|:---------|:-----|:-------|
| `userId` | On every auth state change with a signed-in user | The Sentry user id. An empty string counts as nobody |
| `userEmail` | Only for a user with a non-empty id | The email, or none when it is null or empty |
| `userExtras` | Only while a user is reported | Scope tags; each call replaces the keys of the previous one |

`T` is the host app's own `Authenticatable` model. The package has no user model, team or tag of its own, and stays that way: app-specific data arrives through these callbacks.

<a name="why-the-auth-state-drives-it"></a>
## Why the Auth State Drives It

`install()` subscribes to `Auth.stateNotifier`, which fires on login, logout, a session restored at boot and, in an app with teams, a team switch. Doing it there rather than at each call site keeps a future one correct for free, and it guarantees the logout case: a scope that keeps the previous user would file the next visitor's errors under the person who signed out, which is worse than no user at all. So `apply()` sets the user to `null` explicitly on sign-out.

`install()` also applies the current state at once. `Auth.restore()` usually runs during boot, so a user is often signed in by the time this installs, and waiting for the next change would leave the whole first session anonymous.

<a name="extras"></a>
## Extras

`userExtras` returns a `Map<String, String>` of scope tags. Its keys replace whatever the previous call set, and a sign-out clears them, so a team switch carries the new value without leaking the old one. Read straight off the model; the callbacks run on every auth change, so no network call and no side effect.

<a name="using-it-without-the-provider"></a>
## Using It Without the Provider

Construct the context yourself only when you wire Sentry outside `SentryServiceProvider`:

```dart
import 'package:magic_sentry/magic_sentry.dart';

import '../app/models/user.dart';

void followAuth() {
  SentryUserContext<User>(
    id: (user) => user.id?.toString() ?? '',
    email: (user) => user.email,
    extras: (user) => {'plan': user.plan},
  ).install();
}
```

Calling `install()` twice on the same instance adds no second listener. The context compares the notifier by identity, so it also resubscribes when `Auth.stateNotifier` itself changes, as it does after a test fakes a new guard.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Returning `user.id` as it is | `Model.id` is `dynamic` and often an `int`, which throws when the context installs; return `user.id?.toString() ?? ''` |
| Passing `userEmail` without `userId` | Nothing is reported; `userId` is what turns user reporting on |
| Doing a request or a lookup inside `userId` or `userEmail` | They run on every auth change; read straight off the model |
| An `id` that is empty for a signed-out visitor | That is fine: an empty id means nobody, so no stale user is kept |
| Adding an app concept such as a team to this package | Return it from `userExtras` instead |

<a name="related-documentation"></a>
## Related Documentation

- [Boot and the Provider](boot-and-provider.md): where `install()` is called.
- [Testing](../guides/testing.md): reading the scope user in a test.

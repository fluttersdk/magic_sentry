# Token Scrubbing

`SentryTokenScrubber` masks URL-borne tokens in everything Sentry is about to send, and `MagicSentry.run` installs it for you.

- [Quick Reference](#quick-reference)
- [Why It Exists](#why-it-exists)
- [The Three Rules](#the-three-rules)
- [What It Covers](#what-it-covers)
- [Failing Closed](#failing-closed)
- [Your Own Hooks](#your-own-hooks)
- [Limits](#limits)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Hook | Masks |
|:-----|:------|
| `beforeSend` | An event: `request.url`, `queryString`, `fragment`, the transaction name, `contexts.trace`, exception values and the message |
| `beforeSendTransaction` | Everything `beforeSend` covers, plus every span's description and data (apps on `SentryTraceLifecycle.static`) |
| `beforeSendSpan` | A streamed span: its name and every string or string-array attribute (the `sentry_flutter` 10 default) |
| `beforeBreadcrumb` | A breadcrumb's `message` and every string in its `data`, plus the `url` of an `http` one |
| `beforeSendLog` | A structured log (`Sentry.logger`): its `body` and every string or string-array attribute |

All of them are static members of `SentryTokenScrubber`. `MagicSentry.run` calls `SentryTokenScrubber.install(options)` after your `configure` returns, so there is nothing to do.

<a name="why-it-exists"></a>
## Why It Exists

A Magic route such as `/invitations/:token/accept` puts a credential in the path, and a reset link puts one in the query. On web the SDK copies `window.location` into `request.url` and the pathname into the transaction name, and `sentry_dio` keeps the API path on every breadcrumb and span. A token reaches Sentry through half a dozen fields nobody thinks of as sensitive.

<a name="the-three-rules"></a>
## The Three Rules

Applied in this order:

| Rule | What becomes `[Filtered]` or `{token}` |
|:-----|:---------------------------------------|
| Query values | The value of a `key=value` pair whose key contains `token`, `password`, `secret`, `signature`, `credential` or `api_key`, in any case, in the query or in a fragment that opens with a pair (`#access_token=...`). The key and every other pair stay |
| Route-bound segments | A path segment sitting where a registered Magic route has a param whose name contains `token`. Routes come from `MagicRouter.instance.allRoutes`, so routes inside `MagicRoute.group(layout: ...)` count |
| Opaque API segments | On an `http` breadcrumb or span URL, any path segment of 32 or more `[A-Za-z0-9_-]` characters becomes `{token}`. A UUID is exempt because it is an id, not a credential |

The interceptor's own events and fingerprints go further and collapse numeric and UUID ids to `{id}` and drop the query, through `SentryTokenScrubber.scrubApiUrl`.

<a name="what-it-covers"></a>
## What It Covers

Every hook only masks and never drops: an event, breadcrumb or log the scrubber does not recognise passes through unchanged. Numeric ids and the `email` query key are left alone on purpose, since masking them would blind debugging without protecting a credential. A hash-routed URL (`https://host/#/invitations/<token>/accept`) is covered.

<a name="failing-closed"></a>
## Failing Closed

A throwing hook is no place to fail. `sentry_flutter` 10 catches it and drops the event, breadcrumb or log, but sends a streamed span as it was, half scrubbed, and nothing promises another SDK version would not do the same for the rest. So when scrubbing itself throws, the scrubber replaces every field it would have covered with `[Filtered]` and still returns the event. A scrubber bug costs you detail, never a token and never the report.

<a name="your-own-hooks"></a>
## Your Own Hooks

The scrubber runs first and hands its result to your hook, so your hook can drop or rewrite but never sees a raw token. Set app hooks inside `configure`:

```dart
import 'package:sentry_flutter/sentry_flutter.dart';

void configure(SentryFlutterOptions options) {
  options.beforeSend = (SentryEvent event, Hint hint) {
    // Already masked by SentryTokenScrubber; return null here to drop it.
    return event;
  };
}
```

A hook assigned after `SentryFlutter.init` replaces the scrubber, which is the one way to turn it off by accident.

<a name="limits"></a>
## Limits

- A transaction's deprecated `extra` map is not scrubbed. The same data written with `setData` also lands in `contexts.trace.data`, which is, but keep tokens out of transaction data.
- Only what a route or a key names is masked. A secret in a path segment shorter than 32 characters on a route with no `token` param is not recognised.
- `breadcrumbData` from your own events is yours to whitelist; the scrubber is a net under it.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Assigning a hook after `SentryFlutter.init` | Assign it inside `configure`, so the scrubber wraps it |
| Naming a route param `:code` or `:hash` for a credential | Name it with `token` in it (`:resetToken`), or the route rule does not see it |
| Calling `normalizeEndpoint` before sending a URL | It collapses ids only; use `SentryTokenScrubber.scrubApiUrl` |
| Calling the hooks yourself in a test without routes | Register the routes first; the route rule reads `MagicRouter.instance.allRoutes` |

<a name="related-documentation"></a>
## Related Documentation

- [Boot and the Provider](../basics/boot-and-provider.md): where `install` is called.
- [HTTP Reporting](../basics/http-reporting.md): the endpoint the interceptor reports.
- [Testing](testing.md): registering routes before calling a hook.

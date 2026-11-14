# HTTP Reporting

`SentryNetworkInterceptor` turns the failures Magic's `Http` facade returns as values into Sentry events and breadcrumbs.

- [Quick Reference](#quick-reference)
- [Why It Exists](#why-it-exists)
- [Events and Breadcrumbs](#events-and-breadcrumbs)
- [Grouping](#grouping)
- [Repeats](#repeats)
- [Double Reporting](#double-reporting)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

The provider registers the interceptor for you. Nothing to call:

| Status | What Sentry gets |
|:-------|:-----------------|
| `0` (no response: timeout, refused connection, CORS rejection on web) | An event |
| `500` and above | An event |
| Anything else, such as `401`, `404`, `422`, `429` | A `warning` breadcrumb on whatever fails next |

<a name="why-it-exists"></a>
## Why It Exists

Magic's `Http` facade never throws. Every call returns a `MagicResponse` and the caller reads `response.successful`, so a failure is a value, not an exception. A global error handler sees none of them, and an app's own habit is usually to log the failure and return. Without this interceptor Sentry would report almost nothing about the surface that breaks most.

The interceptor only reports. It returns the `MagicError` it was given, so observability can never change the outcome of a request.

<a name="events-and-breadcrumbs"></a>
## Events and Breadcrumbs

A 4xx is usually the product working: `401` is an expired session, `422` a form filled in wrong, `404` a record someone deleted. Filing those as issues turns the inbox into one nobody opens, so they become breadcrumbs that give context to the next real failure.

An event carries:

| Field | Value |
|:------|:------|
| Level and logger | `error`, `http` |
| Message | `METHOD endpoint failed with STATUS` |
| Fingerprint | `['http', method, endpoint, 'STATUS']` |
| Context `http_failure` | `method`, `endpoint`, `status_code`, and `transport_message` when there is one |

There is no request body and no header in it. An app that turns `sendDefaultPii` on opts into that risk itself.

<a name="grouping"></a>
## Grouping

The fingerprint carries a normalised endpoint, because a raw path holds a record id and would open one issue per record. `SentryNetworkInterceptor.normalizeEndpoint` drops the query and turns a numeric or UUID segment into `{id}`, so `/monitors/42/checks` and `/monitors/43/checks` are one issue. The status comes last in the fingerprint, which keeps one endpoint's `500` and `502` apart: they usually have different causes.

What reaches Sentry goes through `SentryTokenScrubber.scrubApiUrl`, which runs `normalizeEndpoint` first and then masks what is left, so a failed invitation call groups under `/api/v1/invitations/{token}/accept` instead of carrying the token.

<a name="repeats"></a>
## Repeats

One event per distinct `METHOD endpoint status` per session; the next occurrence becomes an `error` breadcrumb marked `(repeat)`. Without that, a client polling a dead endpoint is a flood source: a one-hour outage across a few hundred open tabs is tens of thousands of identical events, and most Sentry plans bill by event count. The repeat breadcrumbs still show the retry pattern to whoever opens the issue.

The set is `SentryNetworkInterceptor.reportedFailures`. It is process-wide and not time-windowed: a web session is a tab, so it ends with the page, and a returning user reports the failure again.

<a name="double-reporting"></a>
## Double Reporting

`sentry_dio` can capture failed requests on its own. The provider turns that off (`captureFailedRequests: false`) for two reasons: its events are raised inside the SDK adapter, so their stack trace points at the SDK instead of your call site, and they cannot carry the endpoint fingerprint above. Leaving it on would also report every failure twice. The provider still adds `sentry_dio`'s `addSentry()`, which contributes an HTTP breadcrumb and a span per request.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Turning `captureFailedRequests` back on in your own Dio setup | Leave it off; `SentryNetworkInterceptor` is the one layer that decides event or breadcrumb |
| Expecting a `404` or `422` to open an issue | They are breadcrumbs by design; look at the breadcrumbs of the next event |
| Expecting every failed call to arrive as an event | Only the first of a repeated failure per session does; the rest are `(repeat)` breadcrumbs |
| Calling `normalizeEndpoint` to make a URL safe to send | It collapses ids only and a token in the path survives it; use `SentryTokenScrubber.scrubApiUrl` |

<a name="related-documentation"></a>
## Related Documentation

- [Boot and the Provider](boot-and-provider.md): where the interceptor is wired.
- [Token Scrubbing](../guides/token-scrubbing.md): the masking `scrubApiUrl` applies.
- [Testing](../guides/testing.md): clearing `reportedFailures` between tests.

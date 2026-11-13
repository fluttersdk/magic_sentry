# Event Breadcrumbs

Any Magic event that implements `ReportsBreadcrumb` becomes a Sentry breadcrumb, with no extra wiring.

- [Quick Reference](#quick-reference)
- [How It Works](#how-it-works)
- [What Goes in the Data](#what-goes-in-the-data)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

Make the event opt in; the provider's wildcard listener does the rest:

```dart
import 'package:magic/magic.dart';

class InvoicePaid extends MagicEvent implements ReportsBreadcrumb {
  InvoicePaid(this.invoiceId);

  final String invoiceId;

  @override
  String get breadcrumbCategory => 'billing';

  @override
  String get breadcrumbMessage => 'Invoice paid';

  @override
  Map<String, Object?> get breadcrumbData => {'invoice_id': invoiceId};
}
```

Dispatching `InvoicePaid` adds an `info` breadcrumb with that category, message and data to the next event Sentry sends.

<a name="how-it-works"></a>
## How It Works

`SentryServiceProvider.boot()` registers one listener through `Event.listenAny`, which runs on every dispatch. For each event it asks `EventBreadcrumbs.breadcrumbFor`, which answers `null` unless the event implements `ReportsBreadcrumb`, and adds what it returns with `Sentry.addBreadcrumb`. This package does not know which events exist; the event opts in.

`ReportsBreadcrumb` first shipped in Magic 0.0.22, together with `Event.listenAny`. A second `boot()` in the same isolate removes the previous listener before adding one, so a test suite that boots the provider again does not register it twice. `magic_deeplink`'s `DeeplinkOpened` and `DeeplinkNavigating` already implement the contract and carry only the matched route pattern.

<a name="what-goes-in-the-data"></a>
## What Goes in the Data

`breadcrumbData` is a whitelist the event author curates. `breadcrumbFor` copies it as it is and never adds or drops a key. The breadcrumb also passes through `SentryTokenScrubber.beforeBreadcrumb`, which masks tokens that look like tokens, but that is a net and not a licence: keep tokens, emails and query values out of the map.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Expecting a plain `MagicEvent` to leave a breadcrumb | Add `implements ReportsBreadcrumb`; events that do not opt in are skipped |
| Putting a secret in `breadcrumbData` | It is sent as written apart from token masking; whitelist only what is safe to store |
| Expecting a breadcrumb without a DSN | `boot()` returns early when `Sentry.isEnabled` is false, so no listener is registered |

<a name="related-documentation"></a>
## Related Documentation

- [Boot and the Provider](boot-and-provider.md): where the listener is registered.
- [Token Scrubbing](../guides/token-scrubbing.md): the masking a breadcrumb passes through.

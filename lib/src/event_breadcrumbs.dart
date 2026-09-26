import 'package:magic/magic.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Translates a dispatched [MagicEvent] into a Sentry [Breadcrumb], for
/// [SentryServiceProvider]'s wildcard listener.
///
/// Pure and testable with no Sentry hub, the same shape as
/// `SentryUserContext.userFor`: an event opts in by implementing
/// [ReportsBreadcrumb], and nothing else (this package, the listener, any
/// other event) has to know that contract exists.
class EventBreadcrumbs {
  // Prevent instantiation: every member is static.
  EventBreadcrumbs._();

  /// The breadcrumb for [event], or null when [event] does not implement
  /// [ReportsBreadcrumb].
  ///
  /// [Breadcrumb.data] carries exactly [ReportsBreadcrumb.breadcrumbData],
  /// which is a whitelist the event author already curated; this never adds
  /// or drops a key from it.
  static Breadcrumb? breadcrumbFor(MagicEvent event) {
    if (event is! ReportsBreadcrumb) {
      return null;
    }

    // Explicit cast rather than relying on flow promotion: [MagicEvent] and
    // [ReportsBreadcrumb] are unrelated types (an event opts in via
    // `implements`, not inheritance), and Dart only promotes a variable to a
    // subtype of its declared type.
    final ReportsBreadcrumb crumb = event as ReportsBreadcrumb;

    return Breadcrumb(
      category: crumb.breadcrumbCategory,
      message: crumb.breadcrumbMessage,
      data: crumb.breadcrumbData,
      level: SentryLevel.info,
    );
  }
}

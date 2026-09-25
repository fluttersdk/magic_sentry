import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:magic/magic.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// What a failed HTTP call becomes in Sentry.
enum SentryHttpDisposition {
  /// An issue someone should look at.
  event,

  /// Context attached to whatever fails next, with no issue of its own.
  breadcrumb,
}

/// Reports HTTP failures that magic's `Http` facade would otherwise swallow.
///
/// WHY THIS EXISTS AT ALL. magic's `Http` facade never throws: every call
/// returns a `MagicResponse` and the caller reads `response.successful`, so a
/// failure is a VALUE, not an exception. A global error handler therefore sees
/// none of them, and a host app's own habit is usually to log the failure and
/// return quietly. Without this interceptor Sentry reports almost nothing
/// about the surface that actually breaks.
///
/// TWO DECISIONS, both of which a test pins:
///
/// 1. WHAT DESERVES AN ISSUE. A 5xx or a dead connection is a fault. A 4xx is
///    usually the product working correctly: 401 is an expired session, 422 is
///    a form the user filled in wrong, 404 is a record someone else deleted.
///    Filing those as issues is how an inbox becomes one nobody opens, so they
///    become breadcrumbs and provide context for the next real failure instead.
/// 2. HOW IT GROUPS. The fingerprint carries a NORMALISED path, because a raw
///    one contains a record id and would open a separate issue per record.
///    One broken endpoint arriving as a thousand issues looks exactly like a
///    thousand bugs.
///
/// It reports and returns; it never changes the outcome of a request. Wire it
/// in with [SentryServiceProvider], which also disables `sentry_dio`'s own
/// failed-request capture to avoid reporting the same failure twice.
class SentryNetworkInterceptor extends MagicNetworkInterceptor {
  /// Failures already reported this session, as `METHOD /path {status}`.
  ///
  /// Session-scoped rather than time-windowed on purpose: a web session is a
  /// tab, so it ends when the page does, and a returning user reports the
  /// failure again. A timer would need a clock, a test seam and a decision
  /// about what "recently" means, to save an issue that Sentry already groups.
  @visibleForTesting
  static final Set<String> reportedFailures = <String>{};

  /// Report the failure, then hand it back untouched.
  ///
  /// The return value is meaningful to magic: a `MagicResponse` RESOLVES the
  /// failure as a success, anything else lets it continue down the chain. This
  /// returns exactly what it was given, so observability can never change
  /// behaviour.
  ///
  /// Nothing here checks whether Sentry is enabled. It does not need to: with
  /// no DSN the SDK is inert and every call below is a no-op, which is the
  /// state every local run and the whole test suite are in.
  @override
  dynamic onError(MagicError error) {
    final int status = error.statusCode;
    final String method = error.request?.method.toUpperCase() ?? 'UNKNOWN';
    final String endpoint = normalizeEndpoint(error.request?.url ?? 'unknown');

    if (dispositionFor(status) == SentryHttpDisposition.breadcrumb) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          type: 'http',
          category: 'http',
          level: SentryLevel.warning,
          message: '$method $endpoint -> $status',
          data: {
            'method': method,
            'endpoint': endpoint,
            'status_code': status,
          },
        ),
      );

      return error;
    }

    // One issue per distinct failure per session, then breadcrumbs. Without
    // this a client polling any endpoint is a flood source rather than a
    // signal: a one-hour backend outage across a couple of hundred open tabs
    // is tens of thousands of identical events, and most Sentry plans bill by
    // event count with no overage budget.
    //
    // The first occurrence is the one that carries information; the rest are
    // the same fingerprint arriving repeatedly, which Sentry would group into
    // one issue anyway while still billing for each. Their breadcrumbs still
    // show the retry pattern to whoever opens that issue.
    if (!reportedFailures.add('$method $endpoint $status')) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          type: 'http',
          category: 'http',
          level: SentryLevel.error,
          message: '$method $endpoint -> $status (repeat)',
          data: {
            'method': method,
            'endpoint': endpoint,
            'status_code': status,
          },
        ),
      );

      return error;
    }

    Sentry.captureEvent(
      SentryEvent(
        level: SentryLevel.error,
        logger: 'http',
        message: SentryMessage(
          '$method $endpoint failed with $status',
          template: '%s %s failed with %s',
          params: [method, endpoint, status],
        ),
        // The status comes LAST so a single endpoint's 500 and its 502 stay
        // separate issues: they usually have different causes (the app threw
        // vs. the gateway could not reach it).
        fingerprint: ['http', method, endpoint, '$status'],
        // A structured context rather than `extra`, which the SDK deprecated
        // in favour of exactly this. Deliberately no request body and no
        // headers: an app that turns `sendDefaultPii` on is opting into that
        // risk itself, this interceptor does not assume it.
        contexts: Contexts()
          ..['http_failure'] = {
            'method': method,
            'endpoint': endpoint,
            'status_code': status,
            if (error.message != null) 'transport_message': error.message,
          },
      ),
    );

    return error;
  }

  /// Whether a status code is worth an issue or only a breadcrumb.
  ///
  /// [statusCode] is `MagicError.statusCode`, which answers 0 when there is no
  /// response at all. That zero is the most important case in the function: it
  /// is a timeout, a refused connection or a DNS failure, and on web it is also
  /// what a CORS rejection looks like.
  @visibleForTesting
  static SentryHttpDisposition dispositionFor(int statusCode) {
    if (statusCode == 0) {
      return SentryHttpDisposition.event;
    }

    if (statusCode >= 500) {
      return SentryHttpDisposition.event;
    }

    return SentryHttpDisposition.breadcrumb;
  }

  /// Replace identifier segments with `{id}` so one endpoint is one issue.
  ///
  /// [url] is the request path as magic recorded it, which may carry a query
  /// string. The query goes entirely: `?page=3` would otherwise split one
  /// endpoint's failures across every page a user happened to be on.
  @visibleForTesting
  static String normalizeEndpoint(String url) {
    final String path = url.split('?').first;

    return path
        .split('/')
        .map((segment) => _looksLikeIdentifier(segment) ? '{id}' : segment)
        .join('/');
  }

  /// Whether a path segment is an identifier rather than a route name.
  ///
  /// Both numeric and UUID primary keys are covered, and only those two,
  /// since those are the two shapes a magic-backed API issues.
  ///
  /// The UUID pattern is fully anchored rather than a loose "long and hex-ish"
  /// test, because a loose one collapses real route names: `acknowledged` and
  /// `deactivate` are both long, and hex-adjacent enough to fool a sloppy
  /// matcher.
  static bool _looksLikeIdentifier(String segment) {
    if (segment.isEmpty) {
      return false;
    }

    if (RegExp(r'^\d+$').hasMatch(segment)) {
      return true;
    }

    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(segment);
  }
}

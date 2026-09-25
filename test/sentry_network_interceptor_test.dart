import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_sentry/magic_sentry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Locks the two decisions that separate a useful Sentry inbox from an
/// abandoned one.
///
/// magic's HTTP layer never throws: `Http.get()` hands back a
/// `MagicResponse` and the caller reads `response.successful`, so a failure is
/// a VALUE. Nothing reaches Sentry unless this interceptor puts it there,
/// which makes both decisions below load-bearing rather than cosmetic.
///
/// The first is what deserves an issue at all. A 401 is a session that
/// expired and a 422 is a form the user filled in wrong: both are the
/// product working, and filing them as issues is how an inbox becomes
/// something nobody opens. A 500 or a dead connection is the opposite.
///
/// The second is grouping. Sentry groups by fingerprint, and a fingerprint
/// carrying a raw path means `/monitors/<uuid>` opens a NEW issue for every
/// record a caller owns. One broken endpoint would then arrive as a thousand
/// separate issues, which is indistinguishable from a thousand separate bugs.
void main() {
  group('dispositionFor', () {
    test('a dead connection earns an issue', () {
      // `MagicError.statusCode` answers 0 when there is no response at all,
      // which is the shape a timeout or a refused connection arrives in.
      expect(
        SentryNetworkInterceptor.dispositionFor(0),
        SentryHttpDisposition.event,
      );
    });

    test('a server fault earns an issue', () {
      expect(
        SentryNetworkInterceptor.dispositionFor(500),
        SentryHttpDisposition.event,
      );
      expect(
        SentryNetworkInterceptor.dispositionFor(503),
        SentryHttpDisposition.event,
      );
    });

    test('an expected client answer is only a breadcrumb', () {
      for (final status in [400, 401, 403, 404, 409, 422, 429]) {
        expect(
          SentryNetworkInterceptor.dispositionFor(status),
          SentryHttpDisposition.breadcrumb,
          reason:
              '$status is the product working, not a fault to page anyone about.',
        );
      }
    });
  });

  group('normalizeEndpoint', () {
    test('it collapses a numeric id so one endpoint is one issue', () {
      expect(
        SentryNetworkInterceptor.normalizeEndpoint('/monitors/123/checks'),
        '/monitors/{id}/checks',
      );
    });

    test('it collapses a uuid', () {
      expect(
        SentryNetworkInterceptor.normalizeEndpoint(
          '/monitors/9f8e7d6c-5b4a-4321-8765-0fedcba98765/metrics',
        ),
        '/monitors/{id}/metrics',
      );
    });

    test('it leaves a static path alone', () {
      expect(
        SentryNetworkInterceptor.normalizeEndpoint(
            '/dashboard/active-incidents'),
        '/dashboard/active-incidents',
      );
    });

    test('it does not mistake a word for an id', () {
      // A segment being long or hex-ish is not enough; `incidents` must
      // survive.
      expect(
        SentryNetworkInterceptor.normalizeEndpoint('/incidents/acknowledged'),
        '/incidents/acknowledged',
      );
    });

    test('it drops a query string, which would explode grouping', () {
      expect(
        SentryNetworkInterceptor.normalizeEndpoint(
            '/monitors?page=3&per_page=50'),
        '/monitors',
      );
    });
  });

  group('deduplication', () {
    setUp(SentryNetworkInterceptor.reportedFailures.clear);

    test('the same failure is only reported once per session', () {
      // A client that polls, retries, or reconnects turns a single ongoing
      // failure into hundreds of identical reports if nothing deduplicates:
      // Sentry groups them anyway, so the extras cost quota for no new
      // information.
      final interceptor = SentryNetworkInterceptor();
      final error = MagicError(message: 'gateway down');

      interceptor.onError(error);
      interceptor.onError(error);
      interceptor.onError(error);

      expect(SentryNetworkInterceptor.reportedFailures, hasLength(1));
    });

    test('a different endpoint or status is its own report', () {
      final interceptor = SentryNetworkInterceptor();

      interceptor.onError(MagicError(message: 'a'));
      interceptor.onError(
        MagicError(
          message: 'b',
          request: MagicRequest(url: '/monitors', method: 'GET'),
        ),
      );

      expect(SentryNetworkInterceptor.reportedFailures, hasLength(2));
    });
  });

  group('captured events', () {
    setUp(SentryNetworkInterceptor.reportedFailures.clear);

    tearDown(() async {
      if (Sentry.isEnabled) {
        await Sentry.close();
      }
    });

    test('a 500 becomes an event fingerprinted on the normalised endpoint',
        () async {
      SentryEvent? captured;

      await Sentry.init((options) {
        options.dsn = 'https://public@o0.ingest.sentry.io/0';
        // Read the event Sentry would have sent, then block the send: this
        // test proves what gets CAPTURED, never anything reaching a real
        // network.
        options.beforeSend = (event, hint) {
          captured = event;
          return null;
        };
      });

      SentryNetworkInterceptor().onError(
        MagicError(
          message: 'server exploded',
          request: MagicRequest(url: '/monitors/123', method: 'GET'),
          response: MagicResponse(
            data: null,
            statusCode: 500,
            headers: const {},
          ),
        ),
      );

      // `Sentry.captureEvent` runs asynchronously inside the SDK's own hub;
      // the interceptor fires it and returns immediately (see `onError`'s
      // own docs on why: reporting must never change the outcome of a
      // request). Draining the event queue is what lets `beforeSend` run
      // before this test asserts on it.
      await pumpEventQueue();

      expect(captured, isNotNull);
      expect(captured!.fingerprint, ['http', 'GET', '/monitors/{id}', '500']);
    });

    test('a 404 produces no event, only a breadcrumb', () async {
      bool sendAttempted = false;

      await Sentry.init((options) {
        options.dsn = 'https://public@o0.ingest.sentry.io/0';
        options.beforeSend = (event, hint) {
          sendAttempted = true;
          return event;
        };
      });

      SentryNetworkInterceptor().onError(
        MagicError(
          message: 'not found',
          request: MagicRequest(url: '/monitors/123', method: 'GET'),
          response: MagicResponse(
            data: null,
            statusCode: 404,
            headers: const {},
          ),
        ),
      );

      await pumpEventQueue();

      expect(sendAttempted, isFalse);
    });
  });

  group('onError', () {
    setUp(SentryNetworkInterceptor.reportedFailures.clear);

    test('it returns the error untouched so the interceptor chain survives',
        () {
      // magic reads the return value: a `MagicResponse` RESOLVES the failure
      // as a success, anything else lets it continue. Reporting must never
      // change the outcome of a request, so this returns exactly what it was
      // handed.
      final error = MagicError(message: 'boom');

      expect(
        identical(SentryNetworkInterceptor().onError(error), error),
        isTrue,
      );
    });
  });
}

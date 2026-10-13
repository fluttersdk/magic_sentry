import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_sentry/magic_sentry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Locks the invariant that no URL-borne token reaches Sentry.
///
/// A magic route such as `/invitations/:token/accept` puts a credential in
/// the PATH, and a reset link puts one in the QUERY. The SDK on web copies
/// `window.location` into `request.url` and the pathname into the transaction
/// name, and `sentry_dio` keeps the API path on every breadcrumb and span, so
/// each of them has to be masked before it leaves the process.
void main() {
  const String dsn = 'https://public@o0.ingest.sentry.io/0';
  final Hint hint = Hint();

  /// Makes every location scrub throw: the scrubber reads each route's
  /// `fullPath`, so a route whose getter fails is a failure inside the
  /// scrubber itself, which is what the fail-closed tests need.
  void registerThrowingRoute() {
    MagicRouter.instance.addRoute(
      _ThrowingRoute(path: '/boom', handler: () => const SizedBox()),
    );
  }

  setUp(() {
    MagicApp.reset();
    Magic.flush();
    MagicRouter.reset();

    MagicRoute.page('/invitations/:token/accept', () => const SizedBox());
    MagicRoute.page('/monitors/:id', (String id) => const SizedBox());
  });

  tearDown(() async {
    MagicRouter.reset();

    if (Sentry.isEnabled) {
      await Sentry.close();
    }
  });

  group('beforeSend', () {
    test('masks a token bound to a route param in request.url', () {
      final SentryEvent event = SentryEvent(
        request: SentryRequest(
          url: 'https://app.test/invitations/abc123def/accept',
        ),
      );

      final String url =
          SentryTokenScrubber.beforeSend(event, hint).request!.url!;

      expect(url, isNot(contains('abc123def')));
      expect(url, startsWith('https://app.test/invitations/'));
      expect(url, endsWith('/accept'));
    });

    test('masks a token query value and keeps the other keys', () {
      final SentryEvent event = SentryEvent(
        request: SentryRequest(
          url: 'https://app.test/auth/reset-password?token=abc&email=a%40b.c',
        ),
      );

      final String url =
          SentryTokenScrubber.beforeSend(event, hint).request!.url!;

      expect(url, isNot(contains('token=abc')));
      expect(url, contains('email=a%40b.c'));
      expect(url, startsWith('https://app.test/auth/reset-password?token='));
    });

    test('masks every sensitive query key and leaves the rest alone', () {
      final SentryEvent event = SentryEvent(
        request: SentryRequest(
          queryString: 'password=p1&client_secret=s2&X-Amz-Signature=g3'
              '&credential=c4&api_key=k5&access_token=t6&page=3',
        ),
      );

      final String query =
          SentryTokenScrubber.beforeSend(event, hint).request!.queryString!;

      for (final String leaked in ['p1', 's2', 'g3', 'c4', 'k5', 't6']) {
        expect(query, isNot(contains('=$leaked')));
      }
      expect(query, contains('page=3'));
    });

    test('masks a token in the fragment of a hash-routed url', () {
      final SentryEvent event = SentryEvent(
        request: SentryRequest(
          url: 'https://app.test/#/auth/reset-password?token=abc',
          fragment: '/auth/reset-password?token=abc',
        ),
      );

      final SentryRequest request =
          SentryTokenScrubber.beforeSend(event, hint).request!;

      expect(request.url, isNot(contains('token=abc')));
      expect(request.fragment, isNot(contains('token=abc')));
    });

    test('masks the transaction name of an error event', () {
      final SentryEvent event = SentryEvent(
        transaction: '/invitations/abc123def/accept',
      );

      expect(
        SentryTokenScrubber.beforeSend(event, hint).transaction,
        isNot(contains('abc123def')),
      );
    });

    test('masks the trace context data', () {
      final SentryEvent event = SentryEvent(
        contexts: Contexts(
          trace: SentryTraceContext(
            operation: 'navigation',
            traceId: SentryId.newId(),
            spanId: SpanId.newId(),
            description: '/invitations/abc123def/accept',
            data: {'route': '/invitations/abc123def/accept', 'count': 3},
          ),
        ),
      );

      final SentryTraceContext trace =
          SentryTokenScrubber.beforeSend(event, hint).contexts.trace!;

      expect(trace.description, isNot(contains('abc123def')));
      expect(trace.data!['route'], isNot(contains('abc123def')));
      expect(trace.data!['count'], 3);
    });

    test('masks a route-bound token in a hash-routed url', () {
      final SentryEvent event = SentryEvent(
        request: SentryRequest(
          url: 'https://app.test/#/invitations/abc123def/accept',
        ),
      );

      final String url =
          SentryTokenScrubber.beforeSend(event, hint).request!.url!;

      expect(url, isNot(contains('abc123def')));
      expect(url, startsWith('https://app.test/#/invitations/'));
      expect(url, endsWith('/accept'));
    });

    test('masks the location an exception value and a message embed', () {
      final SentryEvent event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'StateError',
            value: 'Bad state at /invitations/abc123def/accept',
          ),
        ],
        message: SentryMessage(
          'failed at /invitations/abc123def/accept',
          template: 'failed at /invitations/abc123def/accept',
        ),
      );

      final SentryEvent scrubbed = SentryTokenScrubber.beforeSend(event, hint);

      expect(scrubbed.exceptions!.single.value, isNot(contains('abc123def')));
      expect(scrubbed.exceptions!.single.value, startsWith('Bad state at '));
      expect(scrubbed.message!.formatted, isNot(contains('abc123def')));
      expect(scrubbed.message!.template, isNot(contains('abc123def')));
    });

    test('fails closed when the scrubber throws, and still returns the event',
        () {
      registerThrowingRoute();

      final SentryEvent event = SentryEvent(
        request: SentryRequest(
          url: 'https://app.test/invitations/abc123def/accept',
          queryString: 'token=abc',
          fragment: '/invitations/abc123def/accept',
        ),
        transaction: '/invitations/abc123def/accept',
        exceptions: [SentryException(type: 'E', value: 'at /x/abc123def')],
        message: SentryMessage('at /x/abc123def'),
      );

      final SentryEvent scrubbed = SentryTokenScrubber.beforeSend(event, hint);
      final String sent = scrubbed.toJson().toString();

      expect(scrubbed, same(event));
      expect(scrubbed.request!.url, '[Filtered]');
      expect(scrubbed.request!.queryString, '[Filtered]');
      expect(scrubbed.request!.fragment, '[Filtered]');
      expect(scrubbed.transaction, '[Filtered]');
      expect(sent, isNot(contains('abc123def')));
    });

    test('masks a token route declared inside a layout group', () {
      MagicRoute.group(
        layout: (Widget child) => child,
        routes: () {
          MagicRoute.page(
              '/team-invites/:token/accept', () => const SizedBox());
        },
      );

      final SentryEvent event = SentryEvent(
        request: SentryRequest(
          url: 'https://app.test/team-invites/abc123def/accept',
        ),
      );

      final String url =
          SentryTokenScrubber.beforeSend(event, hint).request!.url!;

      expect(url, isNot(contains('abc123def')));
      expect(url, endsWith('/accept'));
    });

    test('covers a route registered after the first scrub', () {
      SentryTokenScrubber.beforeSend(
        SentryEvent(transaction: '/warmup'),
        hint,
      );
      MagicRoute.page('/reset/:resetToken', () => const SizedBox());

      final SentryEvent scrubbed = SentryTokenScrubber.beforeSend(
        SentryEvent(transaction: '/reset/abc123def'),
        hint,
      );

      expect(scrubbed.transaction, isNot(contains('abc123def')));
    });

    test('leaves a url with no token untouched', () {
      final SentryEvent event = SentryEvent(
        request: SentryRequest(url: 'https://app.test/monitors/42?page=3'),
        transaction: '/monitors/42',
      );

      final SentryEvent scrubbed = SentryTokenScrubber.beforeSend(event, hint);

      expect(scrubbed.request!.url, 'https://app.test/monitors/42?page=3');
      expect(scrubbed.transaction, '/monitors/42');
    });

    test('never drops the event', () {
      expect(SentryTokenScrubber.beforeSend(SentryEvent(), hint), isNotNull);
    });
  });

  group('beforeBreadcrumb', () {
    test('masks an http breadcrumb url with an opaque path segment', () {
      const String opaque = 'Xq7Lk2Pz9Rt4Wm8Nb3Vc6Yd1Fg5Hj0Ks2Lp';
      final Breadcrumb crumb = Breadcrumb(
        type: 'http',
        category: 'http',
        data: {
          'url': 'https://api.test/api/v1/invitations/$opaque/accept',
          'method': 'POST',
          'status_code': 422,
        },
      );

      final Breadcrumb scrubbed =
          SentryTokenScrubber.beforeBreadcrumb(crumb, hint)!;

      expect(opaque.length, greaterThanOrEqualTo(32));
      expect(scrubbed.data!['url'], isNot(contains(opaque)));
      expect(
        scrubbed.data!['url'],
        'https://api.test/api/v1/invitations/{token}/accept',
      );
      expect(scrubbed.data!['method'], 'POST');
      expect(scrubbed.data!['status_code'], 422);
    });

    test('keeps numeric ids and uuids on a breadcrumb url', () {
      final Breadcrumb crumb = Breadcrumb(
        type: 'http',
        data: {
          'url': 'https://api.test/api/v1/monitors/'
              '123e4567-e89b-12d3-a456-426614174000/checks/9?page=2',
        },
      );

      expect(
        SentryTokenScrubber.beforeBreadcrumb(crumb, hint)!.data!['url'],
        'https://api.test/api/v1/monitors/'
        '123e4567-e89b-12d3-a456-426614174000/checks/9?page=2',
      );
    });

    test('keeps a numeric id and masks an opaque segment of 35 characters', () {
      final Breadcrumb id = Breadcrumb(
        type: 'http',
        data: {'url': 'https://api.test/api/v1/monitors/42?page=2'},
      );
      final Breadcrumb opaque = Breadcrumb(
        type: 'http',
        data: {'url': 'https://api.test/api/v1/reset/${'k' * 35}?page=2'},
      );

      expect(
        SentryTokenScrubber.beforeBreadcrumb(id, hint)!.data!['url'],
        'https://api.test/api/v1/monitors/42?page=2',
      );
      expect(
        SentryTokenScrubber.beforeBreadcrumb(opaque, hint)!.data!['url'],
        'https://api.test/api/v1/reset/{token}?page=2',
      );
    });

    test('masks a token inside a map that is not Map<String, dynamic>', () {
      final Breadcrumb crumb = Breadcrumb(
        type: 'navigation',
        data: {
          'nested': <Object, Object>{
            'route': '/invitations/abc123def/accept',
          },
        },
      );

      final Map<dynamic, dynamic> nested =
          SentryTokenScrubber.beforeBreadcrumb(crumb, hint)!.data!['nested']
              as Map;

      expect(nested['route'], isNot(contains('abc123def')));
    });

    test('fails closed when the scrubber throws, and still returns the crumb',
        () {
      registerThrowingRoute();

      final Breadcrumb crumb = Breadcrumb(
        type: 'http',
        message: 'POST /api/v1/invitations/abc123def/accept',
        data: {
          'url': 'https://api.test/api/v1/invitations/abc123def/accept',
          'status_code': 422,
        },
      );

      final Breadcrumb? scrubbed =
          SentryTokenScrubber.beforeBreadcrumb(crumb, hint);

      expect(scrubbed, same(crumb));
      expect(scrubbed!.message, '[Filtered]');
      expect(scrubbed.data!['url'], '[Filtered]');
      expect(scrubbed.data!['status_code'], 422);
    });

    test('masks the query that sentry_dio keeps beside the url', () {
      final Breadcrumb crumb = Breadcrumb(
        type: 'http',
        data: {
          'url': 'https://api.test/api/v1/auth/reset',
          'http.query': 'token=abc&email=a%40b.c',
        },
      );

      final String query = SentryTokenScrubber.beforeBreadcrumb(crumb, hint)!
          .data!['http.query'] as String;

      expect(query, isNot(contains('token=abc')));
      expect(query, contains('email=a%40b.c'));
    });

    test('masks a route-bound token in a navigation breadcrumb', () {
      final Breadcrumb crumb = Breadcrumb(
        type: 'navigation',
        category: 'navigation',
        message: 'to /invitations/abc123def/accept',
        data: {
          'from': '/home',
          'to': '/invitations/abc123def/accept',
          'nested': {'route': '/invitations/abc123def/accept'},
        },
      );

      final Breadcrumb scrubbed =
          SentryTokenScrubber.beforeBreadcrumb(crumb, hint)!;

      expect(scrubbed.message, isNot(contains('abc123def')));
      expect(scrubbed.data!['to'], isNot(contains('abc123def')));
      expect(scrubbed.data!['from'], '/home');
      expect(
        (scrubbed.data!['nested'] as Map)['route'],
        isNot(contains('abc123def')),
      );
    });

    test('does not treat a long non-http segment as a token', () {
      final Breadcrumb crumb = Breadcrumb(
        category: 'ui.click',
        message: 'tapped /docs/${'a' * 40}',
      );

      expect(
        SentryTokenScrubber.beforeBreadcrumb(crumb, hint)!.message,
        'tapped /docs/${'a' * 40}',
      );
    });

    test('passes a null breadcrumb through', () {
      expect(SentryTokenScrubber.beforeBreadcrumb(null, hint), isNull);
    });
  });

  group('scrubApiUrl', () {
    test('reduces an endpoint: query dropped, ids collapsed', () {
      expect(
        SentryTokenScrubber.scrubApiUrl('/api/v1/monitors/42/checks?page=2'),
        '/api/v1/monitors/{id}/checks',
      );
    });

    test('masks an opaque segment of 32 characters and not 31', () {
      expect(
        SentryTokenScrubber.scrubApiUrl('/api/v1/x/${'a' * 32}/y'),
        '/api/v1/x/{token}/y',
      );
      expect(
        SentryTokenScrubber.scrubApiUrl('/api/v1/x/${'a' * 31}/y'),
        '/api/v1/x/${'a' * 31}/y',
      );
    });

    test('does not mask a long word with a character outside the token set',
        () {
      expect(
        SentryTokenScrubber.scrubApiUrl('/api/v1/${'a' * 20}.${'b' * 20}/y'),
        '/api/v1/${'a' * 20}.${'b' * 20}/y',
      );
    });
  });

  group('transactions', () {
    late List<SentryTransaction> sent;

    setUp(() {
      sent = <SentryTransaction>[];
    });

    Future<void> initSentry({bool appHook = true}) {
      return Sentry.init((SentryOptions options) {
        options
          ..dsn = dsn
          ..tracesSampleRate = 1.0;

        if (appHook) {
          // The app's own hook sees what the scrubber left, and drops the
          // transaction so nothing is ever sent from a test.
          options.beforeSendTransaction = (SentryTransaction t, Hint h) {
            sent.add(t);

            return null;
          };
        }

        SentryTokenScrubber.install(options);
      });
    }

    test('masks the name, the spans and the trace data', () async {
      const String opaque = 'Xq7Lk2Pz9Rt4Wm8Nb3Vc6Yd1Fg5Hj0Ks2Lp';

      await initSentry();

      final ISentrySpan transaction = Sentry.startTransaction(
        '/invitations/abc123def/accept',
        'navigation',
      );
      transaction.setData('route', '/invitations/abc123def/accept');

      final ISentrySpan http = transaction.startChild(
        'http.client',
        description: 'POST https://api.test/api/v1/invitations/$opaque/accept',
      );
      http.setData('url', 'https://api.test/api/v1/invitations/$opaque/accept');
      http.setData('http.query', 'token=abc&page=2');
      await http.finish();

      final ISentrySpan ui = transaction.startChild(
        'ui.load',
        description: '/invitations/abc123def/accept',
      );
      await ui.finish();

      await transaction.finish();

      expect(sent, hasLength(1));

      final SentryTransaction scrubbed = sent.single;
      final String spans = scrubbed.spans
          .map((SentrySpan span) => span.toJson().toString())
          .join();
      final String trace = scrubbed.contexts.trace!.toJson().toString();

      expect(scrubbed.transaction, isNot(contains('abc123def')));
      expect(trace, isNot(contains('abc123def')));
      expect(spans, isNot(contains('abc123def')));
      expect(spans, isNot(contains(opaque)));
      expect(spans, isNot(contains('token=abc')));
      expect(spans, contains('{token}'));
      expect(spans, contains('page=2'));
    });

    test('fails closed when the scrubber throws, and still returns it',
        () async {
      final List<SentryTransaction> raw = <SentryTransaction>[];

      await Sentry.init((SentryOptions options) {
        options
          ..dsn = dsn
          ..tracesSampleRate = 1.0
          ..beforeSendTransaction = (SentryTransaction t, Hint h) {
            raw.add(t);

            return null;
          };
      });

      final ISentrySpan transaction = Sentry.startTransaction(
        '/invitations/abc123def/accept',
        'navigation',
      );
      final ISentrySpan http = transaction.startChild(
        'http.client',
        description: 'POST https://api.test/api/v1/invitations/abc123def',
      );
      http.setData('url', 'https://api.test/api/v1/invitations/abc123def');
      await http.finish();
      await transaction.finish();

      registerThrowingRoute();

      final SentryTransaction scrubbed =
          SentryTokenScrubber.beforeSendTransaction(raw.single, hint);

      expect(scrubbed, same(raw.single));
      expect(scrubbed.transaction, '[Filtered]');
      expect(scrubbed.toJson().toString(), isNot(contains('abc123def')));
    });

    test('runs the app hook after the scrubber, on the scrubbed value',
        () async {
      await initSentry();

      final ISentrySpan transaction = Sentry.startTransaction(
        '/invitations/abc123def/accept',
        'navigation',
      );
      await transaction.finish();

      expect(sent.single.transaction, isNot(contains('abc123def')));
    });
  });

  group('SentryNetworkInterceptor', () {
    setUp(SentryNetworkInterceptor.reportedFailures.clear);

    test('a failed call to a token endpoint carries no token', () async {
      const String opaque = 'Xq7Lk2Pz9Rt4Wm8Nb3Vc6Yd1Fg5Hj0Ks2Lp';
      SentryEvent? captured;

      await Sentry.init((SentryOptions options) {
        options.dsn = dsn;
        options.beforeSend = (SentryEvent event, Hint hint) {
          captured = event;

          return null;
        };
      });

      SentryNetworkInterceptor().onError(
        MagicError(
          message: 'server exploded',
          request: MagicRequest(
            url: '/api/v1/invitations/$opaque/accept',
            method: 'POST',
          ),
          response: MagicResponse(
            data: null,
            statusCode: 500,
            headers: const {},
          ),
        ),
      );

      await pumpEventQueue();

      final String sentEvent = captured!.toJson().toString();

      expect(sentEvent, isNot(contains(opaque)));
      expect(captured!.fingerprint, [
        'http',
        'POST',
        '/api/v1/invitations/{token}/accept',
        '500',
      ]);
    });
  });

  group('install', () {
    test('runs the scrubber first, then the hook the app set', () async {
      final List<String?> seen = <String?>[];
      final SentryOptions options = SentryOptions(dsn: dsn)
        ..beforeSend = (SentryEvent event, Hint hint) {
          seen.add(event.request?.url);

          return event;
        }
        ..beforeBreadcrumb = (Breadcrumb? crumb, Hint hint) {
          seen.add(crumb?.message);

          return crumb;
        };

      SentryTokenScrubber.install(options);

      final SentryEvent? event = await options.beforeSend!(
        SentryEvent(
          request: SentryRequest(
            url: 'https://app.test/invitations/abc123def/accept',
          ),
        ),
        Hint(),
      );
      final Breadcrumb? crumb = options.beforeBreadcrumb!(
        Breadcrumb(message: 'to /invitations/abc123def/accept'),
        Hint(),
      );

      expect(seen, hasLength(2));
      expect(seen[0], isNot(contains('abc123def')));
      expect(seen[1], isNot(contains('abc123def')));
      expect(event!.request!.url, seen[0]);
      expect(crumb!.message, seen[1]);
    });

    test('lets the app hook drop what the scrubber kept', () async {
      final SentryOptions options = SentryOptions(dsn: dsn)
        ..beforeSend = ((SentryEvent event, Hint hint) => null)
        ..beforeBreadcrumb = ((Breadcrumb? crumb, Hint hint) => null);

      SentryTokenScrubber.install(options);

      expect(await options.beforeSend!(SentryEvent(), Hint()), isNull);
      expect(
          options.beforeBreadcrumb!(Breadcrumb(message: 'x'), Hint()), isNull);
    });

    test('wires all three hooks when the app set none', () {
      final SentryOptions options = SentryOptions(dsn: dsn);

      SentryTokenScrubber.install(options);

      expect(options.beforeSend, isNotNull);
      expect(options.beforeSendTransaction, isNotNull);
      expect(options.beforeBreadcrumb, isNotNull);
    });
  });
}

/// A route whose `fullPath` fails, to make the scrubber itself throw.
class _ThrowingRoute extends RouteDefinition {
  _ThrowingRoute({required super.path, required super.handler});

  @override
  String get fullPath => throw StateError('scrubber failure');
}

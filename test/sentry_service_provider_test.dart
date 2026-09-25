import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_sentry/magic_sentry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class _TestUser extends Model with Authenticatable {
  _TestUser({required String id}) {
    setRawAttributes({'id': id});
  }

  @override
  String get table => 'users';

  @override
  String get resource => 'users';

  @override
  String get id => getAttribute('id') as String? ?? '';
}

/// Records every interceptor handed to it. Every other [NetworkDriver] member
/// is unused by [SentryServiceProvider] and left unimplemented on purpose,
/// matching this codebase's "mock via contract inheritance" convention
/// (no mockito) rather than a reflection-driven double.
class _SpyNetworkDriver implements NetworkDriver {
  final List<MagicNetworkInterceptor> interceptors = [];

  @override
  void addInterceptor(MagicNetworkInterceptor interceptor) {
    interceptors.add(interceptor);
  }

  @override
  Future<MagicResponse> index(
    String resource, {
    Map<String, dynamic>? filters,
    Map<String, String>? headers,
  }) =>
      throw UnimplementedError();

  @override
  Future<MagicResponse> show(
    String resource,
    String id, {
    Map<String, String>? headers,
  }) =>
      throw UnimplementedError();

  @override
  Future<MagicResponse> store(
    String resource,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
  }) =>
      throw UnimplementedError();

  @override
  Future<MagicResponse> update(
    String resource,
    String id,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
  }) =>
      throw UnimplementedError();

  @override
  Future<MagicResponse> destroy(
    String resource,
    String id, {
    Map<String, String>? headers,
  }) =>
      throw UnimplementedError();

  @override
  Future<MagicResponse> get(
    String url, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) =>
      throw UnimplementedError();

  @override
  Future<MagicResponse> post(
    String url, {
    dynamic data,
    Map<String, String>? headers,
  }) =>
      throw UnimplementedError();

  @override
  Future<MagicResponse> put(
    String url, {
    dynamic data,
    Map<String, String>? headers,
  }) =>
      throw UnimplementedError();

  @override
  Future<MagicResponse> delete(String url, {Map<String, String>? headers}) =>
      throw UnimplementedError();

  @override
  Future<MagicResponse> upload(
    String url, {
    required Map<String, dynamic> data,
    required Map<String, dynamic> files,
    Map<String, String>? headers,
  }) =>
      throw UnimplementedError();
}

/// Locks what [SentryServiceProvider.boot] wires, and when.
///
/// Everything it does is gated on `Sentry.isEnabled`, which is false in
/// every group here except "with a DSN": that split is the test for the
/// disabled path, since a provider that wired anything without a DSN would
/// touch a container binding (`network`) a bare test never set up.
void main() {
  group('SentryServiceProvider', () {
    setUp(() {
      MagicApp.reset();
      Magic.flush();
      MagicRouter.reset();
    });

    tearDown(() async {
      Auth.unfake();
      MagicRouter.reset();
      if (Sentry.isEnabled) {
        await Sentry.close();
      }
    });

    test('does nothing without a DSN', () async {
      final provider = SentryServiceProvider(MagicApp.instance);

      await provider.boot();

      expect(MagicRouter.instance.observers, isEmpty);
    });

    group('with a DSN', () {
      setUp(() async {
        await Sentry.init(
          (options) => options.dsn = 'https://public@o0.ingest.sentry.io/0',
        );
      });

      test('wires the network interceptor into the bound driver', () async {
        final driver = _SpyNetworkDriver();
        Magic.app.setInstance('network', driver);

        await SentryServiceProvider(MagicApp.instance).boot();

        expect(driver.interceptors, hasLength(1));
        expect(driver.interceptors.single, isA<SentryNetworkInterceptor>());
      });

      test('registers the navigator observer', () async {
        Magic.app.setInstance('network', _SpyNetworkDriver());

        await SentryServiceProvider(MagicApp.instance).boot();

        expect(
          MagicRouter.instance.observers.whereType<SentryNavigatorObserver>(),
          hasLength(1),
        );
      });

      test('installs the user context when id/email callbacks are supplied',
          () async {
        Magic.app.setInstance('network', _SpyNetworkDriver());
        Auth.fake(user: _TestUser(id: 'usr_1'));

        await SentryServiceProvider<_TestUser>(
          MagicApp.instance,
          userId: (user) => user.id,
          userEmail: (user) => null,
        ).boot();

        SentryUser? reported;
        await Sentry.configureScope((scope) => reported = scope.user);

        expect(reported, isNotNull);
        expect(reported!.id, 'usr_1');
      });

      test('skips user reporting when no callbacks are supplied', () async {
        Magic.app.setInstance('network', _SpyNetworkDriver());

        await SentryServiceProvider(MagicApp.instance).boot();

        SentryUser? reported;
        await Sentry.configureScope((scope) => reported = scope.user);

        expect(reported, isNull);
      });

      test(
          'degrades to a debugPrint report, not silence, with no log bound '
          'and no network driver bound', () async {
        // Nothing bound at 'network': `app.make` throws inside the provider,
        // and boot() must not propagate it, since reporting is not worth
        // failing the whole app boot over. But it must not go silent either:
        // with no `log` binding (the state of a bare test, and any host that
        // has not registered logging yet) the fallback is `debugPrint`, so
        // the failure still reaches a console instead of vanishing.
        final List<String> printed = [];
        final DebugPrintCallback original = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) printed.add(message);
        };

        try {
          await SentryServiceProvider(MagicApp.instance).boot();
        } finally {
          debugPrint = original;
        }

        expect(
          MagicRouter.instance.observers.whereType<SentryNavigatorObserver>(),
          hasLength(1),
        );
        expect(
          printed.any((line) => line.contains('sentry')),
          isTrue,
          reason: 'the failure to wire the network interceptor must be '
              'reported, not swallowed',
        );
      });

      test(
          'reports through Log.warning, with a stack trace, when log is '
          'bound', () async {
        final FakeLogManager log = Log.fake();

        try {
          await SentryServiceProvider(MagicApp.instance).boot();
        } finally {
          Log.unfake();
        }

        log.assertLoggedCount(1);
        expect(log.entries.single.level, 'warning');
        expect(log.entries.single.message, contains('sentry'));
        expect(log.entries.single.context, contains('stackTrace'));
      });
    });
  });
}

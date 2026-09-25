import 'package:flutter/foundation.dart' show debugPrint;
import 'package:magic/magic.dart';
import 'package:sentry_dio/sentry_dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'sentry_network_interceptor.dart';
import 'sentry_user_context.dart';

/// Wires Sentry into a magic application, after `Magic.init` has run.
///
/// Everything here is inert without a DSN: [boot] returns immediately when
/// `Sentry.isEnabled` answers false, which is every local run and the whole
/// test suite unless a test calls `Sentry.init` itself. Register it in
/// `lib/config/app.dart`'s `providers` list; `MagicSentry.run` is what starts
/// the SDK itself, earlier, in `main()` (`Sentry.isEnabled` is only ever true
/// by the time this provider's `boot()` runs because that already happened).
///
/// [T] is the host app's own user model. Pass [userId] (and [userEmail] when
/// the model has one) to have this provider install a [SentryUserContext]
/// that follows `Auth.stateNotifier`; leave [userId] null to skip user
/// reporting entirely
/// (the network interceptor and the navigator observer still wire up either
/// way). [userExtras] adds anything else the app wants tagged on every event
/// (a team id, a plan) once a user is reported.
class SentryServiceProvider<T extends Model> extends ServiceProvider {
  /// Creates the provider.
  ///
  /// [userId] turns user reporting on: a scope user with no id is not a
  /// useful one, so without it nothing is reported. [userEmail] is optional,
  /// because a model with no email (a guest-only app) still deserves an id
  /// on its events. [userExtras] is optional and additive.
  SentryServiceProvider(
    super.app, {
    String Function(T user)? userId,
    String? Function(T user)? userEmail,
    Map<String, String> Function(T user)? userExtras,
  }) : _userContext = userId != null
            ? SentryUserContext<T>(
                id: userId,
                email: userEmail ?? (T user) => null,
                extras: userExtras,
              )
            : null;

  /// The user-context installer this provider wires in [boot], or null when
  /// the host app supplied no [userId].
  final SentryUserContext<T>? _userContext;

  @override
  void register() {
    // Nothing to bind: this provider only wires existing services together.
  }

  @override
  Future<void> boot() async {
    if (!Sentry.isEnabled) {
      return;
    }

    _registerNetworkInterceptor();
    _userContext?.install();

    // Registered here rather than in `main()` because `MagicRouter` refuses
    // an observer once it has built its `routerConfig`, and that build
    // happens on the first frame; `boot()` runs before that. Without this
    // every event is filed against a route this app never names, because
    // magic drives go_router and the SDK cannot see through it.
    MagicRouter.instance.addObserver(SentryNavigatorObserver());
  }

  /// Attach Sentry to the network driver, in two layers.
  ///
  /// `addSentry()` (from `sentry_dio`) contributes the automatic half: an
  /// HTTP breadcrumb and a span per request, so a captured failure arrives
  /// with the calls that preceded it. `captureFailedRequests` is turned OFF
  /// because its events are raised inside the sentry_dio adapter, which means
  /// their stack trace points at the SDK rather than at the caller, and they
  /// cannot carry the endpoint-based fingerprint [SentryNetworkInterceptor]
  /// needs; leaving it on would also double-report every failure.
  ///
  /// [SentryNetworkInterceptor] is the second layer and does the actual
  /// reporting, from magic's own interceptor chain where the real call site
  /// is still on the stack. It runs after `addSentry()` so its events carry
  /// the breadcrumbs that layer just recorded.
  ///
  /// The driver is resolved from the container rather than constructed, so a
  /// host that never registered one (a bare widget test) would throw here and
  /// take the whole boot with it. Reporting is not worth failing a boot over,
  /// so the failure degrades to a log line rather than a rethrow. It is
  /// caught NARROWLY (this `try` wraps only the wiring, not the rest of
  /// [boot]) and ALWAYS reported: `Log.warning` when a `log` binding exists,
  /// `debugPrint` otherwise, so a host with no logging configured yet still
  /// sees the failure on its console instead of it disappearing.
  void _registerNetworkInterceptor() {
    try {
      final NetworkDriver driver = app.make<NetworkDriver>('network');

      if (driver is DioNetworkDriver) {
        driver.configureDriver(
          (dio) => dio.addSentry(captureFailedRequests: false),
        );
      }

      driver.addInterceptor(SentryNetworkInterceptor());
    } catch (error, stackTrace) {
      const String message =
          '[sentry] Could not wire Sentry into the network driver';

      if (Magic.bound('log')) {
        Log.warning('$message: $error', {'stackTrace': stackTrace.toString()});
      } else {
        debugPrint('$message: $error\n$stackTrace');
      }
    }
  }
}

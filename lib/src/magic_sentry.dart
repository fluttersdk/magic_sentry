import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Boots Sentry, then the app, inside one zone.
///
/// Call this as the whole body of `main()`, before `Magic.init`:
///
/// ```dart
/// void main() {
///   MagicSentry.run(configure: configureSentry, appRunner: _boot);
/// }
///
/// Future<void> _boot() async {
///   await Magic.init(configFactories: [...]);
///   runApp(MyApp());
/// }
/// ```
///
/// `Config` is not loaded yet at this point, so [configure] cannot read a
/// `Magic` config map; it reads `.env` directly (via `Env`, which [run] loads
/// before calling [SentryFlutter.init]). `lib/config/sentry.dart`'s
/// `configureSentry` is a ready-made [configure] that does exactly this.
class MagicSentry {
  MagicSentry._();

  /// Opens one zone for Flutter's binding, `.env` loading, Sentry's own
  /// initialisation and the whole app, then hands zone-level errors to
  /// Sentry.
  ///
  /// ONE ZONE FOR EVERYTHING is the point, not an implementation detail: on
  /// Flutter web `SentryFlutter.init` opens its own `runZonedGuarded` only
  /// when called from the ROOT zone (`PlatformDispatcher.onError` alone does
  /// not catch every async error there, see flutter/flutter#100277). Entering
  /// a zone here first makes that check false, so `SentryFlutter.init` calls
  /// [appRunner] in THIS zone instead of a second one, and the binding
  /// [appRunner] eventually initialises is never asked to serve a callback
  /// registered in a different zone.
  ///
  /// [configure] receives the `SentryFlutterOptions` to fill in (DSN,
  /// environment, sample rates); [appRunner] is everything the app does
  /// after that, typically `Magic.init(...)` followed by `runApp(...)`. An
  /// empty DSN inside [configure] leaves the SDK inert and [appRunner] still
  /// runs: see `lib/config/sentry.dart`'s `sentryDsn`.
  static void run({
    required FutureOr<void> Function(SentryFlutterOptions options) configure,
    required FutureOr<void> Function() appRunner,
  }) {
    runZonedGuarded(
      () async {
        WidgetsFlutterBinding.ensureInitialized();

        // Loaded before Sentry: the DSN lives in `.env`, and `configure`
        // would otherwise run before it exists. `Env.load` guards on a
        // static `_isLoaded` flag and returns immediately once set, so a
        // host that also calls it from `appRunner` (e.g. because
        // `Magic.init` reads `.env` too) pays no real cost for the repeat
        // call; that same guard also means a DIFFERENT `fileName` passed to
        // that later call is silently ignored rather than merged, since the
        // file this loaded is the one that sticks for the rest of the run.
        await Env.load();

        await SentryFlutter.init(configure, appRunner: appRunner);
      },
      (Object error, StackTrace stackTrace) async {
        // Both halves of what Sentry's own zone handler does: report it, then
        // dump it to the console. Without the dump an uncaught async error
        // would vanish from the local console the moment this zone took over.
        await Sentry.captureException(error, stackTrace: stackTrace);

        FlutterError.dumpErrorToConsole(
          FlutterErrorDetails(exception: error, stack: stackTrace),
          forceReport: true,
        );
      },
    );
  }

  /// Marks a build error that replaced the whole interface with Sentry's
  /// `fatal` breadcrumb level, before the app's own screen ever renders.
  ///
  /// Flutter already reports the underlying exception through
  /// `FlutterError.onError`, which the SDK hooks on its own; what this adds is
  /// a tag distinguishing "an exception got logged" from "an exception
  /// replaced the interface with `ErrorWidget`'s flat grey box", which
  /// otherwise look identical in the issue list. Call once, early in
  /// `appRunner`, before the first widget builds:
  ///
  /// ```dart
  /// Future<void> _boot() async {
  ///   MagicSentry.installErrorWidgetBreadcrumb();
  ///   await Magic.init(...);
  ///   runApp(MyApp());
  /// }
  /// ```
  ///
  /// The default widget is returned unchanged: a replacement screen would
  /// need colours, fonts and a theme, each a thing that can throw in the
  /// exact situation this runs in.
  static void installErrorWidgetBreadcrumb() {
    final ErrorWidgetBuilder defaultErrorWidget = ErrorWidget.builder;

    ErrorWidget.builder = (FlutterErrorDetails details) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          category: 'ui.error_widget',
          message: 'a build error replaced the interface',
          level: SentryLevel.fatal,
          data: <String, Object?>{
            'library': details.library,
            'context': details.context?.toString(),
            'exception': details.exception.toString(),
          },
        ),
      );

      return defaultErrorWidget(details);
    };
  }
}

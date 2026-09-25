import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_sentry/magic_sentry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Locks [MagicSentry.run]'s contract: one zone, Sentry started first, the
/// app's own boot function always runs regardless of whether a DSN was
/// supplied, and a zone-level error is reported rather than crashing the
/// isolate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('barrel exports', () {
    test('the package does not export the app-local sentry config', () {
      // The install stub (`assets/stubs/install/sentry_config.stub`)
      // publishes a top-level `configureSentry` into a consumer app's own
      // `lib/config/sentry.dart`, which the documented `main()` imports
      // alongside `package:magic_sentry/magic_sentry.dart`. Re-exporting a
      // package copy of the same name from the barrel turns that `main()`
      // into an ambiguous import that never compiles, which is exactly what
      // shipped once. There is no reflection API to ask a compiled library
      // what it exported, so this reads the barrel's own source instead: the
      // closest thing to a compile-time contract this package can pin
      // without publishing a second package just to import both at once.
      final String barrel = File('lib/magic_sentry.dart').readAsStringSync();

      expect(
        barrel,
        isNot(contains("'config/sentry.dart'")),
        reason: 'the published install stub is the single source for '
            'configureSentry/sentryDsn/sentryEnabled; the barrel must not '
            'also export a package copy of the same names.',
      );
    });
  });

  group('MagicSentry.run', () {
    tearDown(() async {
      if (Sentry.isEnabled) {
        await Sentry.close();
      }
    });

    test('an empty DSN leaves Sentry disabled and still runs appRunner',
        () async {
      final completer = Completer<void>();

      MagicSentry.run(
        configure: (options) => options.dsn = '',
        appRunner: () {
          completer.complete();
        },
      );

      await completer.future.timeout(const Duration(seconds: 5));

      expect(Sentry.isEnabled, isFalse);
    });

    test('a non-empty DSN enables Sentry before appRunner runs', () async {
      final completer = Completer<bool>();

      MagicSentry.run(
        configure: (options) =>
            options.dsn = 'https://public@o0.ingest.sentry.io/0',
        appRunner: () {
          completer.complete(Sentry.isEnabled);
        },
      );

      expect(
        await completer.future.timeout(const Duration(seconds: 5)),
        isTrue,
      );
    });

    test('a zone error from appRunner does not crash the isolate', () async {
      // There is no bound transport here to assert Sentry actually SENT the
      // error, so this pins the weaker but load-bearing half: the handler
      // this wraps `SentryFlutter.init` in does not rethrow, so the test
      // (and a real app booted through MagicSentry.run) survives an
      // uncaught async error instead of taking the isolate down with it.
      final completer = Completer<void>();

      MagicSentry.run(
        configure: (options) => options.dsn = '',
        appRunner: () {
          scheduleMicrotask(() => throw StateError('boom'));
          completer.complete();
        },
      );

      await completer.future.timeout(const Duration(seconds: 5));
    });
  });

  group('installErrorWidgetBreadcrumb', () {
    late ErrorWidgetBuilder original;

    setUp(() {
      original = ErrorWidget.builder;
    });

    tearDown(() async {
      ErrorWidget.builder = original;
      if (Sentry.isEnabled) {
        await Sentry.close();
      }
    });

    test('tags a build error and still renders the default widget', () async {
      await Sentry.init(
        (options) => options.dsn = 'https://public@o0.ingest.sentry.io/0',
      );

      MagicSentry.installErrorWidgetBreadcrumb();

      final details = FlutterErrorDetails(
        exception: StateError('layout exploded'),
        library: 'magic_sentry test',
      );

      final Widget widget = ErrorWidget.builder(details);

      expect(widget, isA<Widget>());

      List<Breadcrumb> breadcrumbs = const [];
      await Sentry.configureScope((scope) => breadcrumbs = scope.breadcrumbs);

      expect(
        breadcrumbs.any(
          (b) =>
              b.category == 'ui.error_widget' && b.level == SentryLevel.fatal,
        ),
        isTrue,
      );
    });
  });
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_sentry/magic_sentry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Locks which binding [MagicSentry.run] creates.
///
/// This file deliberately never calls `TestWidgetsFlutterBinding
/// .ensureInitialized()`: the binding is a process-wide singleton, and the
/// point is to observe the one `run` creates when none exists yet, as in a
/// real `main()`. sentry_flutter's frame tracking disables itself unless the
/// binding is a [SentryWidgetsFlutterBinding], and its own integration cannot
/// replace a binding that already exists.
void main() {
  tearDown(() async {
    if (Sentry.isEnabled) {
      await Sentry.close();
    }
  });

  test('run creates a SentryWidgetsFlutterBinding before appRunner', () async {
    final completer = Completer<WidgetsBinding>();

    MagicSentry.run(
      configure: (options) =>
          options.dsn = 'https://public@o0.ingest.sentry.io/0',
      appRunner: () {
        completer.complete(WidgetsBinding.instance);
      },
    );

    expect(
      await completer.future.timeout(const Duration(seconds: 5)),
      isA<SentryWidgetsFlutterBinding>(),
    );
  });
}

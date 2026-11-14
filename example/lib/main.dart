import 'package:material_ui/material_ui.dart';
import 'package:magic/magic.dart';
import 'package:magic_sentry/magic_sentry.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'config/sentry.dart';

/// Sentry starts first, in one zone, so a failure while Magic boots is
/// reported too. `main()` is this one call and nothing else.
void main() {
  MagicSentry.run(configure: configureSentry, appRunner: _boot);
}

Future<void> _boot() async {
  // Tags a build error that replaced the interface, before the first widget.
  MagicSentry.installErrorWidgetBreadcrumb();

  await Magic.init(
    configs: [
      {
        'network': {
          'default': 'api',
          'drivers': {
            'api': {
              'base_url': 'http://localhost:8000/api/v1',
              'timeout': 10000,
            },
          },
        },
        'app': {
          'providers': [
            (app) => NetworkServiceProvider(app),
            (app) => SentryServiceProvider(app),
          ],
        },
      },
    ],
  );

  runApp(const ExampleApp());
}

/// One screen: whether Sentry is on, and two buttons that file something.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'magic_sentry example',
      home: Scaffold(
        appBar: AppBar(title: const Text('magic_sentry example')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Sentry.isEnabled
                    ? 'Sentry is on'
                    : 'Sentry is off: set SENTRY_DSN in .env',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Sentry.captureMessage('magic_sentry example'),
                child: const Text('Capture a test event'),
              ),
              const SizedBox(height: 8),
              // Nothing listens on localhost:8000, so this is a dead
              // connection (status 0) and the interceptor files an event.
              FilledButton(
                onPressed: () => Http.get('/health'),
                child: const Text('Fail an HTTP call'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

# magic_sentry example

A Magic app whose `main()` is `MagicSentry.run`. It registers `SentryServiceProvider` next to the network provider, shows whether Sentry is on, and has two buttons: one files a test event, the other makes an HTTP call to a port nothing listens on, which the interceptor reports as a dead connection. Sentry stays off until `.env` carries a DSN.

```bash
cd example
# set SENTRY_DSN in .env, then:
flutter run -d chrome
```

`.env` is a bundled asset (`flutter: assets:` in `pubspec.yaml`) and ships with an empty DSN, so the SDK is off until you fill it in. Do not commit a real DSN. `lib/config/sentry.dart` is the file `plugin:install` publishes into an app, copied here so the example runs on its own.

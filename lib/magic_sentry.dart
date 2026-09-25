/// Sentry error and performance monitoring for the Magic Framework.
///
/// This barrel deliberately does NOT export a `configureSentry`/`sentryDsn`/
/// `sentryEnabled` set: `install.yaml` publishes that as a plain Dart file
/// into a consumer app's own `lib/config/sentry.dart` (see
/// `assets/stubs/install/sentry_config.stub`), and the documented `main()`
/// imports both this barrel and that local file. A package copy of the same
/// top-level names here would make `configureSentry` an ambiguous import the
/// moment both are imported together, which never compiles.
library;

export 'src/magic_sentry.dart';
export 'src/sentry_network_interceptor.dart';
export 'src/sentry_service_provider.dart';
export 'src/sentry_user_context.dart';

import 'package:dowel/dowel.dart';

/// The dowel provider for Magic Sentry.
///
/// Contributes no commands. It exists because dowel `plugin:install` resolves
/// a plugin through `package:magic_sentry/cli.dart` and registers the class
/// named `<PascalCase package>DowelProvider` from it.
class MagicSentryDowelProvider extends DowelServiceProvider {
  @override
  String get providerName => 'magic_sentry';

  @override
  List<DowelCommand> commands() => <DowelCommand>[];
}

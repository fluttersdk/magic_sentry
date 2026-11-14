import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_sentry/cli.dart';

/// Every `import`/`export` target declared by `lib/cli.dart` and the whole
/// `lib/src/cli/` tree, read off disk so a file added later is covered too.
Iterable<String> _cliTreeImportTargets() {
  final directive = RegExp(
    '''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  final files = <File>[
    File('lib/cli.dart'),
    ...Directory('lib/src/cli')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart')),
  ];
  return files.expand(
    (file) => directive
        .allMatches(file.readAsStringSync())
        .map((match) => match.group(1)!),
  );
}

void main() {
  group('MagicSentryDowelProvider', () {
    test('contributes no commands', () {
      expect(MagicSentryDowelProvider().commands(), isEmpty);
    });

    test('the CLI tree imports only dart: and the dowel barrel', () {
      // The dowel dispatcher is a pure Dart process: one import that reaches
      // the UI toolkit, directly or through this package's runtime barrel,
      // breaks every command at the consumer's command line.
      for (final target in _cliTreeImportTargets()) {
        final allowed =
            target.startsWith('dart:') ||
            target == 'package:dowel/dowel.dart' ||
            !target.contains(':');

        expect(allowed, isTrue, reason: target);
      }
    });
  });
}

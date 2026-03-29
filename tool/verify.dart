import 'dart:io';

const _generatedPatterns = <String>[
  ':(glob)**/*.g.dart',
  ':(glob)**/*.freezed.dart',
  ':(glob)**/*.mocks.dart',
];

const _supportedModes = <String>{
  'analyze',
  'test',
  'build-apk',
  'all',
};

Future<void> main(List<String> args) async {
  try {
    final mode = args.isEmpty ? 'all' : args.first;
    if (!_supportedModes.contains(mode)) {
      _printUsage();
      exitCode = 64;
      return;
    }

    await _runStep(
      'Flutter dependencies',
      _flutterCommand(),
      ['pub', 'get'],
    );

    await _runStep(
      'Code generation',
      _dartCommand(),
      ['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
    );

    await _verifyGeneratedSources();

    switch (mode) {
      case 'analyze':
        await _runStep('Static analysis', _flutterCommand(), ['analyze']);
        break;
      case 'test':
        await _runStep('Tests', _flutterCommand(), ['test'], env: _testEnv());
        break;
      case 'build-apk':
        await _runStep(
          'Android release build',
          _flutterCommand(),
          ['build', 'apk', '--release'],
        );
        break;
      case 'all':
        await _runStep('Static analysis', _flutterCommand(), ['analyze']);
        await _runStep(
          'Tests',
          _flutterCommand(),
          ['test'],
          env: _testEnv(),
        );
        await _runStep(
          'Android release build',
          _flutterCommand(),
          ['build', 'apk', '--release'],
        );
        break;
    }
  } on ProcessException catch (error) {
    stderr.writeln(error.message);
    exitCode = error.errorCode;
  }
}

String _flutterCommand() => Platform.isWindows ? 'flutter.bat' : 'flutter';

String _dartCommand() => Platform.isWindows ? 'dart.bat' : 'dart';

Map<String, String> _testEnv() {
  final env = Map<String, String>.from(Platform.environment);
  for (final key in const [
    'http_proxy',
    'https_proxy',
    'HTTP_PROXY',
    'HTTPS_PROXY',
    'all_proxy',
    'ALL_PROXY',
  ]) {
    env.remove(key);
  }
  return env;
}

Future<void> _runStep(
  String label,
  String command,
  List<String> arguments, {
  Map<String, String>? env,
}) async {
  stdout.writeln('==> $label');
  stdout.writeln('    $command ${arguments.join(' ')}');

  final process = await Process.start(
    command,
    arguments,
    runInShell: true,
    environment: env,
    includeParentEnvironment: env == null,
  );

  await stdout.addStream(process.stdout);
  await stderr.addStream(process.stderr);

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(command, arguments, '$label failed', exitCode);
  }
}

Future<void> _verifyGeneratedSources() async {
  stdout.writeln('==> Verifying generated sources are committed');

  final unstaged = await _gitOutput([
    'diff',
    '--name-only',
    '--',
    ..._generatedPatterns,
  ]);
  final untracked = await _gitOutput([
    'ls-files',
    '--others',
    '--exclude-standard',
    '--',
    ..._generatedPatterns,
  ]);

  if (unstaged.isEmpty && untracked.isEmpty) {
    stdout.writeln('    Generated sources are up to date.');
    return;
  }

  if (unstaged.isNotEmpty) {
    stderr.writeln(unstaged.join('\n'));
  }
  if (unstaged.isNotEmpty && untracked.isNotEmpty) {
    stderr.writeln('');
  }
  if (untracked.isNotEmpty) {
    stderr.writeln(untracked.join('\n'));
  }
  stderr.writeln('');
  stderr.writeln(
    'Generated Dart sources changed after build_runner. '
    'Commit the updated files before merging.',
  );

  throw ProcessException(
    'git',
    ['diff', '--name-only', '--', ..._generatedPatterns],
    'Generated sources are out of date',
    1,
  );
}

Future<List<String>> _gitOutput(List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    runInShell: true,
  );

  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    throw ProcessException(
      'git',
      arguments,
      'Unable to inspect generated source status',
      result.exitCode,
    );
  }

  return (result.stdout as String)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

void _printUsage() {
  stderr.writeln(
    'Usage: dart run tool/verify.dart <analyze|test|build-apk|all>',
  );
}

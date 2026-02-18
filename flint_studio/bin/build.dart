import 'dart:io';

Future<void> main() async {
  stdout.writeln('Flint Studio Build');
  stdout.writeln('==================');

  final exeName = Platform.isWindows ? 'flint_studio.exe' : 'flint_studio';
  final outputPath = 'build/$exeName';

  await Directory('build').create(recursive: true);

  stdout.writeln('Running dart pub get...');
  var ok = await _run('dart', ['pub', 'get']);
  if (!ok) {
    stderr.writeln('Failed: dart pub get');
    exitCode = 1;
    return;
  }

  stdout.writeln('Compiling executable...');
  ok = await _run(
    'dart',
    ['compile', 'exe', 'lib/main.dart', '-o', outputPath],
  );
  if (!ok) {
    stderr.writeln('Build failed.');
    exitCode = 1;
    return;
  }

  stdout.writeln('Build complete: $outputPath');
}

Future<bool> _run(String executable, List<String> args) async {
  final process = await Process.start(
    executable,
    args,
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );
  final code = await process.exitCode;
  return code == 0;
}

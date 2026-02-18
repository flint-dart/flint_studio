import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  stdout.writeln('Flint Studio Setup + Start');
  stdout.writeln('==========================');
  stdout.writeln('Target port: 4033');
  stdout.writeln('');

  if (!Platform.isWindows && !Platform.isLinux) {
    stderr.writeln('Unsupported OS. This starter supports Windows and Linux only.');
    exitCode = 1;
    return;
  }

  final dbChoice = _askChoice(
    'Choose database to prepare',
    ['MySQL', 'PostgreSQL', 'Skip database install'],
  );

  if (dbChoice != 2) {
    final target = dbChoice == 0 ? 'mysql' : 'postgres';
    final installed = await _isDbInstalled(target);
    if (installed) {
      stdout.writeln('${_title(target)} already installed.');
    } else {
      final shouldInstall = _askYesNo(
        '${_title(target)} is not detected. Install now?',
        defaultYes: true,
      );
      if (shouldInstall) {
        final ok = await _installDatabase(target);
        if (!ok) {
          stderr.writeln(
            'Install did not complete automatically. Install ${_title(target)} and run start again.',
          );
        }
      }
    }
  }

  stdout.writeln('');
  stdout.writeln('Running dart pub get...');
  final pubOk = await _run('dart', ['pub', 'get']);
  if (!pubOk) {
    stderr.writeln('Failed: dart pub get');
    exitCode = 1;
    return;
  }

  stdout.writeln('');
  stdout.writeln('Starting Flint Studio on http://localhost:4033 ...');
  final startOk = await _run('dart', ['run', 'lib/main.dart']);
  if (!startOk) {
    stderr.writeln('Failed to start Flint Studio.');
    exitCode = 1;
  }
}

String _title(String db) => db == 'mysql' ? 'MySQL' : 'PostgreSQL';

int _askChoice(String question, List<String> options) {
  stdout.writeln(question);
  for (var i = 0; i < options.length; i++) {
    stdout.writeln('  ${i + 1}. ${options[i]}');
  }

  while (true) {
    stdout.write('Select option [1-${options.length}]: ');
    final input = stdin.readLineSync(encoding: utf8)?.trim() ?? '';
    final parsed = int.tryParse(input);
    if (parsed != null && parsed >= 1 && parsed <= options.length) {
      return parsed - 1;
    }
    stdout.writeln('Invalid input. Try again.');
  }
}

bool _askYesNo(String question, {required bool defaultYes}) {
  final suffix = defaultYes ? ' [Y/n]: ' : ' [y/N]: ';
  stdout.write(question + suffix);
  final input = (stdin.readLineSync(encoding: utf8) ?? '').trim().toLowerCase();
  if (input.isEmpty) return defaultYes;
  if (input == 'y' || input == 'yes') return true;
  if (input == 'n' || input == 'no') return false;
  return defaultYes;
}

Future<bool> _isDbInstalled(String db) async {
  if (Platform.isWindows) {
    if (db == 'mysql') return _commandExistsWindows('mysql');
    return _commandExistsWindows('psql');
  }

  if (db == 'mysql') return _commandExistsLinux('mysql');
  return _commandExistsLinux('psql');
}

Future<bool> _commandExistsWindows(String command) async {
  final result = await Process.run(
    'where',
    [command],
    runInShell: true,
  );
  return result.exitCode == 0;
}

Future<bool> _commandExistsLinux(String command) async {
  final result = await Process.run(
    'which',
    [command],
    runInShell: true,
  );
  return result.exitCode == 0;
}

Future<bool> _installDatabase(String db) async {
  stdout.writeln('Attempting installation for ${_title(db)}...');

  if (Platform.isWindows) {
    final commands = db == 'mysql'
        ? <List<String>>[
            ['winget', 'install', '--id', 'Oracle.MySQL', '-e'],
            ['winget', 'install', '--id', 'MySQL.MySQLServer', '-e'],
          ]
        : <List<String>>[
            ['winget', 'install', '--id', 'PostgreSQL.PostgreSQL', '-e'],
          ];

    for (final args in commands) {
      final ok = await _run(args.first, args.sublist(1));
      if (ok) return true;
    }
    return false;
  }

  final package = db == 'mysql' ? 'mysql-server' : 'postgresql';
  final installCandidates = <String>[
    'sudo apt-get update && sudo apt-get install -y $package',
    'sudo dnf install -y $package',
    'sudo yum install -y $package',
    'sudo pacman -Sy --noconfirm $package',
    'sudo zypper install -y $package',
  ];

  for (final command in installCandidates) {
    final ok = await _runShell(command);
    if (ok) return true;
  }
  return false;
}

Future<bool> _runShell(String command) async {
  final shell = Platform.isWindows ? 'cmd' : 'bash';
  final args = Platform.isWindows ? ['/c', command] : ['-lc', command];
  return _run(shell, args);
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

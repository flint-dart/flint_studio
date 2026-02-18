import 'dart:convert';

import 'package:flint_dart/flint_dart.dart';
import 'package:flint_dart/src/database/db.dart';
import 'package:flint_studio/services/connection_profile_store.dart';

class AdminController {
  static final RegExp _identifierPattern = RegExp(r'^[A-Za-z0-9_]+$');
  static final RegExp _mysqlUserPattern = RegExp(r'^[A-Za-z0-9_.-]+$');
  static final RegExp _hostPattern = RegExp(r'^[A-Za-z0-9_.%-]+$');

  final ConnectionProfileStore _store = ConnectionProfileStore();

  bool _isSafeIdentifier(String value) => _identifierPattern.hasMatch(value);
  String _escapeIdentifier(String value) => value.replaceAll('`', '``');
  String _escapePgIdentifier(String value) => value.replaceAll('"', '""');
  String _escapeSqlLiteral(String value) => value.replaceAll("'", "''");
  String _queryValue(Request req, String key) => (req.query[key] ?? '').trim();
  String _profileFromRequest(Request req) => (req.query['profile'] ?? '').trim();
  bool _matchesConfirmation(dynamic input, String expected) =>
      input.toString().trim() == expected;
  bool _sameConnectionTarget(
    Map<String, dynamic> profile, {
    required String driver,
    required String host,
    required int port,
    required String database,
    required String username,
  }) {
    return (profile['driver'] ?? '').toString().toLowerCase() == driver &&
        (profile['host'] ?? '').toString().trim().toLowerCase() ==
            host.toLowerCase() &&
        (profile['port'] ?? 0).toString() == port.toString() &&
        (profile['database'] ?? '').toString().trim().toLowerCase() ==
            database.toLowerCase() &&
        (profile['username'] ?? '').toString().trim().toLowerCase() ==
            username.toLowerCase();
  }

  String _newProfileId() => DateTime.now().microsecondsSinceEpoch.toString();

  bool _isMySql(Map<String, dynamic> profile) =>
      profile['driver'].toString() == 'mysql';

  bool _isPostgres(Map<String, dynamic> profile) =>
      profile['driver'].toString() == 'postgres';

  String _driverLabel(Map<String, dynamic> profile) {
    if (_isMySql(profile)) return 'MySQL';
    if (_isPostgres(profile)) return 'PostgreSQL';
    return (profile['driver'] ?? '').toString();
  }

  bool _isLikelySqlStatement(String sql) {
    final normalized = sql.trimLeft().toUpperCase();
    return RegExp(
      r'^(CREATE|ALTER|DROP|TRUNCATE|RENAME|INSERT|UPDATE|DELETE|REPLACE|SELECT|SET|USE|START|BEGIN|COMMIT|ROLLBACK|GRANT|REVOKE|LOCK|UNLOCK|CALL|DO)\b',
    ).hasMatch(normalized);
  }

  List<String> _splitSqlStatements(String input) {
    final statements = <String>[];
    final buffer = StringBuffer();

    var inSingleQuote = false;
    var inDoubleQuote = false;
    var inBacktick = false;
    var inLineComment = false;
    var inBlockComment = false;

    var i = 0;
    while (i < input.length) {
      final ch = input[i];
      final next = i + 1 < input.length ? input[i + 1] : '';

      if (inLineComment) {
        if (ch == '\n') {
          inLineComment = false;
        }
        i++;
        continue;
      }

      if (inBlockComment) {
        if (ch == '*' && next == '/') {
          inBlockComment = false;
          i += 2;
          continue;
        }
        i++;
        continue;
      }

      if (!inSingleQuote && !inDoubleQuote && !inBacktick) {
        if (ch == '-' && next == '-') {
          inLineComment = true;
          i += 2;
          continue;
        }
        if (ch == '#') {
          inLineComment = true;
          i++;
          continue;
        }
        if (ch == '/' && next == '*') {
          inBlockComment = true;
          i += 2;
          continue;
        }
      }

      if (!inDoubleQuote && !inBacktick && ch == "'") {
        inSingleQuote = !inSingleQuote;
        buffer.write(ch);
        i++;
        continue;
      }
      if (!inSingleQuote && !inBacktick && ch == '"') {
        inDoubleQuote = !inDoubleQuote;
        buffer.write(ch);
        i++;
        continue;
      }
      if (!inSingleQuote && !inDoubleQuote && ch == '`') {
        inBacktick = !inBacktick;
        buffer.write(ch);
        i++;
        continue;
      }

      if ((inSingleQuote || inDoubleQuote) && ch == r'\') {
        buffer.write(ch);
        if (i + 1 < input.length) {
          buffer.write(input[i + 1]);
          i += 2;
        } else {
          i++;
        }
        continue;
      }

      if (!inSingleQuote && !inDoubleQuote && !inBacktick && ch == ';') {
        final stmt = buffer.toString().trim();
        if (stmt.isNotEmpty) {
          statements.add(stmt);
        }
        buffer.clear();
        i++;
        continue;
      }

      buffer.write(ch);
      i++;
    }

    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) {
      statements.add(tail);
    }

    return statements;
  }

  Response _redirectWithMessage(
    Response res,
    String basePath, {
    String? success,
    String? error,
    String? profileId,
  }) {
    final parts = <String>[];
    if (success != null && success.isNotEmpty) {
      parts.add('success=${Uri.encodeQueryComponent(success)}');
    }
    if (error != null && error.isNotEmpty) {
      parts.add('error=${Uri.encodeQueryComponent(error)}');
    }
    if (profileId != null && profileId.isNotEmpty) {
      parts.add('profile=${Uri.encodeQueryComponent(profileId)}');
    }
    final suffix = parts.isEmpty ? '' : '?${parts.join('&')}';
    return res.redirect('$basePath$suffix');
  }

  Future<Map<String, dynamic>> _resolveProfile(
    Request req, {
    String? explicitProfileId,
  }) async {
    final selectedId = explicitProfileId ?? _profileFromRequest(req);
    final profiles = await _store.all();

    if (profiles.isEmpty) {
      throw Exception('No saved connection profile. Create one from dashboard.');
    }

    if (selectedId.isNotEmpty) {
      final byId = await _store.byId(selectedId);
      if (byId != null) return byId;
    }

    final active = await _store.active();
    return active ?? profiles.first;
  }

  Future<List<Map<String, dynamic>>> _profiles() => _store.all();

  Future<void> _connectWithProfile(
    Map<String, dynamic> profile, {
    String? databaseOverride,
  }) async {
    final targetDb = (databaseOverride ?? profile['database']).toString();

    try {
      await DB.close();
    } catch (_) {}

    await DB.connect(
      database: targetDb,
      host: profile['host'].toString(),
      port: (profile['port'] as int),
      username: profile['username'].toString(),
      password: profile['password'].toString(),
      isSecure: profile['secure'] == true,
    );
  }

  Map<String, dynamic> _viewConnectionData(Map<String, dynamic> profile) {
    return {
      'currentProfileId': (profile['id'] ?? '').toString(),
      'currentProfileName': (profile['name'] ?? '').toString(),
      'currentDriver': (profile['driver'] ?? '').toString(),
      'currentHost': (profile['host'] ?? '').toString(),
      'currentPort': (profile['port'] ?? '').toString(),
      'currentDatabase': (profile['database'] ?? '').toString(),
      'currentUser': (profile['username'] ?? '').toString(),
      'currentSecure': profile['secure'] == true ? 'true' : 'false',
    };
  }

  Future<Response> dashboard(Request req, Response res) async {
    final profiles = await _profiles();
    Map<String, dynamic> current = {};
    if (profiles.isNotEmpty) {
      current = await _resolveProfile(req);
    }

    return res.view(
      'dashboard',
      data: {
        'activePage': 'dashboard',
        'profiles': profiles,
        'profileCount': profiles.length,
        ..._viewConnectionData(current),
        'successMessage': _queryValue(req, 'success'),
        'errorMessage': _queryValue(req, 'error'),
      },
    );
  }

  Future<Response> connectDatabase(Request req, Response res) async {
    try {
      final form = await req.form();
      final name = (form['profile_name'] ?? '').trim();
      final driver = (form['driver'] ?? 'mysql').trim().toLowerCase();
      final host = (form['host'] ?? '').trim();
      final portText = (form['port'] ?? '').trim();
      final database = (form['database'] ?? '').trim();
      final username = (form['username'] ?? '').trim();
      final inputPassword = (form['password'] ?? '').trim();
      final secure = (form['secure'] ?? '').trim().toLowerCase() == 'on';

      if (name.isEmpty) {
        return _redirectWithMessage(res, '/', error: 'Profile name is required.');
      }
      if (!(driver == 'mysql' || driver == 'postgres')) {
        return _redirectWithMessage(res, '/', error: 'Invalid driver.');
      }
      if (host.isEmpty || !_hostPattern.hasMatch(host)) {
        return _redirectWithMessage(res, '/', error: 'Invalid host.');
      }
      if (database.isEmpty || username.isEmpty) {
        return _redirectWithMessage(
          res,
          '/',
          error: 'Database and username are required.',
        );
      }

      final port = int.tryParse(portText) ?? (driver == 'mysql' ? 3306 : 5432);
      final existingProfiles = await _profiles();
      final duplicate = existingProfiles.firstWhere(
        (p) => _sameConnectionTarget(
          p,
          driver: driver,
          host: host,
          port: port,
          database: database,
          username: username,
        ),
        orElse: () => <String, dynamic>{},
      );
      if (duplicate.isNotEmpty) {
        final duplicateName = (duplicate['name'] ?? '').toString();
        return _redirectWithMessage(
          res,
          '/',
          error:
              'This database connection already exists as "$duplicateName". Use Update Active Profile instead.',
          profileId: (duplicate['id'] ?? '').toString(),
        );
      }
      final password = inputPassword;
      final id = _newProfileId();
      final profile = {
        'id': id,
        'name': name,
        'driver': driver,
        'host': host,
        'port': port,
        'database': database,
        'username': username,
        'password': password,
        'secure': secure,
        'active': true,
      };

      await _connectWithProfile(profile);
      await _store.upsert(profile, setActive: true);

      return _redirectWithMessage(
        res,
        '/',
        success: 'Connected and saved profile "$name".',
        profileId: id,
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/',
        error: 'Connection failed: ${e.toString()}',
      );
    }
  }

  Future<Response> updateProfile(Request req, Response res) async {
    try {
      final form = await req.form();
      final profileId = (form['profile_id'] ?? '').trim();
      if (profileId.isEmpty) {
        return _redirectWithMessage(res, '/', error: 'Profile ID is required.');
      }

      final existing = await _store.byId(profileId);
      if (existing == null) {
        return _redirectWithMessage(res, '/', error: 'Profile not found.');
      }

      final name = (form['profile_name'] ?? '').trim();
      final driver = (form['driver'] ?? existing['driver']).toString().trim().toLowerCase();
      final host = (form['host'] ?? '').trim();
      final portText = (form['port'] ?? '').trim();
      final database = (form['database'] ?? '').trim();
      final username = (form['username'] ?? '').trim();
      final inputPassword = (form['password'] ?? '').trim();
      final secure = (form['secure'] ?? '').trim().toLowerCase() == 'on';

      if (name.isEmpty) {
        return _redirectWithMessage(res, '/', error: 'Profile name is required.');
      }
      if (!(driver == 'mysql' || driver == 'postgres')) {
        return _redirectWithMessage(res, '/', error: 'Invalid driver.');
      }
      if (host.isEmpty || !_hostPattern.hasMatch(host)) {
        return _redirectWithMessage(res, '/', error: 'Invalid host.');
      }
      if (database.isEmpty || username.isEmpty) {
        return _redirectWithMessage(
          res,
          '/',
          error: 'Database and username are required.',
        );
      }

      final port = int.tryParse(portText) ?? (driver == 'mysql' ? 3306 : 5432);
      final password = inputPassword.isNotEmpty
          ? inputPassword
          : (existing['password'] ?? '').toString();

      final profile = {
        'id': profileId,
        'name': name,
        'driver': driver,
        'host': host,
        'port': port,
        'database': database,
        'username': username,
        'password': password,
        'secure': secure,
        'active': true,
      };

      await _connectWithProfile(profile);
      await _store.upsert(profile, setActive: true);

      return _redirectWithMessage(
        res,
        '/',
        success: 'Profile "$name" updated.',
        profileId: profileId,
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/',
        error: 'Failed to update profile: ${e.toString()}',
      );
    }
  }

  Future<Response> deleteProfile(Request req, Response res) async {
    try {
      final form = await req.form();
      final profileId = (form['profile_id'] ?? '').trim();
      final confirmName = (form['confirm_name'] ?? '').trim();

      if (profileId.isEmpty) {
        return _redirectWithMessage(res, '/', error: 'Profile ID is required.');
      }

      final existing = await _store.byId(profileId);
      if (existing == null) {
        return _redirectWithMessage(res, '/', error: 'Profile not found.');
      }

      final expectedName = (existing['name'] ?? '').toString();
      if (!_matchesConfirmation(confirmName, expectedName)) {
        return _redirectWithMessage(
          res,
          '/',
          error: 'Confirmation failed. Type exact profile name to delete.',
          profileId: profileId,
        );
      }

      await _store.delete(profileId);
      return _redirectWithMessage(
        res,
        '/',
        success: 'Profile "$expectedName" deleted.',
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/',
        error: 'Failed to delete profile: ${e.toString()}',
      );
    }
  }

  Future<Response> switchProfile(Request req, Response res) async {
    try {
      final form = await req.form();
      final profileId = (form['profile_id'] ?? '').trim();

      if (profileId.isEmpty) {
        return _redirectWithMessage(res, '/', error: 'Profile ID is required.');
      }

      final profile = await _store.byId(profileId);
      if (profile == null) {
        return _redirectWithMessage(res, '/', error: 'Profile not found.');
      }

      await _connectWithProfile(profile);
      await _store.setActive(profileId);

      return _redirectWithMessage(
        res,
        '/',
        success: 'Switched to profile "${profile['name']}".',
        profileId: profileId,
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/',
        error: 'Failed to switch profile: ${e.toString()}',
      );
    }
  }

  Future<Response> databases(Request req, Response res) async {
    try {
      final profiles = await _profiles();
      if (profiles.isEmpty) {
        throw Exception('No saved connection profile. Create one from dashboard.');
      }
      final activeProfile = await _resolveProfile(req);

      final databaseEntries = <Map<String, dynamic>>[];
      final profileErrors = <String>[];

      for (final profile in profiles) {
        try {
          await _connectWithProfile(profile);
          final rows = _isMySql(profile)
              ? await DB.query('SHOW DATABASES')
              : await DB.query(
                  '''
                  SELECT datname
                  FROM pg_database
                  WHERE datistemplate = false
                  ORDER BY datname
                  ''',
                );

          for (final row in rows) {
            final databaseName =
                row.values.isNotEmpty ? row.values.first.toString() : '';
            if (databaseName.isEmpty) continue;
            databaseEntries.add({
              'name': databaseName,
              'encodedName': Uri.encodeComponent(databaseName),
              'profileId': (profile['id'] ?? '').toString(),
              'profileName': (profile['name'] ?? '').toString(),
              'driverLabel': _driverLabel(profile),
            });
          }
        } catch (e) {
          final profileName = (profile['name'] ?? 'Unknown profile').toString();
          profileErrors.add('$profileName: ${e.toString()}');
        }
      }

      return res.view(
        'databases',
        data: {
          'activePage': 'databases',
          'databaseEntries': databaseEntries,
          'databaseCount': databaseEntries.length,
          'profileErrorCount': profileErrors.length,
          'profileErrors': profileErrors,
          'currentDriverLabel': _driverLabel(activeProfile),
          ..._viewConnectionData(activeProfile),
          'successMessage': _queryValue(req, 'success'),
          'errorMessage': _queryValue(req, 'error'),
        },
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/',
        error: 'Failed to load databases: ${e.toString()}',
      );
    }
  }

  Future<Response> createDatabase(Request req, Response res) async {
    try {
      final form = await req.form();
      final profileId = (form['profile_id'] ?? '').trim();
      final profile = await _resolveProfile(req, explicitProfileId: profileId);
      await _connectWithProfile(profile);

      final databaseName = (form['database_name'] ?? '').trim();
      if (databaseName.isEmpty || !_isSafeIdentifier(databaseName)) {
        return _redirectWithMessage(
          res,
          '/databases',
          error: 'Invalid database name.',
          profileId: profile['id'].toString(),
        );
      }

      if (_isMySql(profile)) {
        await DB.execute(
          'CREATE DATABASE IF NOT EXISTS `${_escapeIdentifier(databaseName)}`',
        );
      } else {
        await DB.execute('CREATE DATABASE "$databaseName"');
      }

      return _redirectWithMessage(
        res,
        '/databases',
        success: 'Database "$databaseName" created.',
        profileId: profile['id'].toString(),
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/databases',
        error: 'Failed to create database: ${e.toString()}',
      );
    }
  }

  Future<Response> dropDatabase(Request req, Response res) async {
    final databaseName = Uri.decodeComponent((req.params['database'] ?? '').trim());

    if (!_isSafeIdentifier(databaseName)) {
      return _redirectWithMessage(res, '/databases', error: 'Invalid database name.');
    }

    try {
      final form = await req.form();
      final profileId = (form['profile_id'] ?? '').trim();
      final confirmName = (form['confirm_name'] ?? '').trim();
      final profile = await _resolveProfile(req, explicitProfileId: profileId);

      if (!_matchesConfirmation(confirmName, databaseName)) {
        return _redirectWithMessage(
          res,
          '/databases',
          error: 'Confirmation failed. Type exact database name to drop.',
          profileId: profile['id'].toString(),
        );
      }

      if (_isPostgres(profile)) {
        await _connectWithProfile(profile, databaseOverride: 'postgres');
        await DB.execute('DROP DATABASE IF EXISTS "${_escapePgIdentifier(databaseName)}"');
      } else {
        await _connectWithProfile(profile);
        await DB.execute('DROP DATABASE IF EXISTS `${_escapeIdentifier(databaseName)}`');
      }

      return _redirectWithMessage(
        res,
        '/databases',
        success: 'Database "$databaseName" dropped.',
        profileId: profile['id'].toString(),
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/databases',
        error: 'Failed to drop database: ${e.toString()}',
      );
    }
  }

  Future<Response> databaseDetails(Request req, Response res) async {
    final rawName = (req.params['database'] ?? '').trim();
    final databaseName = Uri.decodeComponent(rawName);

    if (!_isSafeIdentifier(databaseName)) {
      return _redirectWithMessage(res, '/databases', error: 'Invalid database.');
    }

    try {
      final profile = await _resolveProfile(req);
      await _connectWithProfile(profile, databaseOverride: databaseName);

      final tables = _isMySql(profile)
          ? await DB.query(
              '''
              SELECT TABLE_NAME, ENGINE, COALESCE(TABLE_ROWS, 0) AS TABLE_ROWS
              FROM information_schema.tables
              WHERE table_schema = ? AND table_type = 'BASE TABLE'
              ORDER BY TABLE_NAME
              ''',
              positionalParams: [databaseName],
            )
          : await DB.query(
              '''
              SELECT table_name AS TABLE_NAME, '-' AS ENGINE, 0 AS TABLE_ROWS
              FROM information_schema.tables
              WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
              ORDER BY table_name
              ''',
            );

      // Ensure row count is visible/accurate by querying each table directly.
      final tablesWithCounts = <Map<String, dynamic>>[];
      for (final row in tables) {
        final table = Map<String, dynamic>.from(row);
        final tableNameValue = (table['TABLE_NAME'] ?? '').toString();
        if (!_isSafeIdentifier(tableNameValue)) {
          tablesWithCounts.add(table);
          continue;
        }

        try {
          final countRows = _isMySql(profile)
              ? await DB.query(
                  'SELECT COUNT(*) AS row_count FROM `${_escapeIdentifier(databaseName)}`.`${_escapeIdentifier(tableNameValue)}`',
                )
              : await DB.query(
                  'SELECT COUNT(*) AS row_count FROM "${_escapePgIdentifier(tableNameValue)}"',
                );
          final exactCount = countRows.isNotEmpty
              ? (countRows.first['row_count'] ?? countRows.first.values.first)
              : 0;
          table['TABLE_ROWS'] = exactCount.toString();
        } catch (_) {
          // Fall back to metadata count if direct count fails.
          table['TABLE_ROWS'] = (table['TABLE_ROWS'] ?? '0').toString();
        }

        tablesWithCounts.add(table);
      }

      final triggers = _isMySql(profile)
          ? await DB.query(
              '''
              SELECT TRIGGER_NAME, ACTION_TIMING, EVENT_MANIPULATION, EVENT_OBJECT_TABLE
              FROM information_schema.triggers
              WHERE trigger_schema = ?
              ORDER BY TRIGGER_NAME
              ''',
              positionalParams: [databaseName],
            )
          : await DB.query(
              '''
              SELECT trigger_name AS TRIGGER_NAME, action_timing AS ACTION_TIMING,
                     event_manipulation AS EVENT_MANIPULATION, event_object_table AS EVENT_OBJECT_TABLE
              FROM information_schema.triggers
              WHERE trigger_schema = 'public'
              ORDER BY trigger_name
              ''',
            );

      List<Map<String, dynamic>> users = [];
      String usersError = '';
      try {
        users = _isMySql(profile)
            ? await DB.query(
                "SELECT CONCAT(user, '@', host) AS ACCOUNT FROM mysql.user ORDER BY user LIMIT 200",
              )
            : await DB.query(
                'SELECT rolname AS ACCOUNT FROM pg_roles ORDER BY rolname LIMIT 200',
              );
      } catch (_) {
        usersError = _isMySql(profile)
            ? 'Could not read mysql.user (missing privilege).'
            : 'Could not read pg_roles (missing privilege).';
      }

      return res.view(
        'database_details',
        data: {
          'activePage': 'databases',
          ..._viewConnectionData(profile),
          'databaseName': databaseName,
          'tables': tablesWithCounts,
          'tableCount': tablesWithCounts.length,
          'triggers': triggers,
          'triggerCount': triggers.length,
          'users': users,
          'usersCount': users.length,
          'usersError': usersError,
          'successMessage': _queryValue(req, 'success'),
          'errorMessage': _queryValue(req, 'error'),
        },
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/databases',
        error: 'Failed to load database details: ${e.toString()}',
      );
    }
  }

  Future<Response> tableDetails(Request req, Response res) async {
    final databaseName = Uri.decodeComponent((req.params['database'] ?? '').trim());
    final tableName = Uri.decodeComponent((req.params['table'] ?? '').trim());

    if (!_isSafeIdentifier(databaseName) || !_isSafeIdentifier(tableName)) {
      return _redirectWithMessage(res, '/databases', error: 'Invalid database/table name.');
    }

    try {
      final profile = await _resolveProfile(req);
      await _connectWithProfile(profile, databaseOverride: databaseName);

      final columns = _isMySql(profile)
          ? await DB.query(
              '''
              SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_KEY
              FROM information_schema.columns
              WHERE table_schema = ? AND table_name = ?
              ORDER BY ordinal_position
              ''',
              positionalParams: [databaseName, tableName],
            )
          : await DB.query(
              '''
              SELECT column_name AS COLUMN_NAME, data_type AS DATA_TYPE,
                     is_nullable AS IS_NULLABLE, '' AS COLUMN_KEY
              FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = ?
              ORDER BY ordinal_position
              ''',
              positionalParams: [tableName],
            );

      final pkRows = _isMySql(profile)
          ? await DB.query(
              '''
              SELECT COLUMN_NAME
              FROM information_schema.key_column_usage
              WHERE table_schema = ? AND table_name = ? AND constraint_name = 'PRIMARY'
              ORDER BY ordinal_position
              ''',
              positionalParams: [databaseName, tableName],
            )
          : await DB.query(
              '''
              SELECT kcu.column_name AS COLUMN_NAME
              FROM information_schema.table_constraints tc
              JOIN information_schema.key_column_usage kcu
                ON tc.constraint_name = kcu.constraint_name
               AND tc.table_schema = kcu.table_schema
              WHERE tc.constraint_type = 'PRIMARY KEY'
                AND tc.table_schema = 'public'
                AND tc.table_name = ?
              ORDER BY kcu.ordinal_position
              ''',
              positionalParams: [tableName],
            );

      final pkColumns = pkRows
          .map((row) => row['COLUMN_NAME']?.toString() ?? '')
          .where((c) => c.isNotEmpty)
          .toList();
      final editable = pkColumns.length == 1;
      final pkColumn = editable ? pkColumns.first : '';

      final rows = _isMySql(profile)
          ? await DB.query(
              'SELECT * FROM `${_escapeIdentifier(databaseName)}`.`${_escapeIdentifier(tableName)}` LIMIT 200',
            )
          : await DB.query(
              'SELECT * FROM "${_escapePgIdentifier(tableName)}" LIMIT 200',
            );

      final columnNames = columns
          .map((col) => col['COLUMN_NAME']?.toString() ?? '')
          .where((c) => c.isNotEmpty)
          .toList();

      return res.view(
        'table_details',
        data: {
          'activePage': 'databases',
          ..._viewConnectionData(profile),
          'databaseName': databaseName,
          'tableName': tableName,
          'columns': columns,
          'columnCount': columnNames.length,
          'rowCount': rows.length,
          'columnNamesJson': jsonEncode(columnNames),
          'rowsJson': jsonEncode(rows),
          'editable': editable ? 'true' : 'false',
          'pkColumn': pkColumn,
          'successMessage': _queryValue(req, 'success'),
          'errorMessage': _queryValue(req, 'error'),
        },
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/databases/${Uri.encodeComponent(databaseName)}',
        error: 'Failed to load table details: ${e.toString()}',
      );
    }
  }

  Future<Response> triggerDetails(Request req, Response res) async {
    final databaseName = Uri.decodeComponent((req.params['database'] ?? '').trim());
    final triggerName = Uri.decodeComponent((req.params['trigger'] ?? '').trim());

    if (!_isSafeIdentifier(databaseName) || !_isSafeIdentifier(triggerName)) {
      return _redirectWithMessage(res, '/databases', error: 'Invalid database/trigger name.');
    }

    try {
      final profile = await _resolveProfile(req);
      await _connectWithProfile(profile, databaseOverride: databaseName);

      final triggerRows = _isMySql(profile)
          ? await DB.query(
              '''
              SELECT TRIGGER_NAME, ACTION_TIMING, EVENT_MANIPULATION, EVENT_OBJECT_TABLE, ACTION_STATEMENT
              FROM information_schema.triggers
              WHERE trigger_schema = ? AND trigger_name = ?
              LIMIT 1
              ''',
              positionalParams: [databaseName, triggerName],
            )
          : await DB.query(
              '''
              SELECT t.tgname AS TRIGGER_NAME,
                     pg_get_triggerdef(t.oid) AS ACTION_STATEMENT,
                     c.relname AS EVENT_OBJECT_TABLE,
                     '' AS ACTION_TIMING,
                     '' AS EVENT_MANIPULATION
              FROM pg_trigger t
              JOIN pg_class c ON t.tgrelid = c.oid
              WHERE NOT t.tgisinternal AND t.tgname = ?
              LIMIT 1
              ''',
              positionalParams: [triggerName],
            );

      final trigger = triggerRows.isNotEmpty ? triggerRows.first : <String, dynamic>{};

      return res.view(
        'trigger_details',
        data: {
          'activePage': 'databases',
          ..._viewConnectionData(profile),
          'databaseName': databaseName,
          'triggerName': triggerName,
          'trigger': trigger,
        },
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/databases/${Uri.encodeComponent(databaseName)}',
        error: 'Failed to load trigger details: ${e.toString()}',
      );
    }
  }

  Future<Response> dropTable(Request req, Response res) async {
    final databaseName = Uri.decodeComponent((req.params['database'] ?? '').trim());
    final tableName = Uri.decodeComponent((req.params['table'] ?? '').trim());

    if (!_isSafeIdentifier(databaseName) || !_isSafeIdentifier(tableName)) {
      return _redirectWithMessage(res, '/databases', error: 'Invalid database/table name.');
    }

    try {
      final form = await req.form();
      final profileId = (form['profile_id'] ?? '').trim();
      final confirmName = (form['confirm_name'] ?? '').trim();
      final profile = await _resolveProfile(req, explicitProfileId: profileId);

      if (!_matchesConfirmation(confirmName, tableName)) {
        return _redirectWithMessage(
          res,
          '/databases/${Uri.encodeComponent(databaseName)}',
          error: 'Confirmation failed. Type exact table name to drop.',
          profileId: profile['id'].toString(),
        );
      }

      await _connectWithProfile(profile, databaseOverride: databaseName);

      if (_isMySql(profile)) {
        await DB.execute(
          'DROP TABLE IF EXISTS `${_escapeIdentifier(databaseName)}`.`${_escapeIdentifier(tableName)}`',
        );
      } else {
        await DB.execute(
          'DROP TABLE IF EXISTS "${_escapePgIdentifier(tableName)}"',
        );
      }

      return _redirectWithMessage(
        res,
        '/databases/${Uri.encodeComponent(databaseName)}',
        success: 'Table "$tableName" dropped.',
        profileId: profile['id'].toString(),
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/databases/${Uri.encodeComponent(databaseName)}',
        error: 'Failed to drop table: ${e.toString()}',
      );
    }
  }

  Future<Response> dropTableColumn(Request req, Response res) async {
    final databaseName = Uri.decodeComponent((req.params['database'] ?? '').trim());
    final tableName = Uri.decodeComponent((req.params['table'] ?? '').trim());

    if (!_isSafeIdentifier(databaseName) || !_isSafeIdentifier(tableName)) {
      return _redirectWithMessage(res, '/databases', error: 'Invalid database/table name.');
    }

    try {
      final form = await req.form();
      final profileId = (form['profile_id'] ?? '').trim();
      final profile = await _resolveProfile(req, explicitProfileId: profileId);
      await _connectWithProfile(profile, databaseOverride: databaseName);

      final columnName = (form['column_name'] ?? '').trim();
      final confirmName = (form['confirm_name'] ?? '').trim();
      if (!_isSafeIdentifier(columnName)) {
        return _redirectWithMessage(
          res,
          '/databases/${Uri.encodeComponent(databaseName)}/tables/${Uri.encodeComponent(tableName)}',
          error: 'Invalid column name.',
          profileId: profile['id'].toString(),
        );
      }
      if (!_matchesConfirmation(confirmName, columnName)) {
        return _redirectWithMessage(
          res,
          '/databases/${Uri.encodeComponent(databaseName)}/tables/${Uri.encodeComponent(tableName)}',
          error: 'Confirmation failed. Type exact column name to drop.',
          profileId: profile['id'].toString(),
        );
      }

      if (_isMySql(profile)) {
        await DB.execute(
          'ALTER TABLE `${_escapeIdentifier(databaseName)}`.`${_escapeIdentifier(tableName)}` DROP COLUMN `${_escapeIdentifier(columnName)}`',
        );
      } else {
        await DB.execute(
          'ALTER TABLE "${_escapePgIdentifier(tableName)}" DROP COLUMN "${_escapePgIdentifier(columnName)}"',
        );
      }

      return _redirectWithMessage(
        res,
        '/databases/${Uri.encodeComponent(databaseName)}/tables/${Uri.encodeComponent(tableName)}',
        success: 'Column "$columnName" dropped.',
        profileId: profile['id'].toString(),
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/databases/${Uri.encodeComponent(databaseName)}/tables/${Uri.encodeComponent(tableName)}',
        error: 'Failed to drop column: ${e.toString()}',
      );
    }
  }

  Future<Response> deleteTableRow(Request req, Response res) async {
    final databaseName = Uri.decodeComponent((req.params['database'] ?? '').trim());
    final tableName = Uri.decodeComponent((req.params['table'] ?? '').trim());

    try {
      final payload = await req.json();
      final profileId = (payload['profile_id'] ?? '').toString().trim();
      final profile = await _resolveProfile(req, explicitProfileId: profileId);
      await _connectWithProfile(profile, databaseOverride: databaseName);

      final pkColumn = (payload['pk_column'] ?? '').toString().trim();
      final pkValue = payload['pk_value'];
      final confirmValue = payload['confirm_value'];

      if (!_isSafeIdentifier(tableName) || !_isSafeIdentifier(pkColumn)) {
        return res.status(400).json({'ok': false, 'message': 'Invalid table or PK column.'});
      }
      if (pkValue == null) {
        return res.status(400).json({'ok': false, 'message': 'Missing PK value.'});
      }
      if (!_matchesConfirmation(confirmValue, pkValue.toString())) {
        return res.status(400).json({
          'ok': false,
          'message': 'Confirmation failed. Type the exact row key to delete.',
        });
      }

      if (_isMySql(profile)) {
        await DB.execute(
          'DELETE FROM `${_escapeIdentifier(databaseName)}`.`${_escapeIdentifier(tableName)}` WHERE `${_escapeIdentifier(pkColumn)}` = ? LIMIT 1',
          positionalParams: [pkValue],
        );
      } else {
        await DB.execute(
          'DELETE FROM "${_escapePgIdentifier(tableName)}" WHERE "${_escapePgIdentifier(pkColumn)}" = ?',
          positionalParams: [pkValue],
        );
      }

      return res.json({'ok': true, 'message': 'Row deleted.'});
    } catch (e) {
      return res.status(500).json({'ok': false, 'message': 'Failed to delete row', 'error': e.toString()});
    }
  }

  Future<Response> updateTableRow(Request req, Response res) async {
    final databaseName = Uri.decodeComponent((req.params['database'] ?? '').trim());
    final tableName = Uri.decodeComponent((req.params['table'] ?? '').trim());

    try {
      final payload = await req.json();
      final profileId = (payload['profile_id'] ?? '').toString().trim();
      final profile = await _resolveProfile(req, explicitProfileId: profileId);
      await _connectWithProfile(profile, databaseOverride: databaseName);

      final pkColumn = (payload['pk_column'] ?? '').toString().trim();
      final pkValue = payload['pk_value'];
      final changesRaw = payload['changes'];

      if (!_isSafeIdentifier(tableName) || !_isSafeIdentifier(pkColumn)) {
        return res.status(400).json({'ok': false, 'message': 'Invalid table or primary key column.'});
      }
      if (pkValue == null) {
        return res.status(400).json({'ok': false, 'message': 'Missing primary key value.'});
      }
      if (changesRaw is! Map) {
        return res.status(400).json({'ok': false, 'message': 'Invalid changes payload.'});
      }

      final changeEntries = <MapEntry<String, dynamic>>[];
      for (final entry in changesRaw.entries) {
        final col = entry.key.toString();
        if (!_isSafeIdentifier(col)) continue;
        if (col == pkColumn) continue;
        changeEntries.add(MapEntry(col, entry.value));
      }

      if (changeEntries.isEmpty) {
        return res.json({'ok': true, 'message': 'No changes to save.'});
      }

      if (_isMySql(profile)) {
        final setSql = <String>[];
        final params = <dynamic>[];
        for (final e in changeEntries) {
          setSql.add('`${_escapeIdentifier(e.key)}` = ?');
          params.add(e.value);
        }
        params.add(pkValue);
        await DB.execute(
          'UPDATE `${_escapeIdentifier(databaseName)}`.`${_escapeIdentifier(tableName)}` SET ${setSql.join(', ')} WHERE `${_escapeIdentifier(pkColumn)}` = ? LIMIT 1',
          positionalParams: params,
        );
      } else {
        final setSql = <String>[];
        final params = <dynamic>[];
        for (final e in changeEntries) {
          setSql.add('"${_escapePgIdentifier(e.key)}" = ?');
          params.add(e.value);
        }
        params.add(pkValue);
        await DB.execute(
          'UPDATE "${_escapePgIdentifier(tableName)}" SET ${setSql.join(', ')} WHERE "${_escapePgIdentifier(pkColumn)}" = ?',
          positionalParams: params,
        );
      }

      return res.json({'ok': true, 'message': 'Row updated successfully.'});
    } catch (e) {
      return res.status(500).json({'ok': false, 'message': 'Failed to update row', 'error': e.toString()});
    }
  }

  Future<Response> createTable(Request req, Response res) async {
    final rawName = (req.params['database'] ?? '').trim();
    final databaseName = Uri.decodeComponent(rawName);

    try {
      final form = await req.form();
      final profileId = (form['profile_id'] ?? '').trim();
      final profile = await _resolveProfile(req, explicitProfileId: profileId);
      await _connectWithProfile(profile, databaseOverride: databaseName);

      final tableName = (form['table_name'] ?? '').trim();
      final columnsSql = (form['columns_sql'] ?? '').trim();

      if (!_isSafeIdentifier(tableName) || columnsSql.isEmpty) {
        return _redirectWithMessage(
          res,
          '/databases/${Uri.encodeComponent(databaseName)}',
          error: 'Invalid table input.',
          profileId: profile['id'].toString(),
        );
      }

      if (_isMySql(profile)) {
        await DB.execute(
          'CREATE TABLE `${_escapeIdentifier(databaseName)}`.`${_escapeIdentifier(tableName)}` ($columnsSql)',
        );
      } else {
        await DB.execute('CREATE TABLE "$tableName" ($columnsSql)');
      }

      return _redirectWithMessage(
        res,
        '/databases/${Uri.encodeComponent(databaseName)}',
        success: 'Table "$tableName" created.',
        profileId: profile['id'].toString(),
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/databases/${Uri.encodeComponent(databaseName)}',
        error: 'Failed to create table: ${e.toString()}',
      );
    }
  }

  Future<Response> createTrigger(Request req, Response res) async {
    final rawName = (req.params['database'] ?? '').trim();
    final databaseName = Uri.decodeComponent(rawName);

    try {
      final form = await req.form();
      final profileId = (form['profile_id'] ?? '').trim();
      final profile = await _resolveProfile(req, explicitProfileId: profileId);

      if (_isPostgres(profile)) {
        return _redirectWithMessage(
          res,
          '/databases/${Uri.encodeComponent(databaseName)}',
          error: 'Use SQL Query page for PostgreSQL trigger creation.',
          profileId: profile['id'].toString(),
        );
      }

      await _connectWithProfile(profile, databaseOverride: databaseName);

      final triggerName = (form['trigger_name'] ?? '').trim();
      final timing = (form['timing'] ?? '').trim().toUpperCase();
      final event = (form['event'] ?? '').trim().toUpperCase();
      final tableName = (form['table_name'] ?? '').trim();
      final statementSql = (form['statement_sql'] ?? '').trim();

      if (!_isSafeIdentifier(triggerName) ||
          !_isSafeIdentifier(tableName) ||
          statementSql.isEmpty) {
        return _redirectWithMessage(
          res,
          '/databases/${Uri.encodeComponent(databaseName)}',
          error: 'Invalid trigger input.',
          profileId: profile['id'].toString(),
        );
      }

      await DB.execute(
        '''
        CREATE TRIGGER `${_escapeIdentifier(databaseName)}`.`${_escapeIdentifier(triggerName)}`
        $timing $event ON `${_escapeIdentifier(databaseName)}`.`${_escapeIdentifier(tableName)}`
        FOR EACH ROW
        $statementSql
        ''',
      );

      return _redirectWithMessage(
        res,
        '/databases/${Uri.encodeComponent(databaseName)}',
        success: 'Trigger "$triggerName" created.',
        profileId: profile['id'].toString(),
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/databases/${Uri.encodeComponent(databaseName)}',
        error: 'Failed to create trigger: ${e.toString()}',
      );
    }
  }

  Future<Response> createUser(Request req, Response res) async {
    final rawName = (req.params['database'] ?? '').trim();
    final databaseName = Uri.decodeComponent(rawName);

    try {
      final form = await req.form();
      final profileId = (form['profile_id'] ?? '').trim();
      final profile = await _resolveProfile(req, explicitProfileId: profileId);
      await _connectWithProfile(profile, databaseOverride: databaseName);

      final username = (form['username'] ?? '').trim();
      final password = (form['password'] ?? '').trim();
      final host = (form['host'] ?? '%').trim().isEmpty
          ? '%'
          : (form['host'] ?? '%').trim();
      final grantAll = (form['grant_all'] ?? '').trim().toLowerCase() == 'on';

      if (!_mysqlUserPattern.hasMatch(username) || password.isEmpty) {
        return _redirectWithMessage(
          res,
          '/databases/${Uri.encodeComponent(databaseName)}',
          error: 'Invalid user input.',
          profileId: profile['id'].toString(),
        );
      }

      final safePassword = _escapeSqlLiteral(password);

      if (_isMySql(profile)) {
        final safeUser = _escapeSqlLiteral(username);
        final safeHost = _escapeSqlLiteral(host);
        await DB.execute(
          "CREATE USER IF NOT EXISTS '$safeUser'@'$safeHost' IDENTIFIED BY '$safePassword'",
        );
        if (grantAll) {
          await DB.execute(
            "GRANT ALL PRIVILEGES ON `${_escapeIdentifier(databaseName)}`.* TO '$safeUser'@'$safeHost'",
          );
          await DB.execute('FLUSH PRIVILEGES');
        }
      } else {
        await DB.execute(
          'CREATE ROLE "$username" WITH LOGIN PASSWORD \'$safePassword\'',
        );
        if (grantAll) {
          await DB.execute(
            'GRANT ALL PRIVILEGES ON DATABASE "$databaseName" TO "$username"',
          );
        }
      }

      return _redirectWithMessage(
        res,
        '/databases/${Uri.encodeComponent(databaseName)}',
        success: 'User "$username" created.',
        profileId: profile['id'].toString(),
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/databases/${Uri.encodeComponent(databaseName)}',
        error: 'Failed to create user: ${e.toString()}',
      );
    }
  }

  Future<Response> queryEditor(Request req, Response res) async {
    try {
      final profile = await _resolveProfile(req);
      final profiles = await _profiles();

      return res.view(
        'query',
        data: {
          'activePage': 'query',
          'profiles': profiles,
          ..._viewConnectionData(profile),
        },
      );
    } catch (_) {
      return res.view(
        'query',
        data: {
          'activePage': 'query',
          'profiles': [],
          'currentProfileId': '',
          'currentProfileName': '',
          'currentDriver': '',
          'currentDatabase': '',
        },
      );
    }
  }

  Future<Response> importSql(Request req, Response res) async {
    try {
      if (!await req.hasFile('sql_file')) {
        return _redirectWithMessage(res, '/', error: 'Please choose an .sql file.');
      }

      final form = await req.form();
      final profileId = (form['profile_id'] ?? '').trim();
      final profile = await _resolveProfile(req, explicitProfileId: profileId);
      final targetDb = (form['database_name'] ?? '').trim();
      final dbToUse = targetDb.isNotEmpty ? targetDb : profile['database'].toString();

      await _connectWithProfile(profile, databaseOverride: dbToUse);

      final upload = await req.file('sql_file');
      if (upload == null) {
        return _redirectWithMessage(
          res,
          '/',
          error: 'Could not read uploaded file.',
          profileId: profile['id'].toString(),
        );
      }

      final chunks = await upload.content.toList();
      final bytes = <int>[];
      for (final c in chunks) {
        bytes.addAll(c);
      }
      final sqlText = utf8.decode(bytes);
      final statements = _splitSqlStatements(sqlText)
          .map((s) => s.trim())
          .where((s) => !s.toUpperCase().startsWith('DELIMITER '))
          .where((s) => s.isNotEmpty && _isLikelySqlStatement(s))
          .toList();

      if (statements.isEmpty) {
        return _redirectWithMessage(
          res,
          '/',
          error: 'No valid SQL statements found in uploaded file.',
        );
      }

      var count = 0;
      for (var i = 0; i < statements.length; i++) {
        final sql = statements[i];
        try {
          await DB.execute(sql);
          count++;
        } catch (e) {
          final preview = sql.length > 120 ? '${sql.substring(0, 120)}...' : sql;
          throw Exception(
            'Statement ${i + 1}/${statements.length} failed: ${e.toString()} | SQL: $preview',
          );
        }
      }

      return _redirectWithMessage(
        res,
        '/databases/${Uri.encodeComponent(dbToUse)}',
        success: 'Imported $count SQL statements into "$dbToUse".',
        profileId: profile['id'].toString(),
      );
    } catch (e) {
      return _redirectWithMessage(
        res,
        '/',
        error: 'SQL import failed: ${e.toString()}',
      );
    }
  }

  Future<Response> runQuery(Request req, Response res) async {
    try {
      final payload = await req.json();
      final profileId = (payload['profile_id'] ?? '').toString().trim();
      final profile = await _resolveProfile(req, explicitProfileId: profileId);
      await _connectWithProfile(profile);

      final sql = (payload['sql'] ?? '').toString().trim();
      if (sql.isEmpty) {
        return res.status(400).json({'ok': false, 'message': 'SQL query is required'});
      }

      final readOnly = RegExp(r'^(SELECT|SHOW|DESCRIBE|EXPLAIN)\b', caseSensitive: false);
      if (readOnly.hasMatch(sql)) {
        final rows = await DB.query(sql);
        return res.json({
          'ok': true,
          'type': 'result_set',
          'count': rows.length,
          'rows': rows,
          'profile': profile['name'],
        });
      }

      await DB.execute(sql);
      return res.json({
        'ok': true,
        'type': 'command',
        'message': 'Query executed successfully',
        'profile': profile['name'],
      });
    } catch (e) {
      return res.status(500).json({
        'ok': false,
        'message': 'Query execution failed',
        'error': e.toString(),
      });
    }
  }
}

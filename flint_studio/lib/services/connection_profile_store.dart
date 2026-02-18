import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flint_dart/flint_dart.dart';

class ConnectionProfileStore {
  static const String _filePath = 'storage/connection_profiles.json';
  static const String _encPrefix = 'enc:v1:';

  Future<List<Map<String, dynamic>>> all() async {
    final file = File(_filePath);
    if (!await file.exists()) {
      return [];
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return [];
    }

    final rawProfiles = decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final profiles = rawProfiles.map(_decryptProfile).toList();
    final needsMigration = rawProfiles.any((p) {
      final password = (p['password'] ?? '').toString();
      return password.isNotEmpty && !password.startsWith(_encPrefix);
    });
    if (needsMigration) {
      await _saveAll(profiles);
    }
    return profiles;
  }

  Future<Map<String, dynamic>?> byId(String id) async {
    final profiles = await all();
    for (final profile in profiles) {
      if (profile['id'].toString() == id) {
        return profile;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> active() async {
    final profiles = await all();
    for (final profile in profiles) {
      if (profile['active'] == true) {
        return profile;
      }
    }
    if (profiles.isEmpty) return null;
    return profiles.first;
  }

  Future<void> upsert(
    Map<String, dynamic> profile, {
    bool setActive = false,
  }) async {
    final profiles = await all();
    final id = profile['id'].toString();
    var replaced = false;

    for (var i = 0; i < profiles.length; i++) {
      if (profiles[i]['id'].toString() == id) {
        profiles[i] = {...profiles[i], ...profile};
        replaced = true;
        break;
      }
    }

    if (!replaced) {
      profiles.add(profile);
    }

    if (setActive) {
      for (final p in profiles) {
        p['active'] = p['id'].toString() == id;
      }
    }

    await _saveAll(profiles);
  }

  Future<void> setActive(String id) async {
    final profiles = await all();
    for (final profile in profiles) {
      profile['active'] = profile['id'].toString() == id;
    }
    await _saveAll(profiles);
  }

  Future<void> delete(String id) async {
    final profiles = await all();
    final filtered = profiles.where((p) => p['id'].toString() != id).toList();
    if (filtered.isNotEmpty && !filtered.any((p) => p['active'] == true)) {
      filtered.first['active'] = true;
    }
    await _saveAll(filtered);
  }

  Future<void> _saveAll(List<Map<String, dynamic>> profiles) async {
    final file = File(_filePath);
    await file.parent.create(recursive: true);
    final encryptedProfiles = profiles.map(_encryptProfile).toList();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(encryptedProfiles),
    );
  }

  Map<String, dynamic> _encryptProfile(Map<String, dynamic> profile) {
    final copy = Map<String, dynamic>.from(profile);
    final password = (copy['password'] ?? '').toString();
    if (password.isNotEmpty) {
      copy['password'] = _encryptString(password);
    }
    return copy;
  }

  Map<String, dynamic> _decryptProfile(Map<String, dynamic> profile) {
    final copy = Map<String, dynamic>.from(profile);
    final password = (copy['password'] ?? '').toString();
    if (password.isNotEmpty) {
      copy['password'] = _decryptString(password);
    }
    return copy;
  }

  String _encryptString(String plaintext) {
    final bytes = utf8.encode(plaintext);
    final nonce = Uint8List.fromList(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final cipher = _xorWithKeyStream(bytes, nonce);
    final payload = <int>[...nonce, ...cipher];
    return '$_encPrefix${base64Encode(payload)}';
  }

  String _decryptString(String value) {
    if (!value.startsWith(_encPrefix)) return value;

    try {
      final raw = base64Decode(value.substring(_encPrefix.length));
      if (raw.length < 16) return '';
      final nonce = raw.sublist(0, 16);
      final cipher = raw.sublist(16);
      final plain = _xorWithKeyStream(cipher, nonce);
      return utf8.decode(plain);
    } catch (_) {
      return '';
    }
  }

  List<int> _xorWithKeyStream(List<int> input, List<int> nonce) {
    final keyBytes = utf8.encode(_encryptionKey());
    final output = List<int>.filled(input.length, 0);
    var offset = 0;
    var counter = 0;

    while (offset < input.length) {
      final counterBytes = ByteData(4)..setUint32(0, counter, Endian.big);
      final blockSeed = <int>[
        ...keyBytes,
        ...nonce,
        ...counterBytes.buffer.asUint8List(),
      ];
      final digest = sha256.convert(blockSeed).bytes;

      for (var i = 0; i < digest.length && offset < input.length; i++) {
        output[offset] = input[offset] ^ digest[i];
        offset++;
      }
      counter++;
    }
    return output;
  }

  String _encryptionKey() {
    final configured = FlintEnv.get('FLINT_STUDIO_PROFILE_KEY', '').trim();
    if (configured.isNotEmpty) return configured;
    final jwtSecret = FlintEnv.get('JWT_SECRET', '').trim();
    if (jwtSecret.isNotEmpty) return jwtSecret;
    return 'flint-studio-default-profile-key';
  }
}

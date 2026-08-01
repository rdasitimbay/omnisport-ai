import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/athlete.dart';
import '../models/session_model.dart';
import 'firestore_service.dart';

class SecureHiveService {
  static const _secureStorage = FlutterSecureStorage();
  static const String _encryptionKeyId = 'hive_encryption_key';
  static const String pendingSyncBoxName = 'pending_sync_box';
  static const String athleteCacheBoxName = 'athlete_cache_box';

  /// Inicializa Hive, registra adaptadores y abre cajas cifradas
  static Future<void> init() async {
    // Nos aseguramos de tener un token válido antes de permitir abrir las cajas
    try {
      final firestoreService = FirestoreService();
      await firestoreService.refreshToken();
    } catch (e) {
      debugPrint(
        'SecureHive: No se pudo refrescar token. Si no hay red, usaremos token cachead. $e',
      );
    }

    await Hive.initFlutter();

    // Registrar los TypeAdapters generados
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(AthleteAdapter());
    if (!Hive.isAdapterRegistered(1))
      Hive.registerAdapter(SessionModelAdapter());

    // Obtener llave de cifrado segura
    final encryptionKey = await _getOrCreateEncryptionKey();

    // Abrir cajas cifradas
    await Hive.openBox(
      pendingSyncBoxName,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
    await Hive.openBox(
      athleteCacheBoxName,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    debugPrint('SecureHive: Cajas cifradas iniciadas correctamente (AES-256)');
  }

  /// Obtiene o genera una llave de 32 bytes para AES-256
  static Future<List<int>> _getOrCreateEncryptionKey() async {
    String? keyString = await _secureStorage.read(key: _encryptionKeyId);
    if (keyString == null) {
      final key = Hive.generateSecureKey();
      keyString = base64UrlEncode(key);
      await _secureStorage.write(key: _encryptionKeyId, value: keyString);
      debugPrint(
        'SecureHive: Nueva llave generada y guardada en SecureStorage',
      );
    }
    return base64Url.decode(keyString);
  }

  static Box get pendingSyncBox => Hive.box(pendingSyncBoxName);
  static Box get athleteCacheBox => Hive.box(athleteCacheBoxName);
}

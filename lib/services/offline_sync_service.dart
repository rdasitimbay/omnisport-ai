import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'firestore_service.dart';
import 'secure_hive_service.dart';
import '../models/athlete.dart';
import '../models/session_model.dart';


class OfflineSyncService {
  static StreamSubscription<List<ConnectivityResult>>?
  _connectivitySubscription;
  static bool forceOfflineMode = false;
  static String lastSyncResponse = 'No sync attempted';

  /// Inicializa la cola de sincronización en background.
  /// Las cajas se inicializan en SecureHiveService.
  static Future<void> init() async {
    // No llamamos a Hive.initFlutter() aquí, porque SecureHiveService ya lo hace.
    _startSyncQueue();
  }

  static void _startSyncQueue() {
    // Cancel previous subscription before creating a new one to avoid duplicates
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (!results.contains(ConnectivityResult.none)) {
        debugPrint(
          'OfflineSync: Red detectada. Intentando sincronizar cola...',
        );
        syncLogs();
      }
    });
  }

  static void dispose() {
    _connectivitySubscription?.cancel();
  }

  /// Guarda un registro en el caché local seguro usando objetos fuertemente tipados.
  static Future<void> saveModelLocally(dynamic model) async {
    try {
      final box = SecureHiveService.pendingSyncBox;
      // Guardamos la clase tipada directamente (Hive se encarga de serializar usando el TypeAdapter)
      await box.add(model);
      debugPrint(
        'OfflineSync: Guardado localmente el modelo ${model.runtimeType} en pending_sync_box',
      );
    } catch (e) {
      debugPrint('OfflineSync: Error al guardar modelo en Hive: $e');
    }
  }

  /// Revisa la cola tipada y sincroniza de forma silenciosa con FirestoreService
  static Future<void> syncLogs({FirebaseFirestore? firestore}) async {
    if (!await _hasInternetConnection()) {
      lastSyncResponse = 'Skipped: Offline';
      return;
    }

    final box = SecureHiveService.pendingSyncBox;
    if (box.isEmpty) {
      lastSyncResponse = 'Skipped: Empty Queue';
      return;
    }

    final firestoreService = FirestoreService();
    final List<dynamic> keysToDelete = [];
    final List<Map<String, dynamic>> accessLogsToSync = [];
    final List<dynamic> accessLogsKeys = [];

    debugPrint(
      'OfflineSync: Iniciando sincronización de ${box.length} elementos tipados...',
    );

    for (var key in box.keys) {
      final model = box.get(key);
      if (model != null) {
        try {
          if (model is SessionModel) {
            // Background Sync: Subimos la sesión usando su método toMap()
            await firestoreService.addTrainingSession(
              model.athleteId,
              model.toMap(),
            );
            keysToDelete.add(key);
          } else if (model is Athlete) {
            // Opcional: Podrías querer crear una lógica para updateAthleteData
            keysToDelete.add(key);
          } else if (model is Map) {
            final mapModel = Map<String, dynamic>.from(model);
            if (mapModel['sync_type'] == 'access_log') {
              mapModel.remove('sync_type');
              accessLogsToSync.add(mapModel);
              accessLogsKeys.add(key);
            } else {
              keysToDelete.add(key);
            }
          } else {
            // Datos inválidos o no reconocidos
            keysToDelete.add(key);
          }
        } catch (e) {
          debugPrint(
            'OfflineSync: Error procesando elemento local $key de tipo ${model.runtimeType}: $e',
          );
        }
      }
    }

    if (accessLogsToSync.isNotEmpty) {
      try {
        final result = await FirebaseFunctions.instance
            .httpsCallable('syncAccessLog')
            .call({'logs': accessLogsToSync});
        
        if (result.data['syncedCount'] == accessLogsToSync.length) {
          keysToDelete.addAll(accessLogsKeys);
          debugPrint('OfflineSync: ${accessLogsToSync.length} access logs sincronizados vía Cloud Function.');
        }
      } catch (e) {
        debugPrint('OfflineSync: Error al llamar a syncAccessLog Cloud Function: $e');
        // No añadimos las keys a keysToDelete para reintentar en el futuro
      }
    }

    if (keysToDelete.isNotEmpty) {
      try {
        await box.deleteAll(keysToDelete);
        lastSyncResponse = 'Success: Synced ${keysToDelete.length} records';
        debugPrint(
          'OfflineSync: Background Sync exitosa. Limpiados ${keysToDelete.length} registros del caché tipado.',
        );
      } catch (e) {
        lastSyncResponse = 'Error cleaning cache: $e';
        debugPrint('OfflineSync: Error al limpiar caché de Hive: $e');
      }
    }
  }

  /// Verifica la conexión a Internet real intentando resolver DNS
  static Future<bool> _hasInternetConnection() async {
    if (forceOfflineMode) return false;
    if (kIsWeb) return true;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return true;
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

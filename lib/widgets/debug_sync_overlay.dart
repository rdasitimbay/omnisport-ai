import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/offline_sync_service.dart';
import '../services/secure_hive_service.dart';

class DebugSyncOverlay extends StatefulWidget {
  const DebugSyncOverlay({Key? key}) : super(key: key);

  @override
  State<DebugSyncOverlay> createState() => _DebugSyncOverlayState();
}

class _DebugSyncOverlayState extends State<DebugSyncOverlay> {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 50,
      right: 10,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orangeAccent, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.orangeAccent.withValues(alpha: 0.3),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ValueListenableBuilder(
            // Solo escuchamos la caja si ya está inicializada
            valueListenable:
                Hive.isBoxOpen(SecureHiveService.pendingSyncBoxName)
                ? SecureHiveService.pendingSyncBox.listenable()
                : ValueNotifier(null),
            builder: (context, box, _) {
              final isKeyLoaded = Hive.isBoxOpen(
                SecureHiveService.pendingSyncBoxName,
              );
              final pendingCount = isKeyLoaded
                  ? SecureHiveService.pendingSyncBox.length
                  : 0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '🛠️ Sync Sentinel',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pending Records: $pendingCount',
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    'AES Key Loaded: ${isKeyLoaded ? "✅" : "❌"}',
                    style: TextStyle(
                      color: isKeyLoaded
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last Response: ${OfflineSyncService.lastSyncResponse}',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        OfflineSyncService.forceOfflineMode =
                            !OfflineSyncService.forceOfflineMode;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OfflineSyncService.forceOfflineMode
                          ? Colors.redAccent
                          : Colors.white24,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 30),
                    ),
                    icon: Icon(
                      OfflineSyncService.forceOfflineMode
                          ? Icons.wifi_off
                          : Icons.wifi,
                      color: Colors.white,
                      size: 14,
                    ),
                    label: Text(
                      OfflineSyncService.forceOfflineMode
                          ? 'Net Fail: ON'
                          : 'Net Fail: OFF',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

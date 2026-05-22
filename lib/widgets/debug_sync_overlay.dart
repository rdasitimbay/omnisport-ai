import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/offline_sync_service.dart';
import '../services/secure_hive_service.dart';

/// Overlay de debug — esquina inferior izquierda, colapsable con tap.
class DebugSyncOverlay extends StatefulWidget {
  const DebugSyncOverlay({Key? key}) : super(key: key);

  @override
  State<DebugSyncOverlay> createState() => _DebugSyncOverlayState();
}

class _DebugSyncOverlayState extends State<DebugSyncOverlay> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 16,
      left: 12,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: IntrinsicWidth(
            child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.7), width: 1.2),
            ),
            child: ValueListenableBuilder(
              valueListenable:
                  Hive.isBoxOpen(SecureHiveService.pendingSyncBoxName)
                  ? SecureHiveService.pendingSyncBox.listenable()
                  : ValueNotifier(null),
              builder: (context, box, _) {
                final isKeyLoaded = Hive.isBoxOpen(SecureHiveService.pendingSyncBoxName);
                final pendingCount = isKeyLoaded
                    ? SecureHiveService.pendingSyncBox.length
                    : 0;
                final hasIssues = pendingCount > 0 || !isKeyLoaded;

                // ── Colapsado: solo chip de estado ───────────────────────
                if (!_expanded) {
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.build_circle_outlined,
                        color: hasIssues ? Colors.orangeAccent : Colors.greenAccent,
                        size: 13),
                    const SizedBox(width: 5),
                    Text('Sentinel',
                        style: TextStyle(
                          color: hasIssues ? Colors.orangeAccent : Colors.greenAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        )),
                    if (pendingCount > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('$pendingCount',
                            style: const TextStyle(color: Colors.white, fontSize: 9)),
                      ),
                    ],
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_less, color: Colors.white38, size: 12),
                  ]);
                }

                // ── Expandido: panel completo ─────────────────────────────
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      const Text('>> Sync Sentinel',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold,
                              fontSize: 11)),
                      const Spacer(),
                      const Icon(Icons.expand_more, color: Colors.white38, size: 12),
                    ]),
                    const SizedBox(height: 6),
                    Text('Pending Records: $pendingCount',
                        style: const TextStyle(color: Colors.cyanAccent, fontSize: 10)),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('AES Key: ',
                          style: TextStyle(color: Colors.white54, fontSize: 10)),
                      Icon(isKeyLoaded ? Icons.check_circle : Icons.cancel,
                          color: isKeyLoaded ? Colors.greenAccent : Colors.redAccent,
                          size: 11),
                    ]),
                    const SizedBox(height: 2),
                    Text('Last Response: ${OfflineSyncService.lastSyncResponse}',
                        style: const TextStyle(color: Colors.white54, fontSize: 9),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => setState(() {
                        OfflineSyncService.forceOfflineMode =
                            !OfflineSyncService.forceOfflineMode;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: OfflineSyncService.forceOfflineMode
                              ? Colors.redAccent.withValues(alpha: 0.3)
                              : Colors.white12,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: OfflineSyncService.forceOfflineMode
                                ? Colors.redAccent
                                : Colors.white24,
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            OfflineSyncService.forceOfflineMode ? Icons.wifi_off : Icons.wifi,
                            color: Colors.white, size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            OfflineSyncService.forceOfflineMode ? 'Net Fail: ON' : 'Net Fail: OFF',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ]),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          ),
        ),
      ),
    );
  }
}

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'attendance_history_screen.dart';
import 'tablas_screen.dart';
import 'qr_generator_screen.dart';
import 'lopdp_vault_screen.dart';

/// Vista del representante (rol: parent).
/// Muestra en tiempo real el estado de presencia de cada hijo vinculado
/// a través de la relación de /parent_children/{parentUid}, más las
/// acciones rápidas y estadísticas de rendimiento en tiempo real.
class ParentDashboardScreen extends StatelessWidget {
  final String parentUid;

  const ParentDashboardScreen({super.key, required this.parentUid});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF0A192F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Mis Deportistas',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.1),
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.square_arrow_right, color: Colors.white54),
            tooltip: 'Cerrar sesión',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF001F3F), Color(0xFF0A192F)],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('parent_children')
                .doc(parentUid)
                .snapshots(),
            builder: (context, parentSnap) {
              if (parentSnap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
              }
              if (!parentSnap.hasData || !parentSnap.data!.exists) {
                return _buildEmpty(context);
              }
              final parentData = parentSnap.data!.data() as Map<String, dynamic>?;
              final childrenIds = List<String>.from(parentData?['childrenIds'] ?? []);
              if (childrenIds.isEmpty) {
                return _buildEmpty(context);
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('athletes')
                    .where(FieldPath.documentId, whereIn: childrenIds)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
                  }
                  if (!snap.hasData || snap.data!.docs.isEmpty) {
                    return _buildEmpty(context);
                  }
                  final athletes = snap.data!.docs;
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      _buildWelcomeHeader(),
                      const SizedBox(height: 16),
                      
                      // ── ⚡ Acciones Rápidas (Parent) ──
                      _buildParentQuickActions(context, athletes),
                      const SizedBox(height: 16),
                      
                      ...athletes.map((doc) => _ChildCard(
                        athleteDoc: doc,
                        onViewHistory: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => AttendanceHistoryScreen(
                            athleteUid:  doc.id,
                            athleteName: (doc.data() as Map)['full_name'] as String? ?? 'Atleta',
                          )),
                        ),
                      )),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.person_2_fill,
                  color: Color(0xFF00E5FF), size: 28),
            ),
            const SizedBox(width: 16),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Portal del Representante',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold,
                      fontSize: 16)),
              SizedBox(height: 2),
              Text('Monitoreo en tiempo real',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _buildParentQuickActions(BuildContext context, List<QueryDocumentSnapshot> athletes) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '⚡ Acciones Rápidas',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _parentActionButton(
                      icon: Icons.emoji_events,
                      label: 'Torneos',
                      subtitle: 'Fixtures',
                      color: const Color(0xFFFFB300),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TablasScreen()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _parentActionButton(
                      icon: CupertinoIcons.barcode_viewfinder,
                      label: 'Identidad',
                      subtitle: 'QR Deportista',
                      color: Colors.greenAccent,
                      onTap: () => _openQrForChild(context, athletes),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _parentActionButton(
                      icon: Icons.shield_rounded,
                      label: 'Privacidad',
                      subtitle: 'Bóveda LOPDP',
                      color: const Color(0xFF00E5FF),
                      onTap: () => _openLopdpForChild(context, athletes),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _parentActionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 9,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openQrForChild(BuildContext context, List<QueryDocumentSnapshot> athletes) {
    if (athletes.isEmpty) return;
    if (athletes.length == 1) {
      final doc = athletes.first;
      Navigator.push(context, MaterialPageRoute(builder: (_) => QrGeneratorScreen(athleteUid: doc.id)));
      return;
    }
    _showChildSelector(
      context,
      athletes,
      'Generar QR de Acceso',
      (doc) => Navigator.push(context, MaterialPageRoute(builder: (_) => QrGeneratorScreen(athleteUid: doc.id))),
    );
  }

  void _openLopdpForChild(BuildContext context, List<QueryDocumentSnapshot> athletes) {
    if (athletes.isEmpty) return;
    if (athletes.length == 1) {
      final doc = athletes.first;
      final name = (doc.data() as Map)['full_name'] as String? ?? 'Atleta';
      Navigator.push(context, MaterialPageRoute(builder: (_) => LopdpVaultScreen(athleteUid: doc.id, athleteName: name)));
      return;
    }
    _showChildSelector(
      context,
      athletes,
      'Bóveda de Privacidad LOPDP',
      (doc) {
        final name = (doc.data() as Map)['full_name'] as String? ?? 'Atleta';
        Navigator.push(context, MaterialPageRoute(builder: (_) => LopdpVaultScreen(athleteUid: doc.id, athleteName: name)));
      },
    );
  }

  void _showChildSelector(
    BuildContext context,
    List<QueryDocumentSnapshot> athletes,
    String title,
    void Function(QueryDocumentSnapshot) onSelected,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1B3E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: athletes.map((doc) {
                    final name = (doc.data() as Map)['full_name'] as String? ?? 'Sin nombre';
                    final category = (doc.data() as Map)['teamOrCategory'] as String? ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white12,
                            ),
                            child: const Icon(CupertinoIcons.person_fill, color: Color(0xFF00E5FF)),
                          ),
                          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          subtitle: Text(category, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          onTap: () {
                            Navigator.pop(ctx);
                            onSelected(doc);
                          },
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(CupertinoIcons.person_badge_minus,
            size: 64, color: Colors.white.withValues(alpha: 0.15)),
        const SizedBox(height: 16),
        const Text('No tienes deportistas vinculados',
            style: TextStyle(color: Colors.white54, fontSize: 16)),
        const SizedBox(height: 8),
        const Text('Contacta al administrador del club\npara vincular a tus hijos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 13)),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () => FirebaseAuth.instance.signOut(),
          icon: const Icon(Icons.logout, color: Colors.white38),
          label: const Text('Cerrar sesión', style: TextStyle(color: Colors.white38)),
        ),
      ]),
    );
  }
}

// ── Tarjeta de cada hijo ─────────────────────────────────────────────────────
class _ChildCard extends StatelessWidget {
  final QueryDocumentSnapshot athleteDoc;
  final VoidCallback onViewHistory;

  const _ChildCard({required this.athleteDoc, required this.onViewHistory});

  @override
  Widget build(BuildContext context) {
    final data     = athleteDoc.data() as Map<String, dynamic>;
    final uid      = athleteDoc.id;
    final name     = (data['full_name'] as String?) ?? 'Sin nombre';
    final category = (data['teamOrCategory'] as String?) ?? '';
    final photoUrl = data['photoUrl'] as String?;
    final isMinor  = (data['isMinor'] as bool?) ?? true;

    // Rango del día de hoy en UTC (Firestore almacena UTC — igual que BUG-11)
    final now      = DateTime.now().toUtc();
    final startDay = Timestamp.fromDate(DateTime.utc(now.year, now.month, now.day));
    final endDay   = Timestamp.fromDate(DateTime.utc(now.year, now.month, now.day + 1));

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('attendance_logs')
            .where('athleteUid', isEqualTo: uid)
            .where('timestamp', isGreaterThanOrEqualTo: startDay)
            .where('timestamp', isLessThanOrEqualTo: endDay)
            .orderBy('timestamp', descending: true)
            .limit(10)
            .snapshots(),
        builder: (context, logSnap) {
          final logs      = logSnap.data?.docs ?? [];
          final lastLog   = logs.isNotEmpty ? logs.first.data() as Map : null;
          final lastAction = lastLog?['action'] as String?;
          final lastTs    = lastLog?['timestamp'] as Timestamp?;

          final isPresent = lastAction == 'ingreso';
          final statusColor = isPresent
              ? const Color(0xFF00E5FF)
              : (lastAction == 'salida' ? Colors.orange : Colors.white30);
          final statusLabel = lastAction == 'ingreso'
              ? 'En entrenamiento'
              : (lastAction == 'salida' ? 'Salió del entrenamiento' : 'Sin actividad hoy');
          final statusIcon = lastAction == 'ingreso'
              ? CupertinoIcons.checkmark_shield_fill
              : (lastAction == 'salida'
                  ? CupertinoIcons.arrow_left_circle_fill
                  : CupertinoIcons.clock);

          return ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: isPresent ? 0.09 : 0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: statusColor.withValues(alpha: isPresent ? 0.4 : 0.15),
                  ),
                ),
                child: Column(children: [
                  // ── Cabecera del atleta ──────────────────────────────
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                        backgroundColor: statusColor.withValues(alpha: 0.2),
                        child: photoUrl == null
                            ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(
                                    color: statusColor, fontWeight: FontWeight.bold,
                                    fontSize: 18))
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(name,
                                style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            if (isMinor) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('MENOR',
                                    style: TextStyle(color: Colors.amber, fontSize: 8,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ]),
                          const SizedBox(height: 2),
                          Text(category,
                              style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        ],
                      )),
                      // Indicador de estado
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Icon(statusIcon, color: statusColor, size: 24),
                        const SizedBox(height: 4),
                        if (lastTs != null)
                          Text(
                            DateFormat('HH:mm').format(lastTs.toDate().toLocal()),
                            style: TextStyle(color: statusColor, fontSize: 13,
                                fontWeight: FontWeight.bold),
                          ),
                      ]),
                    ]),
                  ),

                  // ── Banda de estado ──────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.08),
                      border: Border(
                        top: BorderSide(color: statusColor.withValues(alpha: 0.15)),
                      ),
                    ),
                    child: Text(statusLabel,
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),

                  // ── Últimos movimientos del día ──────────────────────
                  if (logs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Movimientos de hoy',
                              style: TextStyle(color: Colors.white38, fontSize: 11,
                                  fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                          const SizedBox(height: 6),
                          ...logs.take(3).map((log) {
                            final d      = log.data() as Map;
                            final action = d['action'] as String? ?? 'ingreso';
                            final ts     = d['timestamp'] as Timestamp?;
                            final time   = ts != null
                                ? DateFormat('HH:mm').format(ts.toDate().toLocal())
                                : '--:--';
                            final color  = action == 'ingreso'
                                ? const Color(0xFF00E5FF)
                                : Colors.orange;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(children: [
                                Icon(
                                  action == 'ingreso'
                                      ? CupertinoIcons.arrow_right_circle_fill
                                      : CupertinoIcons.arrow_left_circle_fill,
                                  color: color, size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  action == 'ingreso' ? 'Ingresó' : 'Salió',
                                  style: TextStyle(color: color, fontSize: 12),
                                ),
                                const Spacer(),
                                Text(time,
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 12)),
                              ]),
                            );
                          }),
                        ],
                      ),
                    ),

                  // ── Rendimiento y Entrenamientos (Read-Only) ─────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('athletes')
                          .doc(uid)
                          .collection('historial_entrenamientos')
                          .orderBy('fecha', descending: true)
                          .limit(3)
                          .snapshots(),
                      builder: (context, sessSnap) {
                        final sessions = sessSnap.data?.docs ?? [];
                        if (sessSnap.connectionState == ConnectionState.waiting) {
                          return const SizedBox(
                            height: 40,
                            child: Center(
                              child: SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(color: Color(0xFF00E5FF), strokeWidth: 2),
                              ),
                            ),
                          );
                        }

                        if (sessions.isEmpty) {
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.white30, size: 16),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Sin entrenamientos o métricas de rendimiento reportados recientemente.',
                                    style: TextStyle(color: Colors.white30, fontSize: 11, height: 1.3),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(CupertinoIcons.graph_circle_fill, color: Colors.purpleAccent, size: 14),
                                SizedBox(width: 6),
                                Text(
                                  'Historial de Rendimiento',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...sessions.map((sess) {
                              final sData = sess.data() as Map<String, dynamic>;
                              final titulo = sData['titulo'] ?? 'Sesión de Entreno';
                              final duracion = sData['duracion'] ?? 90;
                              final intensidad = (sData['intensidad'] ?? 'MEDIA').toString().toUpperCase();
                              final observaciones = sData['observaciones'] ?? '';
                              final fechaTs = sData['fecha'] as Timestamp?;
                              final fechaStr = fechaTs != null
                                  ? DateFormat('dd MMM').format(fechaTs.toDate())
                                  : 'Hoy';

                              Color colorIntensidad = const Color(0xFFFFB300);
                              if (intensidad == 'BAJA') colorIntensidad = const Color(0xFF00E676);
                              if (intensidad == 'ALTA') colorIntensidad = const Color(0xFFFF1744);

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              titulo.toString().toUpperCase(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            fechaStr,
                                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(CupertinoIcons.stopwatch, color: Colors.white38, size: 12),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$duracion min',
                                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                                          ),
                                          const SizedBox(width: 12),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: colorIntensidad.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'INTENSIDAD: $intensidad',
                                              style: TextStyle(
                                                color: colorIntensidad,
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (observaciones.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          observaciones,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 10,
                                            fontStyle: FontStyle.italic,
                                            height: 1.3,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    ),
                  ),

                  // ── Botón de historial ───────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: GestureDetector(
                      onTap: onViewHistory,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const Center(
                          child: Text('Ver bitácora de asistencias',
                              style: TextStyle(color: Colors.white54, fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

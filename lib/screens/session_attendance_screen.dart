import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

/// Panel de asistencia en tiempo real para coach / admin.
/// Muestra todos los atletas de la institución agrupados por estado:
///   • Presente  — último log de hoy es "ingreso"
///   • Salida    — último log de hoy es "salida"
///   • Ausente   — sin log hoy
/// Permite marcar asistencia manual (sin QR).
class SessionAttendanceScreen extends StatefulWidget {
  final String institutionId;
  final String coachName;

  const SessionAttendanceScreen({
    super.key,
    required this.institutionId,
    required this.coachName,
  });

  @override
  State<SessionAttendanceScreen> createState() => _SessionAttendanceScreenState();
}

class _SessionAttendanceScreenState extends State<SessionAttendanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  String _selectedCategory = 'Todas';
  List<String> _categories = ['Todas'];

  // Comienzo y fin de hoy en UTC (Firestore almacena UTC)
  late final Timestamp _todayStart;
  late final Timestamp _todayEnd;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    final now = DateTime.now().toLocal();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay   = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _todayStart = Timestamp.fromDate(startOfDay);
    _todayEnd   = Timestamp.fromDate(endOfDay);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Determina el estado del atleta según sus logs de hoy ───────────────
  String _resolveStatus(String athleteUid, List<QueryDocumentSnapshot> todayLogs) {
    final myLogs = todayLogs
        .where((d) => (d.data() as Map)['athleteUid'] == athleteUid)
        .toList()
      ..sort((a, b) {
        final ta = ((a.data() as Map)['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final tb = ((b.data() as Map)['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta); // más reciente primero
      });
    if (myLogs.isEmpty) return 'ausente';
    final lastAction = (myLogs.first.data() as Map)['action'] as String? ?? 'ingreso';
    return lastAction == 'ingreso' ? 'presente' : 'salida';
  }

  // ── Registro manual de asistencia ────────────────────────────────────────
  Future<void> _markManual(String athleteUid, String action) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('attendance_logs').add({
      'athleteUid': athleteUid,
      'scannedBy':  user.uid,
      'action':     action,
      'location':   'Manual — ${widget.coachName}',
      'timestamp':  FieldValue.serverTimestamp(),
      'status':     'manual',
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(action == 'ingreso' ? 'Ingreso registrado' : 'Salida registrada'),
      backgroundColor: action == 'ingreso' ? const Color(0xFF00C853) : Colors.orange,
    ));
  }

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
          'Panel de Sesión',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.1),
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: const Color(0xFF00E5FF),
          labelColor: const Color(0xFF00E5FF),
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(text: 'PRESENTES', icon: Icon(CupertinoIcons.checkmark_circle_fill, size: 16)),
            Tab(text: 'SALIDA',    icon: Icon(CupertinoIcons.arrow_left_circle_fill, size: 16)),
            Tab(text: 'AUSENTES',  icon: Icon(CupertinoIcons.xmark_circle_fill, size: 16)),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF001F3F), Color(0xFF0A192F)],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<QuerySnapshot>(
            // Stream de atletas de la institución
            stream: FirebaseFirestore.instance
                .collection('athletes')
                .where('ownerInstitutionId', isEqualTo: widget.institutionId)
                .snapshots(),
            builder: (context, athleteSnap) {
              if (!athleteSnap.hasData) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
              }
              final allAthletes = athleteSnap.data!.docs;

              // Recopilar categorías únicas
              final cats = <String>{'Todas'};
              for (final d in allAthletes) {
                final cat = (d.data() as Map)['teamOrCategory'] as String?;
                if (cat != null && cat.isNotEmpty) cats.add(cat);
              }
              final sortedCats = cats.toList()..sort();
              if (!listEquals(sortedCats, _categories)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _categories = sortedCats);
                });
              }

              final filtered = _selectedCategory == 'Todas'
                  ? allAthletes
                  : allAthletes.where((d) =>
                      (d.data() as Map)['teamOrCategory'] == _selectedCategory).toList();

              return StreamBuilder<QuerySnapshot>(
                // Stream de logs de hoy
                stream: FirebaseFirestore.instance
                    .collection('attendance_logs')
                    .where('timestamp', isGreaterThanOrEqualTo: _todayStart)
                    .where('timestamp', isLessThanOrEqualTo: _todayEnd)
                    .snapshots(),
                builder: (context, logSnap) {
                  final todayLogs = logSnap.data?.docs ?? [];

                  final presentes = <QueryDocumentSnapshot>[];
                  final salida    = <QueryDocumentSnapshot>[];
                  final ausentes  = <QueryDocumentSnapshot>[];

                  for (final athlete in filtered) {
                    final st = _resolveStatus(athlete.id, todayLogs);
                    if (st == 'presente') presentes.add(athlete);
                    else if (st == 'salida') salida.add(athlete);
                    else ausentes.add(athlete);
                  }

                  return Column(
                    children: [
                      // ── Filtro de categoría + resumen ──────────────────
                      _buildHeader(presentes.length, salida.length, ausentes.length),

                      // ── Tabs ──────────────────────────────────────────
                      Expanded(
                        child: TabBarView(
                          controller: _tab,
                          children: [
                            _buildAthleteList(presentes, todayLogs, 'presente'),
                            _buildAthleteList(salida, todayLogs, 'salida'),
                            _buildAthleteList(ausentes, todayLogs, 'ausente'),
                          ],
                        ),
                      ),
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

  Widget _buildHeader(int presentes, int salida, int ausentes) {
    final total = presentes + salida + ausentes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          // Filtro de categoría
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _categories.map((cat) {
                final selected = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF00E5FF).withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? const Color(0xFF00E5FF) : Colors.white24,
                        ),
                      ),
                      child: Text(cat,
                          style: TextStyle(
                            color: selected ? const Color(0xFF00E5FF) : Colors.white54,
                            fontSize: 12, fontWeight: FontWeight.w600,
                          )),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          // Resumen de conteos
          Row(children: [
            _statChip(presentes, 'Presentes', const Color(0xFF00E5FF)),
            const SizedBox(width: 8),
            _statChip(salida, 'Salida', Colors.orange),
            const SizedBox(width: 8),
            _statChip(ausentes, 'Ausentes', Colors.redAccent),
            const Spacer(),
            Text('$total atletas',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          Text(
            DateFormat("EEEE d 'de' MMMM", 'es').format(DateTime.now()),
            style: const TextStyle(color: Colors.white24, fontSize: 11),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _statChip(int count, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text('$count $label',
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildAthleteList(
    List<QueryDocumentSnapshot> athletes,
    List<QueryDocumentSnapshot> todayLogs,
    String statusKey,
  ) {
    if (athletes.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(CupertinoIcons.person_3,
              size: 48, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 12),
          Text('Sin atletas en esta categoría',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: athletes.length,
      itemBuilder: (context, i) {
        final data = athletes[i].data() as Map<String, dynamic>;
        final uid  = athletes[i].id;

        // Último log de este atleta hoy
        final myLogs = todayLogs
            .where((d) => (d.data() as Map)['athleteUid'] == uid)
            .toList()
          ..sort((a, b) {
            final ta = ((a.data() as Map)['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final tb = ((b.data() as Map)['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            return tb.compareTo(ta);
          });
        final lastLog = myLogs.isNotEmpty ? myLogs.first.data() as Map : null;
        final lastTs  = lastLog?['timestamp'] as Timestamp?;
        final timeStr = lastTs != null
            ? DateFormat('HH:mm').format(lastTs.toDate().toLocal())
            : null;

        return _AthleteAttendanceCard(
          uid:        uid,
          name:       (data['full_name'] as String?) ?? 'Sin nombre',
          category:   (data['teamOrCategory'] as String?) ?? '',
          photoUrl:   data['photoUrl'] as String?,
          isMinor:    (data['isMinor'] as bool?) ?? false,
          statusKey:  statusKey,
          timeStr:    timeStr,
          onIngreso: () => _markManual(uid, 'ingreso'),
          onSalida:  () => _markManual(uid, 'salida'),
        );
      },
    );
  }
}

// ── Tarjeta individual de atleta ─────────────────────────────────────────────
class _AthleteAttendanceCard extends StatelessWidget {
  final String uid;
  final String name;
  final String category;
  final String? photoUrl;
  final bool isMinor;
  final String statusKey;
  final String? timeStr;
  final VoidCallback onIngreso;
  final VoidCallback onSalida;

  const _AthleteAttendanceCard({
    required this.uid,
    required this.name,
    required this.category,
    required this.photoUrl,
    required this.isMinor,
    required this.statusKey,
    required this.timeStr,
    required this.onIngreso,
    required this.onSalida,
  });

  Color get _statusColor {
    if (statusKey == 'presente') return const Color(0xFF00E5FF);
    if (statusKey == 'salida')   return Colors.orange;
    return Colors.redAccent;
  }

  IconData get _statusIcon {
    if (statusKey == 'presente') return CupertinoIcons.checkmark_circle_fill;
    if (statusKey == 'salida')   return CupertinoIcons.arrow_left_circle_fill;
    return CupertinoIcons.xmark_circle_fill;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _statusColor.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              // Avatar
              CircleAvatar(
                radius: 22,
                backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
                backgroundColor: _statusColor.withValues(alpha: 0.2),
                child: photoUrl == null
                    ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(color: _statusColor, fontWeight: FontWeight.bold))
                    : null,
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    if (isMinor) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  if (timeStr != null)
                    Text('Reg. $timeStr',
                        style: TextStyle(color: _statusColor.withValues(alpha: 0.7), fontSize: 10)),
                ]),
              ),

              // Estado + acciones manuales
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Icon(_statusIcon, color: _statusColor, size: 22),
                const SizedBox(height: 6),
                if (statusKey == 'ausente')
                  GestureDetector(
                    onTap: onIngreso,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.4)),
                      ),
                      child: const Text('+ Ingreso',
                          style: TextStyle(color: Color(0xFF00E5FF), fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                if (statusKey == 'presente')
                  GestureDetector(
                    onTap: onSalida,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                      ),
                      child: const Text('Salida',
                          style: TextStyle(color: Colors.orange, fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

bool listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

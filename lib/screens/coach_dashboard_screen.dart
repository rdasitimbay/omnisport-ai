import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import 'qr_scanner_screen.dart';
import 'sos_alert_screen.dart';
import 'attendance_history_screen.dart';
import 'tablas_screen.dart';

class CoachDashboardScreen extends StatefulWidget {
  final String coachUid;
  final String institutionId;

  const CoachDashboardScreen({
    super.key,
    required this.coachUid,
    required this.institutionId,
  });

  @override
  State<CoachDashboardScreen> createState() => _CoachDashboardScreenState();
}

class _CoachDashboardScreenState extends State<CoachDashboardScreen> with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchCtrl = TextEditingController();
  
  late TabController _mainTab;
  
  // Atletas Tab state
  String _searchQuery = '';
  String _selectedFilter = 'todos'; 
  
  // Asistencia Tab state
  int _attendanceSubTab = 0; // 0: Hoy, 1: Mensual, 2: Reportes
  String _selectedCategoryHoy = 'Todas';
  
  late String _reportMonth; // format: 'YYYY-MM'

  @override
  void initState() {
    super.initState();
    _mainTab = TabController(length: 3, vsync: this);
    final now = DateTime.now();
    _reportMonth = DateFormat('yyyy-MM').format(now);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _mainTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF001F3F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Gobernanza Deportiva',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.square_arrow_right, color: Colors.white70),
            tooltip: 'Cerrar sesión',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
        bottom: TabBar(
          controller: _mainTab,
          indicatorColor: const Color(0xFF00E5FF),
          labelColor: const Color(0xFF00E5FF),
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(CupertinoIcons.home, size: 20), text: 'PANEL'),
            Tab(icon: Icon(CupertinoIcons.group, size: 20), text: 'ATLETAS'),
            Tab(icon: Icon(CupertinoIcons.chart_bar_alt_fill, size: 20), text: 'ASISTENCIA'),
          ],
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF001F3F), Color(0xFF000D1A)],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db.collection('athletes').where('ownerInstitutionId', isEqualTo: widget.institutionId).snapshots(),
            builder: (context, athletesSnap) {
              if (athletesSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
              }
              final athletes = athletesSnap.data?.docs ?? [];
              
              final now = DateTime.now();
              final thirtyDaysAgo = Timestamp.fromDate(now.subtract(const Duration(days: 30)));
              
              return StreamBuilder<QuerySnapshot>(
                stream: _db.collection('attendance_logs').where('timestamp', isGreaterThanOrEqualTo: thirtyDaysAgo).snapshots(),
                builder: (context, logsSnap) {
                  final logs = logsSnap.data?.docs ?? [];
                  
                  return TabBarView(
                    controller: _mainTab,
                    children: [
                      _buildPanelTab(athletes, logs),
                      _buildAthletesTab(athletes, logs),
                      _buildAttendanceTab(athletes, logs),
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

  // ===========================================================================
  // TAB 0: PANEL
  // ===========================================================================
  Widget _buildPanelTab(List<QueryDocumentSnapshot> athletes, List<QueryDocumentSnapshot> logs) {
    int total = athletes.length;
    
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayLogs = logs.where((l) {
      final t = (l.data() as Map)['timestamp'] as Timestamp?;
      if (t == null) return false;
      return DateFormat('yyyy-MM-dd').format(t.toDate().toLocal()) == todayStr;
    }).toList();
    
    final presentesHoyUids = <String>{};
    for (var log in todayLogs) {
      final data = log.data() as Map;
      if (data['action'] == 'ingreso') {
        presentesHoyUids.add(data['athleteUid']);
      } else if (data['action'] == 'salida') {
        presentesHoyUids.remove(data['athleteUid']);
      }
    }
    
    int issues = athletes.where((a) {
      final s = ((a.data() as Map)['status'] ?? '').toString().toLowerCase();
      return s.contains('lesionado') || s.contains('pago') || s.contains('no apto');
    }).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Cabecera ──────────────────────────────────────────────────────────
        _glassCard(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                  border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
                ),
                child: const Icon(CupertinoIcons.person_2_fill, color: Color(0xFF00E5FF), size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Panel de Entrenador', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('Sede: ${widget.institutionId.toUpperCase()}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── KPIs ─────────────────────────────────────────────────
        Row(
          children: [
            Expanded(child: _buildStatTile('Total Atletas', total.toString(), const Color(0xFF00E5FF))),
            const SizedBox(width: 8),
            Expanded(child: _buildStatTile('Presentes Hoy', presentesHoyUids.length.toString(), const Color(0xFF00E676))),
            const SizedBox(width: 8),
            Expanded(child: _buildStatTile('Con Problemas', issues.toString(), const Color(0xFFFF1744))),
          ],
        ),
        const SizedBox(height: 16),

        // ── ⚡ Acciones Rápidas (Coach) ────────────────────────────────
        // Requerimiento: Torneos · Zero Trust · Historial · S.O.S · Rendimiento
        _glassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('⚡ Acciones Rápidas',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14,
                      letterSpacing: 0.5)),
              const SizedBox(height: 16),
              // Fila 1: Torneos | Zero Trust
              Row(
                children: [
                  Expanded(
                    child: _coachActionButton(
                      icon: Icons.emoji_events,
                      label: 'Torneos',
                      subtitle: 'Fixtures',
                      color: const Color(0xFFFFB300),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const TablasScreen())),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _coachActionButton(
                      icon: CupertinoIcons.barcode_viewfinder,
                      label: 'Zero Trust',
                      subtitle: 'Escáner QR',
                      color: Colors.greenAccent,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const QrScannerScreen())),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Fila 2: Historial | S.O.S | Rendimiento
              Row(
                children: [
                  Expanded(
                    child: _coachActionButton(
                      icon: CupertinoIcons.clock_fill,
                      label: 'Historial',
                      subtitle: 'Bitácora',
                      color: const Color(0xFF00E5FF),
                      onTap: () {
                        // Abre asistencia del primer atleta del coach como demo.
                        // En producción se abre un selector de atleta.
                        _mainTab.animateTo(2);
                        setState(() => _attendanceSubTab = 0);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _coachActionButton(
                      icon: Icons.emergency,
                      label: 'S.O.S',
                      subtitle: 'Emergencia',
                      color: const Color(0xFFFF1744),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(
                            builder: (_) => SosAlertScreen(
                              athleteUid: widget.coachUid,
                              athleteName: 'Coach',
                            ),
                          )),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _coachActionButton(
                      icon: CupertinoIcons.graph_circle_fill,
                      label: 'Rendim.',
                      subtitle: 'Métricas',
                      color: Colors.purpleAccent,
                      onTap: () {
                        _mainTab.animateTo(1);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Gráfica de actividad semanal ───────────────────────────────
        _glassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Actividad Semanal (Asistencia global)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 20),
              SizedBox(
                height: 120,
                child: CustomPaint(
                  size: const Size(double.infinity, 120),
                  painter: WeeklyChartPainter(logs, total),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildStatTile(String label, String value, Color color) {
    return _glassCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      borderColor: color.withValues(alpha: 0.25),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: ATLETAS
  // ===========================================================================
  Widget _buildAthletesTab(List<QueryDocumentSnapshot> athletes, List<QueryDocumentSnapshot> logs) {
    final filtered = athletes.where((doc) {
      final data = doc.data() as Map;
      final name = (data['full_name'] as String? ?? '').toLowerCase();
      final cat = (data['teamOrCategory'] as String? ?? '').toLowerCase();
      final status = (data['status'] as String? ?? '').toLowerCase();
      
      final matchesSearch = name.contains(_searchQuery.toLowerCase()) || cat.contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;

      if (_selectedFilter == 'todos') return true;
      if (_selectedFilter == 'apto') return status.contains('apto') || status.contains('al dia') || status.contains('autorizado');
      if (_selectedFilter == 'lesionado') return status.contains('lesionado') || status.contains('no apto');
      if (_selectedFilter == 'pago') return status.contains('pago');
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _buildSearchBar(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _buildFilters(),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState('No se encontraron atletas')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) => _buildAthleteCard(filtered[i], logs),
                ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return _glassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Buscar atleta por nombre o equipo...',
          hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
          border: InputBorder.none,
          icon: const Icon(CupertinoIcons.search, color: Colors.cyanAccent, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    setState(() {
                      _searchCtrl.clear();
                      _searchQuery = '';
                    });
                  },
                  child: const Icon(Icons.clear, color: Colors.white54, size: 18),
                )
              : null,
        ),
        onChanged: (val) => setState(() => _searchQuery = val),
      ),
    );
  }

  Widget _buildFilters() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _filterPill('Todos', 'todos', Colors.white),
        _filterPill('Aptos', 'apto', const Color(0xFF00E676)),
        _filterPill('Lesión', 'lesionado', const Color(0xFFFF1744)),
        _filterPill('Pago', 'pago', const Color(0xFFFFB300)),
      ],
    );
  }

  Widget _filterPill(String label, String filterKey, Color activeColor) {
    final active = _selectedFilter == filterKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = filterKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? activeColor.withValues(alpha: 0.5) : Colors.white12, width: 1),
        ),
        child: Text(label, style: TextStyle(color: active ? activeColor : Colors.white38, fontSize: 11, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.person_3_fill, color: Colors.white.withValues(alpha: 0.15), size: 64),
          const SizedBox(height: 12),
          Text(msg, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildAthleteCard(QueryDocumentSnapshot doc, List<QueryDocumentSnapshot> logs) {
    final data = doc.data() as Map;
    final name = data['full_name'] ?? 'Sin nombre';
    final category = data['teamOrCategory'] ?? 'Sin categoría';
    final status = data['status'] ?? 'Inactivo';
    final photoUrl = data['photoUrl'] ?? '';

    Color neonColor = const Color(0xFFB0BEC5);
    String lowerStatus = status.toString().trim().toLowerCase();
    if (lowerStatus.contains('apto') || lowerStatus.contains('autorizado') || lowerStatus.contains('al dia')) {
      neonColor = const Color(0xFF00E676);
    } else if (lowerStatus.contains('pago')) {
      neonColor = const Color(0xFFFFB300);
    } else if (lowerStatus.contains('lesionado') || lowerStatus.contains('no apto')) {
      neonColor = const Color(0xFFFF1744);
    }

    final currentMonthStr = DateFormat('yyyy-MM').format(DateTime.now());
    final athleteLogs = logs.where((l) {
      final m = l.data() as Map;
      if (m['athleteUid'] != doc.id) return false;
      final t = m['timestamp'] as Timestamp?;
      return t != null && DateFormat('yyyy-MM').format(t.toDate().toLocal()) == currentMonthStr;
    }).toList();
    
    final daysPresent = athleteLogs.map((l) => DateFormat('yyyy-MM-dd').format(((l.data() as Map)['timestamp'] as Timestamp).toDate().toLocal())).toSet().length;
    double pct = (daysPresent / 12.0) * 100;
    if (pct > 100) pct = 100;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: _glassCard(
        borderColor: neonColor.withValues(alpha: 0.35),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: neonColor, width: 2),
                    boxShadow: [BoxShadow(color: neonColor.withValues(alpha: 0.25), blurRadius: 10)],
                  ),
                  child: CircleAvatar(
                    backgroundColor: Colors.white12,
                    backgroundImage: photoUrl.toString().isNotEmpty ? NetworkImage(photoUrl) : null,
                    child: photoUrl.toString().isEmpty ? Text(name.toString().isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)) : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(category.toString().toUpperCase(), style: TextStyle(color: neonColor.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                            child: Text('Asist. ${pct.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: neonColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: neonColor.withValues(alpha: 0.4))),
                  child: Text(status.toString().toUpperCase(), style: TextStyle(color: neonColor, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Divider(color: Colors.white12, height: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _actionButton(icon: Icons.add_task_rounded, label: 'Registrar Entr.', color: const Color(0xFF00E5FF), onTap: () => _showAddSessionSheet(doc.id, name)),
                _actionButton(icon: Icons.history_rounded, label: 'Historial', color: Colors.white70, onTap: () => _showSessionHistoryDialog(doc.id, name)),
                _actionButton(icon: Icons.swap_horizontal_circle_outlined, label: 'Estado', color: const Color(0xFFFFAB40), onTap: () => _showStatusSelectorDialog(doc.id, name, status)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _coachActionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 22, color: color),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
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

  // ===========================================================================
  // TAB 2: ASISTENCIA
  // ===========================================================================
  Widget _buildAttendanceTab(List<QueryDocumentSnapshot> athletes, List<QueryDocumentSnapshot> logs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              _subTabBtn(0, 'Hoy', CupertinoIcons.clock),
              const SizedBox(width: 8),
              _subTabBtn(1, 'Mensual', CupertinoIcons.calendar),
              const SizedBox(width: 8),
              _subTabBtn(2, 'Reportes', CupertinoIcons.chart_bar),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _attendanceSubTab == 0
              ? _buildTodaySubTab(athletes, logs)
              : _attendanceSubTab == 1
                  ? _buildMonthlySubTab(athletes, logs)
                  : _buildReportsSubTab(athletes, logs),
        ),
      ],
    );
  }

  Widget _subTabBtn(int index, String label, IconData icon) {
    final active = _attendanceSubTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _attendanceSubTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF00E5FF).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? const Color(0xFF00E5FF) : Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: active ? const Color(0xFF00E5FF) : Colors.white54),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: active ? const Color(0xFF00E5FF) : Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  // --- HOY ---
  Widget _buildTodaySubTab(List<QueryDocumentSnapshot> athletes, List<QueryDocumentSnapshot> logs) {
    final cats = <String>{'Todas'};
    for (var a in athletes) {
      final c = (a.data() as Map)['teamOrCategory'] as String?;
      if (c != null && c.isNotEmpty) cats.add(c);
    }
    
    if (!cats.contains(_selectedCategoryHoy)) _selectedCategoryHoy = 'Todas';

    final filteredAthletes = _selectedCategoryHoy == 'Todas' 
        ? athletes 
        : athletes.where((a) => (a.data() as Map)['teamOrCategory'] == _selectedCategoryHoy).toList();

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayLogs = logs.where((l) {
      final t = (l.data() as Map)['timestamp'] as Timestamp?;
      if (t == null) return false;
      return DateFormat('yyyy-MM-dd').format(t.toDate().toLocal()) == todayStr;
    }).toList();

    final presentes = <QueryDocumentSnapshot>[];
    final salida = <QueryDocumentSnapshot>[];
    final ausentes = <QueryDocumentSnapshot>[];

    for (var a in filteredAthletes) {
      final myLogs = todayLogs.where((l) => (l.data() as Map)['athleteUid'] == a.id).toList()
        ..sort((x, y) => ((y.data() as Map)['timestamp'] as Timestamp).compareTo((x.data() as Map)['timestamp'] as Timestamp));
      
      if (myLogs.isEmpty) {
        ausentes.add(a);
      } else {
        final action = (myLogs.first.data() as Map)['action'];
        if (action == 'ingreso') presentes.add(a);
        else salida.add(a);
      }
    }

    return Column(
      children: [
        SizedBox(
          height: 36,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            children: cats.map((cat) {
              final active = cat == _selectedCategoryHoy;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedCategoryHoy = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: active ? Colors.blueAccent : Colors.white12),
                    ),
                    child: Text(cat, style: TextStyle(color: active ? Colors.blueAccent : Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (presentes.isNotEmpty) ...[
                const Text('✅ PRESENTES', style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                ...presentes.map((a) => _buildTodayAthleteCard(a, 'presente')),
                const SizedBox(height: 16),
              ],
              if (salida.isNotEmpty) ...[
                const Text('⬅ SALIDA REGISTRADA', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                ...salida.map((a) => _buildTodayAthleteCard(a, 'salida')),
                const SizedBox(height: 16),
              ],
              if (ausentes.isNotEmpty) ...[
                const Text('❌ AUSENTES', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                ...ausentes.map((a) => _buildTodayAthleteCard(a, 'ausente')),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTodayAthleteCard(QueryDocumentSnapshot doc, String statusKey) {
    final data = doc.data() as Map;
    final name = data['full_name'] ?? 'Sin nombre';
    final cat = data['teamOrCategory'] ?? '';

    Color color = Colors.redAccent;
    if (statusKey == 'presente') color = const Color(0xFF00E676);
    if (statusKey == 'salida') color = Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Text(name.toString().isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Text(cat, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          if (statusKey == 'ausente')
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), minimumSize: const Size(60, 30), padding: const EdgeInsets.symmetric(horizontal: 12)),
              onPressed: () => _markManual(doc.id, 'ingreso'),
              child: const Text('Marcar', style: TextStyle(fontSize: 10, color: Colors.white)),
            ),
          if (statusKey == 'presente')
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, minimumSize: const Size(60, 30), padding: const EdgeInsets.symmetric(horizontal: 12)),
              onPressed: () => _markManual(doc.id, 'salida'),
              child: const Text('Salida', style: TextStyle(fontSize: 10, color: Colors.white)),
            ),
        ],
      ),
    );
  }

  Future<void> _markManual(String uid, String action) async {
    final user = FirebaseAuth.instance.currentUser;
    await _db.collection('attendance_logs').add({
      'athleteUid': uid,
      'scannedBy': user?.uid ?? 'unknown',
      'action': action,
      'location': 'Manual - Coach',
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'manual',
    });
  }

  // --- MENSUAL ---
  Widget _buildMonthlySubTab(List<QueryDocumentSnapshot> athletes, List<QueryDocumentSnapshot> logs) {
    return Center(
      child: _glassCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.calendar_today, color: Colors.white38, size: 48),
            const SizedBox(height: 16),
            const Text('Grilla Mensual', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Filtro actual: $_reportMonth', style: const TextStyle(color: Colors.blueAccent)),
            const SizedBox(height: 16),
            const Text('Próximamente: Grilla tipo Admin para control masivo por día.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // --- REPORTES ---
  Widget _buildReportsSubTab(List<QueryDocumentSnapshot> athletes, List<QueryDocumentSnapshot> logs) {
    final Map<String, int> attendances = {};
    for (var a in athletes) { attendances[a.id] = 0; }
    
    for (var l in logs) {
      final uid = (l.data() as Map)['athleteUid'];
      if (attendances.containsKey(uid) && (l.data() as Map)['action'] == 'ingreso') {
        attendances[uid] = attendances[uid]! + 1;
      }
    }
    
    var sorted = attendances.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    var top5 = sorted.take(5).toList();
    var bottom5 = sorted.reversed.take(5).toList();

    String getName(String uid) {
      try {
        return (athletes.firstWhere((a) => a.id == uid).data() as Map)['full_name'] ?? 'Desconocido';
      } catch(e) { return 'Desconocido'; }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _glassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(CupertinoIcons.star_fill, color: Colors.amber, size: 20),
                  SizedBox(width: 8),
                  Text('Top 5 Asistencia (30 días)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const Divider(color: Colors.white12, height: 24),
              if (top5.isEmpty) const Text('No hay datos', style: TextStyle(color: Colors.white38)),
              ...top5.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(getName(e.key), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    Text('${e.value} ses.', style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              )),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _glassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.redAccent, size: 20),
                  SizedBox(width: 8),
                  Text('Más Ausentes (30 días)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const Divider(color: Colors.white12, height: 24),
              if (bottom5.isEmpty) const Text('No hay datos', style: TextStyle(color: Colors.white38)),
              ...bottom5.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(getName(e.key), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    Text('${e.value} ses.', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              )),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          icon: const Icon(CupertinoIcons.doc_text, color: Colors.white),
          label: const Text('Exportar Resumen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white12,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generando reporte en background...')));
          },
        ),
        const SizedBox(height: 32),
      ],
    );
  }


// ═══════════════════════════════════════════════════════════════════════════
  // MODAL — Registrar Sesión de Entrenamiento
  // ═══════════════════════════════════════════════════════════════════════════

  void _showAddSessionSheet(String athleteId, String athleteName) {
    final titleCtrl = TextEditingController(text: 'Práctica de Voleibol');
    final durationCtrl = TextEditingController(text: '90');
    String intensity = 'media';
    final notesCtrl = TextEditingController();
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D1B3E),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.add_task_rounded, color: Color(0xFF00E5FF), size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Registrar Sesión - ${athleteName.split(' ').first.toUpperCase()}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: titleCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _inputDecoration('Título del Entrenamiento (ej. Práctica de pases)'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: durationCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _inputDecoration('Duración en minutos (ej. 90)'),
                    ),
                    const SizedBox(height: 16),
                    const Text('Intensidad de la Sesión', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _intensityOption(ctx, (v) => setModalState(() => intensity = v), 'Baja', 'baja', intensity, const Color(0xFF00E676)),
                        _intensityOption(ctx, (v) => setModalState(() => intensity = v), 'Media', 'media', intensity, const Color(0xFFFFB300)),
                        _intensityOption(ctx, (v) => setModalState(() => intensity = v), 'Alta', 'alta', intensity, const Color(0xFFFF1744)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _inputDecoration('Notas de desempeño / Observaciones clínicas...'),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: submitting
                            ? null
                            : () async {
                                final title = titleCtrl.text.trim();
                                final durationStr = durationCtrl.text.trim();
                                if (title.isEmpty || durationStr.isEmpty) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('Por favor completa los campos obligatorios'), backgroundColor: Colors.orange),
                                  );
                                  return;
                                }

                                setModalState(() => submitting = true);

                                try {
                                  final duration = int.tryParse(durationStr) ?? 90;
                                  
                                  await _firestoreService.addTrainingSession(athleteId, {
                                    'titulo': title,
                                    'duracion': duration,
                                    'intensidad': intensity,
                                    'observaciones': notesCtrl.text.trim(),
                                  });

                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(content: Text('Sesión de entrenamiento registrada con éxito ✅'), backgroundColor: Colors.green),
                                    );
                                  }
                                } catch (e) {
                                  setModalState(() => submitting = false);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.redAccent),
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: submitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black87, strokeWidth: 2))
                            : const Text('GUARDAR REGISTRO', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _intensityOption(
    BuildContext ctx,
    Function(String) onSelect,
    String label,
    String value,
    String current,
    Color color,
  ) {
    final selected = current == value;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : Colors.white12, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(color: selected ? color : Colors.white38, fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }

  // Workaround para actualizar el Sheet sin rediseñar todo con Riverpod/Streams
  void _showAddSessionSheetWithIntensity({
    required String athleteId,
    required String athleteName,
    required String intensity,
  }) {
    // Reabre el sheet con la intensidad seleccionada
    final titleCtrl = TextEditingController(text: 'Práctica de Voleibol');
    final durationCtrl = TextEditingController(text: '90');
    final notesCtrl = TextEditingController();
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D1B3E),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.add_task_rounded, color: Color(0xFF00E5FF), size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Registrar Sesión',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: titleCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _inputDecoration('Título del Entrenamiento (ej. Práctica de pases)'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: durationCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _inputDecoration('Duración en minutos (ej. 90)'),
                    ),
                    const SizedBox(height: 16),
                    const Text('Intensidad de la Sesión', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _intensityOption(ctx, (v) => setModalState(() => intensity = v), 'Baja', 'baja', intensity, const Color(0xFF00E676)),
                        _intensityOption(ctx, (v) => setModalState(() => intensity = v), 'Media', 'media', intensity, const Color(0xFFFFB300)),
                        _intensityOption(ctx, (v) => setModalState(() => intensity = v), 'Alta', 'alta', intensity, const Color(0xFFFF1744)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _inputDecoration('Notas de desempeño / Observaciones clínicas...'),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: submitting
                            ? null
                            : () async {
                                final title = titleCtrl.text.trim();
                                final durationStr = durationCtrl.text.trim();
                                if (title.isEmpty || durationStr.isEmpty) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('Por favor completa los campos obligatorios'), backgroundColor: Colors.orange),
                                  );
                                  return;
                                }

                                setModalState(() => submitting = true);

                                try {
                                  final duration = int.tryParse(durationStr) ?? 90;
                                  
                                  await _firestoreService.addTrainingSession(athleteId, {
                                    'titulo': title,
                                    'duracion': duration,
                                    'intensidad': intensity,
                                    'observaciones': notesCtrl.text.trim(),
                                  });

                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(content: Text('Sesión de entrenamiento registrada con éxito ✅'), backgroundColor: Colors.green),
                                    );
                                  }
                                } catch (e) {
                                  setModalState(() => submitting = false);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.redAccent),
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: submitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black87, strokeWidth: 2))
                            : const Text('GUARDAR REGISTRO', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODAL — Historial de Sesiones
  // ═══════════════════════════════════════════════════════════════════════════

  void _showSessionHistoryDialog(String athleteId, String athleteName) {
    showDialog(
      context: context,
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            backgroundColor: const Color(0xFF0D1B3E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
            ),
            title: Row(
              children: [
                const Icon(Icons.history_rounded, color: Color(0xFF00E5FF), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    athleteName.split(' ').first.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: StreamBuilder<QuerySnapshot>(
                stream: _db
                    .collection('athletes')
                    .doc(athleteId)
                    .collection('historial_entrenamientos')
                    .orderBy('fecha', descending: true)
                    .limit(5)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
                    );
                  }

                  final sessions = snapshot.data?.docs ?? [];
                  if (sessions.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Text(
                        'Sin entrenamientos registrados.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: sessions.length,
                    itemBuilder: (context, idx) {
                      final sData = sessions[idx].data() as Map<String, dynamic>;
                      final titulo = sData['titulo'] ?? 'Práctica';
                      final duracion = sData['duracion'] ?? 90;
                      final intensidad = (sData['intensidad'] ?? 'media').toString().toUpperCase();
                      final observaciones = sData['observaciones'] ?? '';
                      final fechaTs = sData['fecha'] as Timestamp?;
                      final fechaStr = fechaTs != null
                          ? DateFormat('dd MMM yyyy - HH:mm').format(fechaTs.toDate())
                          : 'Hoy';

                      Color colorIntensidad = const Color(0xFFFFB300);
                      if (intensidad == 'BAJA') colorIntensidad = const Color(0xFF00E676);
                      if (intensidad == 'ALTA') colorIntensidad = const Color(0xFFFF1744);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colorIntensidad.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      intensidad,
                                      style: TextStyle(color: colorIntensidad, fontSize: 8, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.timer_outlined, color: Colors.white38, size: 12),
                                  const SizedBox(width: 4),
                                  Text('$duracion min', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                  const SizedBox(width: 12),
                                  const Icon(Icons.calendar_today_outlined, color: Colors.white38, size: 12),
                                  const SizedBox(width: 4),
                                  Text(fechaStr, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                ],
                              ),
                              if (observaciones.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  observaciones,
                                  style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar', style: TextStyle(color: Color(0xFF00E5FF))),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODAL — Cambiar Estado (Status)
  // ═══════════════════════════════════════════════════════════════════════════

  void _showStatusSelectorDialog(String athleteId, String athleteName, String currentStatus) {
    showDialog(
      context: context,
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            backgroundColor: const Color(0xFF0D1B3E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            ),
            title: Text(
              'Estado - ${athleteName.split(' ').first.toUpperCase()}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _statusOption(ctx, athleteId, 'Acceso Autorizado', const Color(0xFF00E676)),
                const SizedBox(height: 8),
                _statusOption(ctx, athleteId, 'Pago Pendiente', const Color(0xFFFFB300)),
                const SizedBox(height: 8),
                _statusOption(ctx, athleteId, 'Lesinado / No Apto', const Color(0xFFFF1744)),
                const SizedBox(height: 8),
                _statusOption(ctx, athleteId, 'Inactivo', const Color(0xFFB0BEC5)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusOption(BuildContext ctx, String athleteId, String targetStatus, Color color) {
    return InkWell(
      onTap: () async {
        Navigator.pop(ctx);
        try {
          await _db.collection('athletes').doc(athleteId).update({
            'status': targetStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Estado de atleta actualizado a $targetStatus ✅'),
                backgroundColor: color,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al cambiar estado: $e'), backgroundColor: Colors.redAccent),
            );
          }
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              targetStatus.toUpperCase(),
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: color.withValues(alpha: 0.6), size: 14),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    Color? borderColor,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: 0.1)),
          ),
          child: child,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF00E5FF)),
      ),
    );
  }
}

class WeeklyChartPainter extends CustomPainter {
  final List<QueryDocumentSnapshot> logs;
  final int totalAthletes;
  WeeklyChartPainter(this.logs, this.totalAthletes);

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = Colors.white.withValues(alpha: 0.05)..style = PaintingStyle.fill;
    final barPaint = Paint()..color = const Color(0xFF00E5FF)..style = PaintingStyle.fill..strokeCap = StrokeCap.round;
    
    final now = DateTime.now();
    final counts = List.filled(7, 0);
    
    for (var l in logs) {
      final t = (l.data() as Map)['timestamp'] as Timestamp?;
      if (t == null) continue;
      if ((l.data() as Map)['action'] != 'ingreso') continue;
      
      final diff = now.difference(t.toDate().toLocal()).inDays;
      if (diff >= 0 && diff < 7) {
        counts[6 - diff]++; 
      }
    }
    
    final double maxVal = totalAthletes > 0 ? totalAthletes.toDouble() : 1.0;
    final double barWidth = (size.width / 7) * 0.4;
    final double spacing = size.width / 7;

    for (int i = 0; i < 7; i++) {
      final double x = (i * spacing) + (spacing / 2) - (barWidth / 2);
      final double h = (counts[i] / maxVal) * size.height;
      final double y = size.height - h;
      
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, barWidth, size.height), const Radius.circular(4)), bgPaint);
      if (h > 0) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, barWidth, h), const Radius.circular(4)), barPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

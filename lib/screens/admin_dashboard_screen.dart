import 'dart:ui';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;
import 'package:file_picker/file_picker.dart';
import '../services/admin_ingestion_controller.dart';
import '../models/ingestion_result.dart';
import 'rbac_management_screen.dart';
import 'crm_medico_screen.dart';
import 'attendance_report_screen.dart';
import 'session_attendance_screen.dart';
import 'tablas_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String institutionId;
  const AdminDashboardScreen({super.key, required this.institutionId});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AdminIngestionController _controller = AdminIngestionController();

  bool _isLoadingBulk = false;
  bool _isCheckingPermissions = true;
  String? _errorMessage;
  int _currentTab = 0; // 0: Vista General (Métricas), 1: Gestión de Deportistas

  // ── Gestión de Deportistas: sub-tabs, filtros y paginado ──
  int _mgmtSubTab = 0;              // 0 = Lista, 1 = Asistencia
  String _filterDiscipline = 'todos'; // 'todos' | 'voleibol' | 'basquetbol' | 'futbol'
  int _athletesPage = 0;
  static const int _athletesPerPage = 10;

  // ── Control de Asistencia ──
  DateTime _attendanceMonth = DateTime.now();

  final Map<String, bool>   _unmaskedDniVisibility = {};
  final Map<String, String> _unmaskedDniData       = {};

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  // Verifica el rol admin leyendo la colección 'users' en Firestore.
  // Ajustado para coincidir con el esquema: users -> role -> 'admin'
  Future<void> _checkPermissions() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No autenticado.');
      
      final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      var doc = await docRef.get();
      
      if (!doc.exists) {
        // Auto-heal missing profile
        final newRole = (user.email == 'asitimbay.rommel@gmail.com' || user.email == 'admin@omnisport.ai') ? 'admin' : 'user';
        await docRef.set({
          'email': user.email ?? 'Sin correo',
          'role': newRole,
          'createdAt': FieldValue.serverTimestamp(),
        });
        doc = await docRef.get();
      }
      
      final role = doc.data()?['role'];
      
      if (role != 'admin') {
        throw Exception('Acceso restringido a administradores.');
      }
      
      if (mounted) setState(() => _isCheckingPermissions = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingPermissions = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _logout() async => FirebaseAuth.instance.signOut();

  void _downloadLogFile(String report, String filename) {
    if (!kIsWeb) {
      debugPrint('[Log de Ingesta no descargado — Entorno Nativo]');
      debugPrint(report);
      return;
    }
    final bytes  = utf8.encode(report);
    final blob   = html.Blob([bytes]);
    final url    = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..style.display = 'none'
      ..download = filename;
    html.document.body?.children.add(anchor);
    anchor.click();
    html.document.body?.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
  }

  // Flujo de dos fases:
  //   1. Dry Run → muestra errores al admin antes de confirmar.
  //   2. Confirmación → Cloud Function persiste los datos válidos.
  // Art. 10 LOPDP: ninguna escritura de datos sensibles desde el cliente.
  Future<void> _handleBulkUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;

    String csvString;
    try {
      csvString = utf8.decode(result.files.single.bytes!);
    } catch (e) {
      // Fallback para CSVs exportados desde Excel que usan ISO-8859-1 (Latin-1) en lugar de UTF-8
      csvString = latin1.decode(result.files.single.bytes!);
    }
    setState(() => _isLoadingBulk = true);

    // FASE 1: Dry Run — validación sin escritura
    final summary = await _controller.runDryRun(csvString, widget.institutionId);
    setState(() => _isLoadingBulk = false);
    if (!mounted) return;

    // El admin revisa el reporte antes de confirmar
    final confirmed = await _showDryRunDialog(summary);
    if (!confirmed) return;

    // FASE 2: Confirmación — Cloud Function escribe en Firestore
    setState(() => _isLoadingBulk = true);
    try {
      final productionSummary =
          await _controller.confirmIngestion(csvString, widget.institutionId);
      setState(() => _isLoadingBulk = false);

      _downloadLogFile(
        productionSummary.toReportString(widget.institutionId),
        'ingestion_${DateTime.now().millisecondsSinceEpoch}.txt',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Ingesta completada: ${productionSummary.valid} persistidos, '
            '${productionSummary.failed} rechazados.',
          ),
        ));
      }
    } catch (e) {
      setState(() => _isLoadingBulk = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error en ingesta: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  // Dialog de revisión del Dry Run. Retorna true solo si el admin confirma
  // y existen registros válidos para persistir.
  Future<bool> _showDryRunDialog(IngestionSummary summary) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: summary.failed > 0 ? Colors.orangeAccent : Colors.greenAccent,
                width: 0.8,
              ),
            ),
            title: Row(children: [
              Icon(
                summary.failed > 0
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
                color: summary.failed > 0 ? Colors.orange : Colors.greenAccent,
              ),
              const SizedBox(width: 12),
              const Text(
                'Simulación DRY RUN',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ]),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _statRow('Total procesados', '${summary.total}', Colors.white70),
                  _statRow('Válidos',          '${summary.valid}', Colors.greenAccent),
                  _statRow('Con errores',      '${summary.failed}', Colors.redAccent),
                  if (summary.errors.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Errores detectados:',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: summary.errors.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• ${summary.errors[i].message}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (summary.failed > 0 && summary.valid > 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Los registros con errores serán omitidos. '
                        'Solo los válidos se persistirán.',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                onPressed: summary.valid > 0
                    ? () => Navigator.pop(ctx, true)
                    : null,
                icon: const Icon(Icons.cloud_upload, size: 16),
                label: Text('Confirmar ${summary.valid} registros'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _statRow(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            Text(value,
                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      );

  // Lee el DNI vía controller (que lee /private con admin SDK).
  // Delega el audit log a Cloud Function — el cliente no escribe en audit_logs.
  // Art. 37 LOPDP: registro inalterable de acceso a datos sensibles.
  // TTL de 30s: el DNI se oculta automáticamente tras la visualización.
  Future<void> _revealDni(String athId) async {
    if (_unmaskedDniVisibility[athId] == true) {
      setState(() => _unmaskedDniVisibility[athId] = false);
      return;
    }
    try {
      final dni = await _controller.fetchDni(athId);
      await _controller.logDniReveal(athId);

      setState(() {
        _unmaskedDniVisibility[athId] = true;
        _unmaskedDniData[athId] = dni;
      });

      Future.delayed(const Duration(seconds: 30), () {
        if (mounted) setState(() => _unmaskedDniVisibility[athId] = false);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al acceder al DNI: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _linkParent(String athId) async {
    final _emailController = TextEditingController();

    final parentEmail = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Row(
          children: [
            Icon(Icons.family_restroom, color: Colors.orange),
            SizedBox(width: 8),
            Text('Vincular Representante', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: TextField(
          controller: _emailController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Correo electrónico del padre',
            labelStyle: TextStyle(color: Colors.white70),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, _emailController.text.trim()),
            child: const Text('Vincular', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (parentEmail == null || parentEmail.isEmpty) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Buscando usuario...'))
      );
    }

    try {
      final snap = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: parentEmail).get();
      if (snap.docs.isEmpty) {
        throw Exception('No se encontró un usuario con ese correo.');
      }
      
      final parentUser = snap.docs.first;
      if (parentUser.data()['role'] != 'parent') {
        throw Exception('El usuario encontrado no tiene el rol PARENT.');
      }

      await FirebaseFirestore.instance.collection('athletes').doc(athId).update({
        'parentUid': parentUser.id,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Representante vinculado correctamente.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  void _showPrivacyNotice() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Colors.orangeAccent, width: 0.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.privacy_tip, color: Colors.orange),
            SizedBox(width: 12),
            Text('Aviso de Privacidad LOPDP',
                style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'En cumplimiento con la Ley Orgánica de Protección de Datos Personales (LOPDP) de Ecuador, '
            'OmniSport-AI informa que los datos de los atletas aquí gestionados están cifrados de extremo a extremo. '
            'El acceso administrativo está auditado y cada visualización de DNI queda registrada en el log forense. '
            '\n\nResponsable: Rommel Asitimbay Morales\nDelegado DPO: Antigravity AI',
            style: TextStyle(color: Colors.white70),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido', style: TextStyle(color: Colors.orange)),
          )
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                _buildTabButton('PANEL DE CONTROL 📊', 0),
                _buildTabButton('GESTIÓN DE DEPORTISTAS 🛡️', 1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, int tabIndex) {
    final isSelected = _currentTab == tabIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _currentTab = tabIndex;
          });
        },
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Color(0xFF00E5FF), Color(0xFF00BFA5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF001220) : Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDisciplineCard({
    required String title,
    required String emoji,
    required int athletes,
    required int teams,
    required int matches,
    required double percentage,
    required List<Color> gradientColors,
  }) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withValues(alpha: 0.04),
            blurRadius: 16,
            spreadRadius: 2,
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 1.0,
                        fontFamily: 'Manrope',
                      ),
                    ),
                    Text(
                      emoji,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Atletas Registrados', style: TextStyle(color: Colors.white38, fontSize: 10)),
                        Text('$athletes', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Equipos en Liga', style: TextStyle(color: Colors.white38, fontSize: 10)),
                        Text('$teams', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Partidos del Fixture', style: TextStyle(color: Colors.white38, fontSize: 10)),
                        Text('$matches', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Representatividad', style: TextStyle(color: Colors.white38, fontSize: 9)),
                        Text('${(percentage * 100).toStringAsFixed(0)}%', style: TextStyle(color: gradientColors[0], fontWeight: FontWeight.bold, fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 6,
                        width: double.infinity,
                        child: LinearProgressIndicator(
                          value: percentage.isNaN ? 0.0 : percentage,
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          valueColor: AlwaysStoppedAnimation<Color>(gradientColors[0]),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDisciplinesSection(
    int totalAthletes,
    int volleyAthletes,
    int volleyTeams,
    int volleyMatches,
    int basketAthletes,
    int basketTeams,
    int basketMatches,
    int futbolAthletes,
    int futbolTeams,
    int futbolMatches,
  ) {
    final double volleyPercentage = totalAthletes == 0 ? 0.0 : volleyAthletes / totalAthletes;
    final double basketPercentage = totalAthletes == 0 ? 0.0 : basketAthletes / totalAthletes;
    final double futbolPercentage = totalAthletes == 0 ? 0.0 : futbolAthletes / totalAthletes;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          return Row(
            children: [
              Expanded(
                child: _buildDisciplineCard(
                  title: 'Voleibol',
                  emoji: '🏐',
                  athletes: volleyAthletes,
                  teams: volleyTeams,
                  matches: volleyMatches,
                  percentage: volleyPercentage,
                  gradientColors: [const Color(0xFF00E5FF), const Color(0xFF00BFA5)],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDisciplineCard(
                  title: 'Básquetbol',
                  emoji: '🏀',
                  athletes: basketAthletes,
                  teams: basketTeams,
                  matches: basketMatches,
                  percentage: basketPercentage,
                  gradientColors: [const Color(0xFFFFAB00), const Color(0xFFFF3D00)],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDisciplineCard(
                  title: 'Fútbol',
                  emoji: '⚽',
                  athletes: futbolAthletes,
                  teams: futbolTeams,
                  matches: futbolMatches,
                  percentage: futbolPercentage,
                  gradientColors: [const Color(0xFFE040FB), const Color(0xFF9C27B0)],
                ),
              ),
            ],
          );
        } else {
          return Column(
            children: [
              _buildDisciplineCard(
                title: 'Voleibol',
                emoji: '🏐',
                athletes: volleyAthletes,
                teams: volleyTeams,
                matches: volleyMatches,
                percentage: volleyPercentage,
                gradientColors: [const Color(0xFF00E5FF), const Color(0xFF00BFA5)],
              ),
              const SizedBox(height: 16),
              _buildDisciplineCard(
                title: 'Básquetbol',
                emoji: '🏀',
                athletes: basketAthletes,
                teams: basketTeams,
                matches: basketMatches,
                percentage: basketPercentage,
                gradientColors: [const Color(0xFFFFAB00), const Color(0xFFFF3D00)],
              ),
              const SizedBox(height: 16),
              _buildDisciplineCard(
                title: 'Fútbol',
                emoji: '⚽',
                athletes: futbolAthletes,
                teams: futbolTeams,
                matches: futbolMatches,
                percentage: futbolPercentage,
                gradientColors: [const Color(0xFFE040FB), const Color(0xFF9C27B0)],
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildAuditLogsSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('audit_logs').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.orange));
        }
        final docs = snapshot.data?.docs ?? [];
        final List<Map<String, dynamic>> logs = docs
            .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
            .toList();

        // Sort descending in memory for 100% index-free safety
        logs.sort((a, b) {
          final dynamic tsA = a['timestamp'];
          final dynamic tsB = b['timestamp'];
          DateTime tA = DateTime(2020);
          DateTime tB = DateTime(2020);
          if (tsA is Timestamp) tA = tsA.toDate();
          if (tsB is Timestamp) tB = tsB.toDate();
          return tB.compareTo(tA);
        });

        final recentLogs = logs.take(4).toList();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.history_toggle_off_rounded, color: Colors.orangeAccent, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'LOG DE AUDITORÍA EN TIEMPO REAL (Art. 37 LOPDP)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Colors.greenAccent, size: 6),
                        SizedBox(width: 6),
                        Text(
                          'ACTIVO',
                          style: TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (recentLogs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No hay logs de seguridad registrados aún.',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: recentLogs.length,
                  separatorBuilder: (context, index) => Divider(color: Colors.white.withValues(alpha: 0.04)),
                  itemBuilder: (context, index) {
                    final log = recentLogs[index];
                    final String rawAction = log['action'] ?? log['tipo'] ?? 'Acción General';
                    final String details = log['details'] ?? log['mensaje'] ?? 'Sin detalles adicionales';
                    final dynamic ts = log['timestamp'];
                    String timeStr = 'Reciente';
                    if (ts is Timestamp) {
                      final dt = ts.toDate();
                      timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} · ${dt.day}/${dt.month}';
                    }

                    // Elegant Spanish LOPDP Compliance Translation Map
                    String friendlyTitle = rawAction.replaceAll('_', ' ').toUpperCase();
                    String friendlyDesc = details;
                    IconData icon = Icons.security_rounded;
                    Color iconColor = Colors.orangeAccent;

                    if (rawAction == 'BULK_INGESTION_COMPLETED') {
                      friendlyTitle = 'Carga Masiva de Deportistas';
                      final int valid = log['valid'] ?? 0;
                      final int failed = log['failed'] ?? 0;
                      friendlyDesc = 'Ingesta cifrada de $valid expedientes (Art. 10 LOPDP). Omitidos: $failed.';
                      icon = Icons.cloud_upload_rounded;
                      iconColor = const Color(0xFF00E5FF);
                    } else if (rawAction == 'BULK_INGESTION_NO_VALID_RECORDS') {
                      friendlyTitle = 'Intento de Ingesta Rechazado';
                      friendlyDesc = 'Carga de CSV detenida. Ningún registro cumple con los estándares LOPDP.';
                      icon = Icons.warning_rounded;
                      iconColor = Colors.redAccent;
                    } else if (rawAction == 'unmask_dni' || rawAction.contains('REVEAL') || rawAction.contains('DNI')) {
                      friendlyTitle = 'Revelación de Identidad Cifrada';
                      final String adminEmail = log['adminEmail'] ?? 'Administrador';
                      friendlyDesc = 'Acceso a DNI desencriptado por $adminEmail (Auditoría Forense Art. 37 LOPDP).';
                      icon = Icons.remove_red_eye_rounded;
                      iconColor = const Color(0xFFFFAB00);
                    } else if (rawAction == 'SMART_ID_GENERATED') {
                      friendlyTitle = 'Firma Digital QR Generada';
                      friendlyDesc = 'Token QR dinámico asignado para acceso seguro y control de asistencia (Art. 10 LOPDP).';
                      icon = Icons.qr_code_rounded;
                      iconColor = const Color(0xFF00E676);
                    } else if (rawAction == 'SMART_ID_VERIFIED') {
                      friendlyTitle = 'Acceso Escolar Verificado';
                      friendlyDesc = 'Validación criptográfica exitosa del QR de identidad en punto físico.';
                      icon = Icons.fact_check_rounded;
                      iconColor = const Color(0xFF00E676);
                    } else if (rawAction.contains('ERASURE_INITIATED')) {
                      friendlyTitle = 'Derecho al Olvido Iniciado';
                      friendlyDesc = 'Petición formal de revocación de consentimiento y eliminación recibida (Art. 16 LOPDP).';
                      icon = Icons.delete_sweep_rounded;
                      iconColor = Colors.amberAccent;
                    } else if (rawAction.contains('ERASURE_COMPLETED')) {
                      friendlyTitle = 'Derecho al Olvido Consumado';
                      friendlyDesc = 'Eliminación irreversible de expediente físico y credenciales Auth (Derecho al Olvido).';
                      icon = Icons.check_circle_rounded;
                      iconColor = Colors.redAccent;
                    } else if (rawAction == 'EMERGENCY_BROADCAST_SENT') {
                      friendlyTitle = 'Alerta Médica Distribuida (S.O.S)';
                      friendlyDesc = 'Notificación inmediata enviada a tutores y personal médico por lesión deportiva.';
                      icon = Icons.notification_important_rounded;
                      iconColor = Colors.redAccent;
                    } else if (rawAction == 'INJURY_REGISTERED') {
                      friendlyTitle = 'Expediente Médico Actualizado';
                      friendlyDesc = 'Anotación confidencial de incidente de salud en CRM Médico (Art. 26 LOPDP).';
                      icon = Icons.medical_services_rounded;
                      iconColor = Colors.amber;
                    } else if (rawAction == 'MEDICAL_DISCHARGE_ISSUED') {
                      friendlyTitle = 'Alta Médica Concedida';
                      friendlyDesc = 'Registro formal de aptitud física habilitada tras recuperación en CRM Médico.';
                      icon = Icons.assignment_turned_in_rounded;
                      iconColor = const Color(0xFF00E676);
                    } else if (rawAction == 'ROLE_SCALED' || rawAction.contains('ROLE')) {
                      friendlyTitle = 'Privilegios de Acceso Modificados';
                      friendlyDesc = 'Actualización de perfil de seguridad y permisos de cuenta (RBAC Control).';
                      icon = Icons.admin_panel_settings_rounded;
                      iconColor = Colors.purpleAccent;
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: iconColor, size: 14),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  friendlyTitle,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.2),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  friendlyDesc,
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeStr,
                            style: const TextStyle(color: Colors.white30, fontSize: 10),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF00E5FF), size: 20),
            const SizedBox(height: 12),
            Text(label,
                style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermissions) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(child: CircularProgressIndicator(color: Colors.orange)),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 80, color: Colors.redAccent),
              const SizedBox(height: 24),
              const Text('Acceso Denegado',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text('Detalle: $_errorMessage',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54)),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _logout,
                style:
                    ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                child: const Text('Cerrar Sesión',
                    style: TextStyle(color: Colors.white)),
              )
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      extendBodyBehindAppBar: true,
      drawer: Drawer(
        backgroundColor: const Color(0xFF1A1A1A),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF0A0A0A)),
              child: Text('OmniSport-AI Admin', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings, color: Colors.orange),
              title: const Text('RBAC & Roles', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const RbacManagementScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.emoji_events_rounded, color: Color(0xFF00E5FF)),
              title: const Text('The League Hub (Torneos)', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Clasificación · Calendario · Sembrado de Liga',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const TablasScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.medical_services_rounded, color: Color(0xFF00E676)),
              title: const Text('CRM Médico', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Lesiones · Alta médica · Expedientes',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CrmMedicoScreen(institutionId: widget.institutionId),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_rounded, color: Color(0xFF00E5FF)),
              title: const Text('Reporte de Asistencia',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Control · Estadísticas · Exportar CSV',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AttendanceReportScreen(
                        institutionId: widget.institutionId),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_rounded, color: Colors.amber),
              title: const Text('Panel de Sesión',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Presentes · Ausentes · Marcado manual',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SessionAttendanceScreen(
                      institutionId: widget.institutionId,
                      coachName:     'Admin',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),

      floatingActionButton: null,
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('OMNISPORT-AI BACKOFFICE',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5)),
        backgroundColor: Colors.black.withValues(alpha: 0.5),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high, color: Colors.amberAccent),
            tooltip: 'Seed Firestore',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await FirebaseFirestore.instance.collection('app_config').doc('notification_templates').set({
                 'Ingreso Atleta': 'El atleta {name} ha registrado su entrada.',
                 'Salida Segura': 'El atleta {name} ha registrado su salida.',
                 'Aviso de Emergencia': 'ALERTA: Se ha reportado una situación médica urgente.'
              });
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(content: Text('Plantillas de notificación actualizadas.')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: _logout,
          )
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF001220), Color(0xFF001F3F), Color(0xFF002D5A)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('BACKOFFICE CENTRAL',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1)),
                  const Text('OMNISPORT-AI • AUDITORÍA DE SEGURIDAD',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2)),
                  
                  _buildTabBar(),

                  // Stream del listado general de atletas para calcular KPIs reactivos
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('athletes')
                        .where('ownerInstitutionId', isEqualTo: widget.institutionId)
                        .snapshots(),
                    builder: (context, athletesSnapshot) {
                      if (athletesSnapshot.hasError) {
                        return const Expanded(
                          child: Center(
                            child: Text('Error al cargar datos de atletas',
                                style: TextStyle(color: Colors.white)),
                          ),
                        );
                      }
                      if (athletesSnapshot.connectionState == ConnectionState.waiting) {
                        return const Expanded(
                          child: Center(
                            child: CircularProgressIndicator(color: Colors.orange),
                          ),
                        );
                      }

                      final athletesDocs = athletesSnapshot.data?.docs ?? [];

                      // Si está en el Tab 0: Panel de Control (Estadísticas Multi-Disciplina)
                      if (_currentTab == 0) {
                        // Consultar tablas y encuentros en cascada reactiva
                        return StreamBuilder<QuerySnapshot>(
                          stream: _firestore.collection('tournaments').snapshots(),
                          builder: (context, tournamentsSnapshot) {
                            return StreamBuilder<QuerySnapshot>(
                              stream: _firestore.collection('tournament_matches').snapshots(),
                              builder: (context, matchesSnapshot) {
                                final teamsDocs = tournamentsSnapshot.data?.docs ?? [];
                                final matchesDocs = matchesSnapshot.data?.docs ?? [];

                                // Voleibol stats
                                final volleyAthletes = athletesDocs.where((d) {
                                  final data = d.data() as Map<String, dynamic>;
                                  final disc = (data['disciplina'] ?? data['teamOrCategory'] ?? data['sport'] ?? '').toString().toLowerCase();
                                  return disc.contains('volei') || disc.contains('volley') || disc == 'voleibol';
                                }).length;
                                final volleyTeams = teamsDocs.where((d) {
                                  final data = d.data() as Map<String, dynamic>;
                                  return (data['disciplina'] ?? '').toString().toLowerCase() == 'voleibol';
                                }).length;
                                final volleyMatches = matchesDocs.where((d) {
                                  final data = d.data() as Map<String, dynamic>;
                                  return (data['disciplina'] ?? '').toString().toLowerCase() == 'voleibol';
                                }).length;

                                // Básquetbol stats
                                final basketAthletes = athletesDocs.where((d) {
                                  final data = d.data() as Map<String, dynamic>;
                                  final disc = (data['disciplina'] ?? data['teamOrCategory'] ?? data['sport'] ?? '').toString().toLowerCase();
                                  return disc.contains('basket') || disc.contains('basquet') || disc == 'basquetbol';
                                }).length;
                                final basketTeams = teamsDocs.where((d) {
                                  final data = d.data() as Map<String, dynamic>;
                                  return (data['disciplina'] ?? '').toString().toLowerCase() == 'basquetbol';
                                }).length;
                                final basketMatches = matchesDocs.where((d) {
                                  final data = d.data() as Map<String, dynamic>;
                                  return (data['disciplina'] ?? '').toString().toLowerCase() == 'basquetbol';
                                }).length;

                                // Fútbol stats
                                final futbolAthletes = athletesDocs.where((d) {
                                  final data = d.data() as Map<String, dynamic>;
                                  final disc = (data['disciplina'] ?? data['teamOrCategory'] ?? data['sport'] ?? '').toString().toLowerCase();
                                  return disc.contains('futbol') || disc.contains('fútbol') || disc.contains('soccer') || disc == 'futbol';
                                }).length;
                                final futbolTeams = teamsDocs.where((d) {
                                  final data = d.data() as Map<String, dynamic>;
                                  return (data['disciplina'] ?? '').toString().toLowerCase() == 'futbol';
                                }).length;
                                final futbolMatches = matchesDocs.where((d) {
                                  final data = d.data() as Map<String, dynamic>;
                                  return (data['disciplina'] ?? '').toString().toLowerCase() == 'futbol';
                                }).length;

                                return Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            _buildMiniStat('Atletas en la Institución', '${athletesDocs.length}', Icons.people_outline),
                                            const SizedBox(width: 12),
                                            _buildMiniStat('Auditoría Forense LOPDP', 'Activo 🛡️', Icons.verified_user_outlined),
                                          ],
                                        ),
                                        const SizedBox(height: 24),
                                        const Text(
                                          'RENDIMIENTO POR DISCIPLINA DEPORTIVA',
                                          style: TextStyle(
                                            color: Colors.white38,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        _buildDisciplinesSection(
                                          athletesDocs.length,
                                          volleyAthletes,
                                          volleyTeams,
                                          volleyMatches,
                                          basketAthletes,
                                          basketTeams,
                                          basketMatches,
                                          futbolAthletes,
                                          futbolTeams,
                                          futbolMatches,
                                        ),
                                        const SizedBox(height: 24),
                                        const Text(
                                          'CENTRO DE INTELIGENCIA DEPORTIVA',
                                          style: TextStyle(
                                            color: Colors.white38,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        _buildChartsSection(
                                          athletesDocs.length,
                                          volleyAthletes,
                                          volleyTeams,
                                          volleyMatches,
                                          basketAthletes,
                                          basketTeams,
                                          basketMatches,
                                          futbolAthletes,
                                          futbolTeams,
                                          futbolMatches,
                                        ),
                                        const SizedBox(height: 24),
                                        _buildAuditLogsSection(),
                                        const SizedBox(height: 20),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      }

                      // Si está en el Tab 1: Gestión de Deportistas
                      return Expanded(
                        child: _buildMgmtTabContent(athletesDocs),
                      );
                    },
                  ),

                  const SizedBox(height: 16),
                  Center(
                    child: Opacity(
                      opacity: 0.6,
                      child: TextButton.icon(
                        onPressed: _showPrivacyNotice,
                        icon: const Icon(Icons.shield_outlined,
                            color: Colors.white, size: 14),
                        label: const Text(
                          'CUMPLIMIENTO LOPDP • PRIVACIDAD',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────
  //  GESTIÓN DE DEPORTISTAS — Shell con sub-tabs
  // ──────────────────────────────────────────────────────

  Widget _buildMgmtTabContent(List<QueryDocumentSnapshot> allAthletes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Sub-tab bar ──
        _buildMgmtSubTabBar(),
        const SizedBox(height: 12),
        // ── Sub-tab content ──
        Expanded(
          child: _mgmtSubTab == 0
              ? _buildAthleteListTab(allAthletes)
              : _buildAttendanceTab(allAthletes),
        ),
      ],
    );
  }

  Widget _buildMgmtSubTabBar() {
    const tabs = [
      ('📋 Lista de Deportistas', 0),
      ('📅 Control de Asistencia', 1),
    ];
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: tabs.map((t) {
          final selected = _mgmtSubTab == t.$2;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() { _mgmtSubTab = t.$2; _athletesPage = 0; }),
              child: Container(
                margin: const EdgeInsets.all(4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(
                          colors: [Color(0xFF00BFA5), Color(0xFF00E5FF)],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  t.$1,
                  style: TextStyle(
                    color: selected ? const Color(0xFF001220) : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ──────────────────────────────────────────────────────
  //  SUB-TAB 0: Lista de Deportistas (filtros + paginado)
  // ──────────────────────────────────────────────────────

  Widget _buildAthleteListTab(List<QueryDocumentSnapshot> allAthletes) {
    // ── Acción buttons (top-right) ──
    final actionRow = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left: label + hint
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'REGISTROS Y CUMPLIMIENTO LOPDP',
              style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.5),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white24, size: 11),
                const SizedBox(width: 4),
                Text(
                  'Para añadir un atleta individual usa RBAC → Escalación',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 9),
                ),
              ],
            ),
          ],
        ),
        // Right: solo Ingesta CSV
        ElevatedButton.icon(
          onPressed: _handleBulkUpload,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: _isLoadingBulk
              ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5))
              : const Icon(Icons.cloud_upload, size: 15),
          label: Text(
            _isLoadingBulk ? 'Subiendo...' : '⬆  Ingesta CSV',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );

    // ── Discipline filter chips ──
    final filterRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _discChip('Todos', 'todos', Icons.sports),
          const SizedBox(width: 8),
          _discChip('🏐 Voleibol', 'voleibol', null),
          const SizedBox(width: 8),
          _discChip('🏀 Básquetbol', 'basquetbol', null),
          const SizedBox(width: 8),
          _discChip('⚽ Fútbol', 'futbol', null),
        ],
      ),
    );

    // ── Filter athletes ──
    List<QueryDocumentSnapshot> filtered = allAthletes.where((doc) {
      if (_filterDiscipline == 'todos') return true;
      final data = doc.data() as Map<String, dynamic>;
      final disc = (data['disciplina'] ?? data['teamOrCategory'] ?? data['sport'] ?? '')
          .toString().toLowerCase();
      return disc.contains(_filterDiscipline) || disc == _filterDiscipline;
    }).toList();

    // ── Pagination ──
    final totalPages = (filtered.length / _athletesPerPage).ceil().clamp(1, 9999);
    final start = _athletesPage * _athletesPerPage;
    final end = (start + _athletesPerPage).clamp(0, filtered.length);
    final pageAthletes = filtered.sublist(start, end);

    // ── Build rows grouped by discipline ──
    String? lastDisc;
    final rows = <DataRow>[];
    for (final doc in pageAthletes) {
      final data = doc.data() as Map<String, dynamic>;
      final disc = (data['disciplina'] ?? data['teamOrCategory'] ?? data['sport'] ?? 'Sin disciplina')
          .toString().toLowerCase();

      // Section header row (only when all disciplines shown)
      if (_filterDiscipline == 'todos' && disc != lastDisc) {
        lastDisc = disc;
        final (emoji, color) = _discStyle(disc);
        rows.add(DataRow(
          color: WidgetStateProperty.all(color.withValues(alpha: 0.08)),
          cells: [
            DataCell(Row(children: [
              Text('$emoji ', style: const TextStyle(fontSize: 14)),
              Text(
                disc.toUpperCase(),
                style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1),
              ),
              const SizedBox(width: 8),
              Text(
                '(${filtered.where((d) { final dd = (d.data() as Map<String, dynamic>)['disciplina'] ?? ''; return dd.toString().toLowerCase() == disc; }).length} deportistas)',
                style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 9),
              ),
            ])),
            const DataCell(SizedBox()),
            const DataCell(SizedBox()),
            const DataCell(SizedBox()),
            const DataCell(SizedBox()),
          ],
        ));
      }

      // Athlete row
      final athId = doc.id;
      final fullName = data['full_name'] ?? data['fullName'] ?? 'Desconocido';
      final teamCat = data['teamOrCategory'] ?? data['sport'] ?? 'N/A';
      final isVisible = _unmaskedDniVisibility[athId] ?? false;

      // Show ⚠ badge when athlete was created without going through the
      // Cloud Function that writes to /private/sensitive_data
      final dniLikelyMissing = (data['hasSensitiveData'] == false) ||
          (!isVisible && data.containsKey('hasSensitiveData') && data['hasSensitiveData'] != true);

      rows.add(DataRow(cells: [
        DataCell(Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fullName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            Row(
              children: [
                Text(
                  teamCat.toString().toUpperCase(),
                  style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.w600),
                ),
                if (dniLikelyMissing) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: const Text('⚠ Sin DNI', style: TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ],
        )),
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isVisible ? Colors.white.withValues(alpha: 0.15) : Colors.black12,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            isVisible ? (_unmaskedDniData[athId] ?? 'N/A') : '••••••••••',
            style: TextStyle(
              color: isVisible ? Colors.white : Colors.white24,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        )),
        DataCell(IconButton(
          icon: Icon(
            isVisible ? Icons.remove_red_eye : Icons.remove_red_eye_outlined,
            color: isVisible ? Colors.white : Colors.white38,
            size: 18,
          ),
          onPressed: () => _revealDni(athId),
        )),
        DataCell(Row(children: [
          if (data['parentUid'] != null)
            const Icon(Icons.check_circle, color: Colors.green, size: 16)
          else
            const Icon(Icons.warning, color: Colors.amber, size: 16),
          IconButton(
            icon: const Icon(Icons.family_restroom, color: Colors.orange, size: 18),
            tooltip: 'Vincular Representante',
            onPressed: () => _linkParent(athId),
          ),
        ])),
        // Discipline badge
        DataCell(
          Builder(builder: (ctx) {
            final (emoji, color) = _discStyle(disc);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(
                '$emoji ${disc[0].toUpperCase()}${disc.substring(1)}',
                style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            );
          }),
        ),
      ]));
    }

    // ── Pagination controls ──
    final paginator = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white54),
          onPressed: _athletesPage > 0 ? () => setState(() => _athletesPage--) : null,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Página ${_athletesPage + 1} de $totalPages  ·  ${filtered.length} deportistas',
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: Colors.white54),
          onPressed: _athletesPage < totalPages - 1 ? () => setState(() => _athletesPage++) : null,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        actionRow,
        const SizedBox(height: 12),
        filterRow,
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.06)),
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 64,
                      columns: const [
                        DataColumn(label: Text('DEPORTISTA', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 11))),
                        DataColumn(label: Text('DNI PROTEGIDO', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 11))),
                        DataColumn(label: Text('AUDITORÍA', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 11))),
                        DataColumn(label: Text('FAMILIA', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 11))),
                        DataColumn(label: Text('DISCIPLINA', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 11))),
                      ],
                      rows: rows,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        paginator,
      ],
    );
  }

  (String, Color) _discStyle(String disc) {
    if (disc.contains('volei')) return ('🏐', const Color(0xFF00E5FF));
    if (disc.contains('basket') || disc.contains('basquet')) return ('🏀', const Color(0xFFFFAB00));
    if (disc.contains('futbol') || disc.contains('fútbol') || disc.contains('soccer')) return ('⚽', const Color(0xFFE040FB));
    return ('🏅', Colors.white54);
  }

  Widget _discChip(String label, String value, IconData? icon) {
    final selected = _filterDiscipline == value;
    return GestureDetector(
      onTap: () => setState(() { _filterDiscipline = value; _athletesPage = 0; }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [Color(0xFF00BFA5), Color(0xFF00E5FF)])
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.transparent : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF001220) : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────
  //  SUB-TAB 1: Control de Asistencia Digital
  // ──────────────────────────────────────────────────────

  Widget _buildAttendanceTab(List<QueryDocumentSnapshot> allAthletes) {
    // Filter athletes by discipline
    final athletes = _filterDiscipline == 'todos'
        ? allAthletes
        : allAthletes.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final disc = (data['disciplina'] ?? data['teamOrCategory'] ?? data['sport'] ?? '').toString().toLowerCase();
            return disc.contains(_filterDiscipline) || disc == _filterDiscipline;
          }).toList();

    final year = _attendanceMonth.year;
    final month = _attendanceMonth.month;
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final monthName = _monthName(month);

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('attendance_logs')
          .where('institutionId', isEqualTo: widget.institutionId)
          .snapshots(),
      builder: (ctx, snap) {
        // Build a lookup: athleteId -> Set<day> for "present" marks
        // And absenceLookup: "$athleteId-$day" -> absenceCode
        final Map<String, Set<int>> presentDays = {};
        final Map<String, String> absenceCodes = {};

        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            final ts = d['timestamp'];
            final dateStr = d['date'] as String?;
            DateTime? dt;
            if (ts is Timestamp) dt = ts.toDate();
            if (dateStr != null) dt = DateTime.tryParse(dateStr);
            if (dt == null) continue;
            if (dt.year != year || dt.month != month) continue;

            final athleteId = d['athleteId'] as String? ?? '';
            final code = d['absenceCode'] as String?;
            final day = dt.day;

            presentDays.putIfAbsent(athleteId, () => {});
            if (code == null || code.isEmpty) {
              // Present mark
              presentDays[athleteId]!.add(day);
            } else {
              absenceCodes['$athleteId-$day'] = code;
            }
          }
        }

        return Column(
          children: [
            // ── Month navigator + discipline filter ──
            Row(
              children: [
                // Discipline filter
                _discChip('Todos', 'todos', null),
                const SizedBox(width: 6),
                _discChip('🏐', 'voleibol', null),
                const SizedBox(width: 6),
                _discChip('🏀', 'basquetbol', null),
                const SizedBox(width: 6),
                _discChip('⚽', 'futbol', null),
                const Spacer(),
                // Month nav
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white70),
                  onPressed: () => setState(() {
                    _attendanceMonth = DateTime(year, month - 1);
                  }),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$monthName $year',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.white70),
                  onPressed: () => setState(() {
                    _attendanceMonth = DateTime(year, month + 1);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── Legend ──
            Wrap(
              spacing: 12,
              children: [
                _attendanceLegendItem('✅', 'Asistió', Colors.greenAccent),
                _attendanceLegendItem('NE', 'Necesidad/Malestar', Colors.orange),
                _attendanceLegendItem('NR', 'Sin Razón', Colors.redAccent),
                _attendanceLegendItem('NC', 'Conducta', Colors.purpleAccent),
                _attendanceLegendItem('NU', 'Ropa Inadecuada', Colors.amber),
                _attendanceLegendItem('—', 'Sin marcar', Colors.white24),
              ],
            ),
            const SizedBox(height: 10),
            // ── Grid ──
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                ),
                child: athletes.isEmpty
                    ? const Center(
                        child: Text('No hay deportistas en esta disciplina.',
                            style: TextStyle(color: Colors.white38, fontSize: 13)),
                      )
                    : SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.05)),
                            dataRowMinHeight: 44,
                            dataRowMaxHeight: 44,
                            columnSpacing: 4,
                            columns: [
                              const DataColumn(label: SizedBox(width: 130, child: Text('DEPORTISTA', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)))),
                              ...List.generate(daysInMonth, (i) {
                                final day = i + 1;
                                final wd = DateTime(year, month, day).weekday;
                                final isWeekend = wd == 6 || wd == 7;
                                return DataColumn(
                                  label: SizedBox(
                                    width: 28,
                                    child: Text(
                                      '$day',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: isWeekend ? Colors.white24 : Colors.white54,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                            rows: athletes.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final athId = doc.id;
                              final name = (data['full_name'] ?? data['fullName'] ?? 'Desconocido').toString();
                              final shortName = name.length > 16 ? '${name.substring(0, 14)}…' : name;

                              return DataRow(cells: [
                                DataCell(SizedBox(
                                  width: 130,
                                  child: Text(shortName,
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis),
                                )),
                                ...List.generate(daysInMonth, (i) {
                                  final day = i + 1;
                                  final key = '$athId-$day';
                                  final isPresent = presentDays[athId]?.contains(day) ?? false;
                                  final code = absenceCodes[key];
                                  final wd = DateTime(year, month, day).weekday;
                                  final isWeekend = wd == 6 || wd == 7;

                                  return DataCell(
                                    GestureDetector(
                                      onTap: isWeekend ? null : () => _showAttendancePicker(athId, year, month, day),
                                      child: Center(
                                        child: _attendanceCell(isPresent, code, isWeekend),
                                      ),
                                    ),
                                  );
                                }),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _attendanceCell(bool isPresent, String? code, bool isWeekend) {
    if (isWeekend) {
      return Container(
        width: 24, height: 24,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }
    if (code != null) {
      final (bg, fg) = _codeStyle(code);
      return Container(
        width: 26, height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
        child: Text(code, style: TextStyle(color: fg, fontSize: 8, fontWeight: FontWeight.w900)),
      );
    }
    if (isPresent) {
      return Container(
        width: 26, height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.greenAccent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
        ),
        child: const Text('✓', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w900)),
      );
    }
    return Container(
      width: 26, height: 26,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
    );
  }

  (Color, Color) _codeStyle(String code) {
    switch (code) {
      case 'NE': return (Colors.orange.withValues(alpha: 0.25), Colors.orange);
      case 'NR': return (Colors.redAccent.withValues(alpha: 0.25), Colors.redAccent);
      case 'NC': return (Colors.purpleAccent.withValues(alpha: 0.25), Colors.purpleAccent);
      case 'NU': return (Colors.amber.withValues(alpha: 0.25), Colors.amber);
      default:   return (Colors.white.withValues(alpha: 0.08), Colors.white38);
    }
  }

  Widget _attendanceLegendItem(String label, String desc, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 4),
        Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 9)),
      ],
    );
  }

  String _monthName(int month) {
    const names = [
      '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];
    return names[month];
  }

  Future<void> _showAttendancePicker(String athleteId, int year, int month, int day) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    const options = [
      ('✅ Asistió', null),
      ('NE — No entrenó (necesidad/malestar)', 'NE'),
      ('NR — No entrenó sin razón / no avisó', 'NR'),
      ('NC — No permitido por conducta', 'NC'),
      ('NU — No permitido por ropa inadecuada', 'NU'),
    ];

    final selected = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 0.5),
        ),
        title: Text(
          'Asistencia · Día $day/$month/$year',
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((opt) {
            final (label, code) = opt;
            final (bg, fg) = code != null ? _codeStyle(code) : (Colors.greenAccent.withValues(alpha: 0.15), Colors.greenAccent);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.pop(ctx, code ?? '__PRESENT__'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                  child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );

    if (selected == null) return;

    // Build ISO date string for Firestore
    final dateStr = '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    final String? absenceCode = selected == '__PRESENT__' ? null : selected;

    try {
      await _firestore.collection('attendance_logs').add({
        'athleteId': athleteId,
        'scannedByUid': adminUid,
        'eventType': 'MANUAL_MARK',
        'absenceCode': absenceCode,
        'date': dateStr,
        'institutionId': widget.institutionId,
        'timestamp': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(absenceCode == null
              ? '✅ Asistencia registrada para el día $day'
              : 'Código $absenceCode registrado para el día $day'),
          backgroundColor: absenceCode == null ? Colors.green : Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al registrar: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  Widget _buildChartsSection(

    int totalAthletes,
    int volleyAthletes,
    int volleyTeams,
    int volleyMatches,
    int basketAthletes,
    int basketTeams,
    int basketMatches,
    int futbolAthletes,
    int futbolTeams,
    int futbolMatches,
  ) {
    final double volleyPercentage = totalAthletes == 0 ? 0.0 : volleyAthletes / totalAthletes;
    final double basketPercentage = totalAthletes == 0 ? 0.0 : basketAthletes / totalAthletes;
    final double futbolPercentage = totalAthletes == 0 ? 0.0 : futbolAthletes / totalAthletes;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        final content = [
          // Donut Chart Card
          Expanded(
            flex: isWide ? 4 : 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  const Text(
                    'DISTRIBUCIÓN DE ATLETAS',
                    style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: DonutChart(
                      volleyPercent: volleyPercentage,
                      basketPercent: basketPercentage,
                      futbolPercent: futbolPercentage,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Legend
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildLegendItem('Voleibol', const Color(0xFF00E5FF)),
                      _buildLegendItem('Básquetbol', const Color(0xFFFFAB00)),
                      _buildLegendItem('Fútbol', const Color(0xFFE040FB)),
                    ],
                  )
                ],
              ),
            ),
          ),
          if (isWide) const SizedBox(width: 16) else const SizedBox(height: 16),
          // Bar Chart Card
          Expanded(
            flex: isWide ? 6 : 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  const Text(
                    'COMPETENCIA ACTIVA POR DISCIPLINA',
                    style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 20),
                  SportsBarChart(
                    volleyTeams: volleyTeams,
                    volleyMatches: volleyMatches,
                    basketTeams: basketTeams,
                    basketMatches: basketMatches,
                    futbolTeams: futbolTeams,
                    futbolMatches: futbolMatches,
                  ),
                  const SizedBox(height: 20),
                  // Legend
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 6),
                      const Text('Equipos en Liga', style: TextStyle(color: Colors.white54, fontSize: 10)),
                      const SizedBox(width: 20),
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 6),
                      const Text('Partidos del Fixture', style: TextStyle(color: Colors.white54, fontSize: 10)),
                    ],
                  )
                ],
              ),
            ),
          ),
        ];

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: content,
          );
        } else {
          return Column(
            children: content.map((w) {
              if (w is Expanded) return w.child;
              return w;
            }).toList(),
          );
        }
      },
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }
}

// ─── STUNNING DONUT CHART WIDGET ─────────────────────────────────────────────

class DonutChart extends StatelessWidget {
  final double volleyPercent;
  final double basketPercent;
  final double futbolPercent;

  const DonutChart({
    super.key,
    required this.volleyPercent,
    required this.basketPercent,
    required this.futbolPercent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      width: 140,
      child: CustomPaint(
        painter: _DonutChartPainter(
          volley: volleyPercent,
          basket: basketPercent,
          futbol: futbolPercent,
        ),
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final double volley;
  final double basket;
  final double futbol;

  _DonutChartPainter({
    required this.volley,
    required this.basket,
    required this.futbol,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double total = volley + basket + futbol;
    
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    final strokeWidth = 14.0;

    // Background track
    final paintTrack = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, paintTrack);

    if (total == 0) return;

    final paintVolley = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0xFF00E5FF), Color(0xFF00BFA5)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    final paintBasket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFAB00), Color(0xFFFF3D00)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    final paintFutbol = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0xFFE040FB), Color(0xFF9C27B0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    double startAngle = -3.14159 / 2; // Start from top

    // Draw Volley segment
    final sweepVolley = (volley / total) * 2 * 3.14159;
    if (sweepVolley > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepVolley - (sweepVolley == 2 * 3.14159 ? 0.0 : 0.08), // small gap unless it's 100%
        false,
        paintVolley,
      );
      startAngle += sweepVolley;
    }

    // Draw Basket segment
    final sweepBasket = (basket / total) * 2 * 3.14159;
    if (sweepBasket > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepBasket - (sweepBasket == 2 * 3.14159 ? 0.0 : 0.08),
        false,
        paintBasket,
      );
      startAngle += sweepBasket;
    }

    // Draw Futbol segment
    final sweepFutbol = (futbol / total) * 2 * 3.14159;
    if (sweepFutbol > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepFutbol - (sweepFutbol == 2 * 3.14159 ? 0.0 : 0.08),
        false,
        paintFutbol,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ─── STUNNING BAR CHART WIDGET ───────────────────────────────────────────────

class SportsBarChart extends StatelessWidget {
  final int volleyTeams;
  final int volleyMatches;
  final int basketTeams;
  final int basketMatches;
  final int futbolTeams;
  final int futbolMatches;

  const SportsBarChart({
    super.key,
    required this.volleyTeams,
    required this.volleyMatches,
    required this.basketTeams,
    required this.basketMatches,
    required this.futbolTeams,
    required this.futbolMatches,
  });

  @override
  Widget build(BuildContext context) {
    // Find max value to scale the bars
    final int maxVal = [
      volleyTeams, volleyMatches,
      basketTeams, basketMatches,
      futbolTeams, futbolMatches,
      4 // baseline minimum
    ].reduce((curr, next) => curr > next ? curr : next);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 140,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildSportsGroup('VOLEIBOL', volleyTeams, volleyMatches, maxVal, const Color(0xFF00E5FF), const Color(0xFF00E5FF).withValues(alpha: 0.4)),
          _buildSportsGroup('BÁSQUET', basketTeams, basketMatches, maxVal, const Color(0xFFFFAB00), const Color(0xFFFFAB00).withValues(alpha: 0.4)),
          _buildSportsGroup('FÚTBOL', futbolTeams, futbolMatches, maxVal, const Color(0xFFE040FB), const Color(0xFFE040FB).withValues(alpha: 0.4)),
        ],
      ),
    );
  }

  Widget _buildSportsGroup(String label, int teams, int matches, int maxVal, Color c1, Color c2) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildBar(teams, maxVal, c1),
            const SizedBox(width: 8),
            _buildBar(matches, maxVal, c2),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ],
    );
  }

  Widget _buildBar(int value, int maxVal, Color color) {
    final double pct = maxVal == 0 ? 0.0 : value / maxVal;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '$value',
          style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Container(
          height: 85 * pct,
          width: 14,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.3)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.15),
                blurRadius: 4,
                spreadRadius: 1,
              )
            ],
          ),
        ),
      ],
    );
  }
}

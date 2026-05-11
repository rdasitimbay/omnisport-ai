import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;
import 'package:file_picker/file_picker.dart';
import '../services/admin_ingestion_controller.dart';
import '../models/ingestion_result.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String institutionId;
  const AdminDashboardScreen({Key? key, required this.institutionId})
      : super(key: key);

  @override
  _AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AdminIngestionController _controller = AdminIngestionController();

  bool _isLoadingBulk = false;
  bool _isCheckingPermissions = true;
  String? _errorMessage;

  Map<String, bool>   _unmaskedDniVisibility = {};
  Map<String, String> _unmaskedDniData       = {};

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  // Verifica el rol admin leyendo Custom Claims del JWT — sin lectura a Firestore.
  // Art. 10 LOPDP: control de acceso basado en token firmado por Firebase Auth.
  Future<void> _checkPermissions() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No autenticado.');
      final tokenResult = await user.getIdTokenResult();
      if (tokenResult.claims?['role'] != 'admin') {
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
    final bytes  = utf8.encode(report);
    final blob   = html.Blob([bytes]);
    final url    = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..style.display = 'none'
      ..download = filename;
    html.document.body!.children.add(anchor);
    anchor.click();
    html.document.body!.children.remove(anchor);
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

    final csvString = utf8.decode(result.files.single.bytes!);
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.orange,
        onPressed: _handleBulkUpload,
        icon: _isLoadingBulk
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.cloud_upload),
        label: Text(_isLoadingBulk ? 'Procesando...' : 'Nueva Ingesta Masiva'),
      ),
      appBar: AppBar(
        title: const Text('OMNISPORT-AI BACKOFFICE',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5)),
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        actions: [
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
                  colors: [Color(0xFF001F3F), Color(0xFF00E5FF)],
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
                  const SizedBox(height: 32),

                  // Stream filtrado por institutionId del admin autenticado.
                  // Art. 5 LOPDP: minimización — el admin solo ve su institución.
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('athletes')
                        .where('ownerInstitutionId',
                            isEqualTo: widget.institutionId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Expanded(
                          child: Center(
                            child: Text('Error al cargar datos',
                                style: TextStyle(color: Colors.white)),
                          ),
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Expanded(
                          child: Center(
                            child: CircularProgressIndicator(
                                color: Colors.orange),
                          ),
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];

                      return Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _buildMiniStat('Atletas Registrados',
                                    '${docs.length}', Icons.people_outline),
                                const SizedBox(width: 12),
                                _buildMiniStat('Acceso Forense', 'Activo',
                                    Icons.verified_user_outlined),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(32),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.2)),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 40,
                                        spreadRadius: -10),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(32),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                        sigmaX: 20, sigmaY: 20),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.vertical,
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: DataTable(
                                          headingRowColor:
                                              MaterialStateProperty.all(
                                                  Colors.white
                                                      .withOpacity(0.05)),
                                          columns: const [
                                            DataColumn(
                                                label: Text('IDENTIDAD',
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12))),
                                            DataColumn(
                                                label: Text('DNI PROTEGIDO',
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12))),
                                            DataColumn(
                                                label: Text('AUDITORÍA',
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12))),
                                          ],
                                          rows: docs.map((doc) {
                                            final data = doc.data()
                                                as Map<String, dynamic>;
                                            final athId = doc.id;
                                            final fullName =
                                                data['full_name'] ??
                                                    data['fullName'] ??
                                                    'Desconocido';
                                            final teamCat =
                                                data['teamOrCategory'] ??
                                                    data['sport'] ??
                                                    'N/A';
                                            final isVisible =
                                                _unmaskedDniVisibility[
                                                        athId] ??
                                                    false;

                                            return DataRow(cells: [
                                              DataCell(Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(fullName,
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold)),
                                                  Text(
                                                      teamCat
                                                          .toString()
                                                          .toUpperCase(),
                                                      style: const TextStyle(
                                                          color: Colors.white54,
                                                          fontSize: 9,
                                                          fontWeight:
                                                              FontWeight.w600)),
                                                ],
                                              )),
                                              DataCell(Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: isVisible
                                                      ? Colors.white
                                                          .withOpacity(0.2)
                                                      : Colors.black12,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  isVisible
                                                      ? (_unmaskedDniData[
                                                              athId] ??
                                                          'N/A')
                                                      : '••••••••••',
                                                  style: TextStyle(
                                                    color: isVisible
                                                        ? Colors.white
                                                        : Colors.white24,
                                                    fontFamily: 'monospace',
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              )),
                                              DataCell(IconButton(
                                                icon: Icon(
                                                  isVisible
                                                      ? Icons.remove_red_eye
                                                      : Icons
                                                          .remove_red_eye_outlined,
                                                  color: isVisible
                                                      ? Colors.white
                                                      : Colors.white38,
                                                ),
                                                onPressed: () =>
                                                    _revealDni(athId),
                                              )),
                                            ]);
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),
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

  Widget _buildMiniStat(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 12),
            Text(label,
                style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
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
}

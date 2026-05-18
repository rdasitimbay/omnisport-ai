import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// CRM Médico — panel para el cuerpo médico / administrador.
///
/// Permite:
///  • Ver lesiones activas de todos los atletas de la institución.
///  • Registrar nuevas lesiones (CF registerInjury → status "Lesionado / No Apto").
///  • Adjuntar documentos médicos (radiografías, informes).
///  • Emitir alta médica (CF issueMedicalDischarge → status "Acceso Autorizado").
///
/// Seguridad:
///  • Solo roles admin / medico pueden acceder.
///  • Datos médicos bajo consentimiento datosSalud (LOPDP Art. 10).
class CrmMedicoScreen extends StatefulWidget {
  final String institutionId;
  const CrmMedicoScreen({super.key, required this.institutionId});

  @override
  State<CrmMedicoScreen> createState() => _CrmMedicoScreenState();
}

class _CrmMedicoScreenState extends State<CrmMedicoScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('CRM Médico',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFF00E676),
          labelColor: const Color(0xFF00E676),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.monitor_heart_rounded), text: 'Lesiones Activas'),
            Tab(icon: Icon(Icons.add_circle_rounded), text: 'Registrar'),
          ],
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A0A), Color(0xFF001225)],
          ),
        ),
        child: SafeArea(
          child: TabBarView(
            controller: _tabs,
            children: [
              _ActiveInjuriesTab(institutionId: widget.institutionId),
              _RegisterInjuryTab(institutionId: widget.institutionId),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 1 — Lesiones Activas
// ═══════════════════════════════════════════════════════════════════════════

class _ActiveInjuriesTab extends StatelessWidget {
  final String institutionId;
  const _ActiveInjuriesTab({required this.institutionId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('athletes')
          .where('ownerInstitutionId', isEqualTo: institutionId)
          .where('status', isEqualTo: 'Lesionado / No Apto')
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E676)));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.health_and_safety_rounded,
                    color: Color(0xFF00E676), size: 64),
                const SizedBox(height: 16),
                const Text('Sin lesiones activas',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Todos los atletas de $institutionId están aptos.',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                    textAlign: TextAlign.center),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _InjuredAthleteCard(
            athleteDoc: docs[i],
          ),
        );
      },
    );
  }
}

class _InjuredAthleteCard extends StatelessWidget {
  final QueryDocumentSnapshot athleteDoc;
  const _InjuredAthleteCard({required this.athleteDoc});

  @override
  Widget build(BuildContext context) {
    final data       = athleteDoc.data()! as Map<String, dynamic>;
    final name       = data['full_name']       as String? ?? 'Atleta';
    final category   = data['teamOrCategory']  as String? ?? '';
    final injuryDate = data['lastInjuryDate']  as Timestamp?;
    final daysAgo    = injuryDate != null
        ? DateTime.now().difference(injuryDate.toDate()).inDays
        : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFF1744).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: const Color(0xFFFF1744).withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.medical_services_rounded,
                      color: Color(0xFFFF5252), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ),
                  _StatusChip(label: 'NO APTO', color: const Color(0xFFFF1744)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (category.isNotEmpty)
                    _InfoPill(label: category, icon: Icons.category_rounded),
                  if (daysAgo != null) ...[
                    const SizedBox(width: 8),
                    _InfoPill(
                      label: daysAgo == 0
                          ? 'Hoy'
                          : 'Hace $daysAgo día${daysAgo == 1 ? '' : 's'}',
                      icon: Icons.calendar_today_rounded,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              // Injuries sub-stream for this athlete
              _InjuryList(athleteUid: athleteDoc.id),
            ],
          ),
        ),
      ),
    );
  }
}

class _InjuryList extends StatelessWidget {
  final String athleteUid;
  const _InjuryList({required this.athleteUid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('medical_records')
          .doc(athleteUid)
          .collection('injuries')
          .where('status', isEqualTo: 'active')
          .orderBy('reportedAt', descending: true)
          .limit(3)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 24,
            child: Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
              ),
            ),
          );
        }
        final injuries = snap.data?.docs ?? [];
        if (injuries.isEmpty) return const SizedBox.shrink();

        return Column(
          children: injuries.map((inj) {
            final iData    = inj.data()! as Map<String, dynamic>;
            final type     = iData['injuryType']  as String? ?? 'otro';
            final severity = iData['severity']    as String? ?? 'yellow';
            final sevColor = severity == 'red'
                ? const Color(0xFFFF1744)
                : severity == 'yellow'
                    ? const Color(0xFFFFB300)
                    : const Color(0xFF00E676);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                        color: sevColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(type,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ),
                  _DischargeButton(
                    athleteUid: athleteUid,
                    injuryId: inj.id,
                    injuryType: type,
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _DischargeButton extends StatelessWidget {
  final String athleteUid;
  final String injuryId;
  final String injuryType;
  const _DischargeButton({
    required this.athleteUid,
    required this.injuryId,
    required this.injuryType,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _showDischargeSheet(context),
      icon: const Icon(Icons.check_circle_rounded,
          color: Color(0xFF00E676), size: 14),
      label: const Text('Dar Alta',
          style: TextStyle(color: Color(0xFF00E676), fontSize: 11)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  void _showDischargeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MedicalDischargeSheet(
        athleteUid: athleteUid,
        injuryId: injuryId,
        injuryType: injuryType,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MODAL — Alta Médica
// ═══════════════════════════════════════════════════════════════════════════

class _MedicalDischargeSheet extends StatefulWidget {
  final String athleteUid;
  final String injuryId;
  final String injuryType;
  const _MedicalDischargeSheet({
    required this.athleteUid,
    required this.injuryId,
    required this.injuryType,
  });

  @override
  State<_MedicalDischargeSheet> createState() => _MedicalDischargeSheetState();
}

class _MedicalDischargeSheetState extends State<_MedicalDischargeSheet> {
  final _notesCtrl = TextEditingController();
  File? _docFile;
  bool  _uploading = false;
  bool  _submitting = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDoc() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (picked != null && mounted) {
      setState(() => _docFile = File(picked.path));
    }
  }

  Future<String?> _uploadDoc() async {
    if (_docFile == null) return null;
    setState(() => _uploading = true);
    try {
      final ref = FirebaseStorage.instance.ref(
          'medical_docs/${widget.athleteUid}/${widget.injuryId}_discharge_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(_docFile!);
      return await ref.getDownloadURL();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final docUrl = await _uploadDoc();
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('issueMedicalDischarge')
          .call({
        'athleteUid':      widget.athleteUid,
        'injuryId':        widget.injuryId,
        'dischargeDocUrl': docUrl ?? '',
        'dischargeNotes':  _notesCtrl.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alta médica emitida. Atleta habilitado para competir.'),
            backgroundColor: Color(0xFF00E676),
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.message ?? e.code),
              backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
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
            const Row(
              children: [
                Icon(Icons.medical_services_rounded,
                    color: Color(0xFF00E676), size: 20),
                SizedBox(width: 10),
                Text('Emitir Alta Médica',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17)),
              ],
            ),
            const SizedBox(height: 6),
            Text('Lesión: ${widget.injuryType}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 20),

            // Document upload
            GestureDetector(
              onTap: _uploading ? null : _pickDoc,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: _docFile != null
                      ? const Color(0xFF00E676).withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _docFile != null
                        ? const Color(0xFF00E676).withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _docFile != null
                          ? Icons.check_circle_rounded
                          : Icons.upload_file_rounded,
                      color: _docFile != null
                          ? const Color(0xFF00E676)
                          : Colors.white38,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _docFile != null
                            ? 'Documento de alta adjunto'
                            : 'Adjuntar documento de alta (foto/radiografía)',
                        style: TextStyle(
                          color: _docFile != null
                              ? const Color(0xFF00E676)
                              : Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Notes
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              maxLength: 500,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Notas clínicas del alta (opcional)',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.15)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.15)),
                ),
                counterStyle:
                    const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_submitting || _uploading) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: (_submitting || _uploading)
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.check_circle_rounded),
                label: Text(
                  _uploading
                      ? 'Subiendo documento…'
                      : _submitting
                          ? 'Emitiendo alta…'
                          : 'Confirmar Alta Médica',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 2 — Registrar nueva lesión
// ═══════════════════════════════════════════════════════════════════════════

class _RegisterInjuryTab extends StatefulWidget {
  final String institutionId;
  const _RegisterInjuryTab({required this.institutionId});

  @override
  State<_RegisterInjuryTab> createState() => _RegisterInjuryTabState();
}

class _RegisterInjuryTabState extends State<_RegisterInjuryTab> {
  String? _selectedAthleteUid;
  String  _selectedAthleteName = '';
  String  _injuryType          = 'contusion';
  String  _severity            = 'yellow';
  String  _bodyLocation        = '';
  final   _descCtrl            = TextEditingController();
  File?   _docFile;
  bool    _submitting          = false;
  bool    _uploadingDoc        = false;

  static const _injuryTypes = [
    ('contusion',              'Contusión / Golpe'),
    ('esguince',               'Esguince / Torcedura'),
    ('fractura_sospecha',      'Sospecha de Fractura'),
    ('golpe_cabeza',           'Golpe en la Cabeza'),
    ('dificultad_respiratoria','Dificultad Respiratoria'),
    ('herida_abierta',         'Herida Abierta'),
    ('desmayo',                'Síncope / Desmayo'),
    ('otro',                   'Otro'),
  ];

  static const _severities = [
    ('red',    'Emergencia',  Color(0xFFFF1744)),
    ('yellow', 'Precaución',  Color(0xFFFFB300)),
    ('green',  'Leve',        Color(0xFF00E676)),
  ];

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDoc() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (picked != null && mounted) {
      setState(() => _docFile = File(picked.path));
    }
  }

  Future<String?> _uploadDoc(String athleteUid) async {
    if (_docFile == null) return null;
    setState(() => _uploadingDoc = true);
    try {
      final ref = FirebaseStorage.instance.ref(
          'medical_docs/$athleteUid/injury_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(_docFile!);
      return await ref.getDownloadURL();
    } finally {
      if (mounted) setState(() => _uploadingDoc = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedAthleteUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Selecciona un atleta primero.'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final docUrl = await _uploadDoc(_selectedAthleteUid!);
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('registerInjury')
          .call({
        'athleteUid':   _selectedAthleteUid,
        'injuryType':   _injuryType,
        'description':  _descCtrl.text.trim(),
        'severity':     _severity,
        'bodyLocation': _bodyLocation.trim(),
        'documentUrl':  docUrl ?? '',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Lesión registrada. $_selectedAthleteName está en estado "No Apto".'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
        // Reset form
        setState(() {
          _selectedAthleteUid  = null;
          _selectedAthleteName = '';
          _injuryType          = 'contusion';
          _severity            = 'yellow';
          _bodyLocation        = '';
          _docFile             = null;
        });
        _descCtrl.clear();
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.message ?? e.code),
              backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Atleta', Icons.person_rounded),
          const SizedBox(height: 10),
          _buildAthleteSelector(),
          const SizedBox(height: 20),

          _sectionLabel('Tipo de lesión', Icons.medical_services_rounded),
          const SizedBox(height: 10),
          _buildInjuryTypeGrid(),
          const SizedBox(height: 20),

          _sectionLabel('Severidad', Icons.warning_rounded),
          const SizedBox(height: 10),
          _buildSeverityRow(),
          const SizedBox(height: 20),

          _sectionLabel('Zona corporal (opcional)',
              Icons.accessibility_new_rounded),
          const SizedBox(height: 10),
          _buildTextField(
            hint: 'Ej. rodilla izquierda, hombro derecho…',
            onChanged: (v) => _bodyLocation = v,
          ),
          const SizedBox(height: 20),

          _sectionLabel('Descripción clínica (opcional)',
              Icons.edit_note_rounded),
          const SizedBox(height: 10),
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            maxLength: 500,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: _inputDecoration('Describe los síntomas y mecanismo de la lesión…'),
          ),
          const SizedBox(height: 20),

          _sectionLabel('Documento adjunto (opcional)',
              Icons.attach_file_rounded),
          const SizedBox(height: 10),
          _buildDocUploadTile(),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_submitting || _uploadingDoc) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF1744),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              icon: (_submitting || _uploadingDoc)
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.medical_services_rounded),
              label: Text(
                _submitting ? 'Registrando…' : 'Registrar Lesión',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'El atleta quedará en estado "Lesionado / No Apto"\nhasta recibir el alta médica.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildAthleteSelector() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('athletes')
          .where('ownerInstitutionId', isEqualTo: widget.institutionId)
          .orderBy('full_name')
          .snapshots(),
      builder: (_, snap) {
        final docs = snap.data?.docs ?? [];
        return _glassContainer(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedAthleteUid,
              dropdownColor: const Color(0xFF0D1B3E),
              isExpanded: true,
              hint: const Text('Seleccionar atleta',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
              icon: const Icon(Icons.expand_more,
                  color: Color(0xFF00E5FF)),
              items: docs.map((d) {
                final data = d.data()! as Map<String, dynamic>;
                final name = data['full_name'] as String? ?? d.id;
                final cat  = data['teamOrCategory'] as String? ?? '';
                return DropdownMenuItem<String>(
                  value: d.id,
                  child: Text(
                    cat.isNotEmpty ? '$name — $cat' : name,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13),
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v == null) return;
                final d = docs.firstWhere((d) => d.id == v);
                final name = (d.data()! as Map<String, dynamic>)['full_name']
                    as String? ?? '';
                setState(() {
                  _selectedAthleteUid  = v;
                  _selectedAthleteName = name;
                });
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildInjuryTypeGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 3,
      children: _injuryTypes.map(((String, String) item) {
        final selected = _injuryType == item.$1;
        return GestureDetector(
          onTap: () => setState(() => _injuryType = item.$1),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFFF1744).withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? const Color(0xFFFF1744)
                    : Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Text(item.$2,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                )),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSeverityRow() {
    return Row(
      children: _severities.map(((String, String, Color) s) {
        final selected = _severity == s.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _severity = s.$1),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? s.$3.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? s.$3
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                        color: s.$3, shape: BoxShape.circle),
                  ),
                  const SizedBox(height: 4),
                  Text(s.$2,
                      style: TextStyle(
                          color: selected ? s.$3 : Colors.white38,
                          fontSize: 10,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDocUploadTile() {
    return GestureDetector(
      onTap: _uploadingDoc ? null : _pickDoc,
      child: _glassContainer(
        borderColor: _docFile != null
            ? const Color(0xFF00E5FF).withValues(alpha: 0.4)
            : null,
        child: Row(
          children: [
            Icon(
              _docFile != null ? Icons.check_circle_rounded : Icons.add_photo_alternate_rounded,
              color: _docFile != null ? const Color(0xFF00E5FF) : Colors.white38,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _docFile != null
                    ? 'Documento adjunto ✓'
                    : 'Foto/radiografía (imagen)',
                style: TextStyle(
                  color: _docFile != null ? const Color(0xFF00E5FF) : Colors.white38,
                  fontSize: 13,
                ),
              ),
            ),
            if (_docFile != null)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                onPressed: () => setState(() => _docFile = null),
              ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _buildTextField({required String hint, required ValueChanged<String> onChanged}) {
    return TextField(
      style: const TextStyle(color: Colors.white, fontSize: 13),
      onChanged: onChanged,
      decoration: _inputDecoration(hint),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white38),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.05),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
    ),
    counterStyle: const TextStyle(color: Colors.white38, fontSize: 10),
  );

  Widget _glassContainer({required Widget child, Color? borderColor}) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: borderColor ?? Colors.white.withValues(alpha: 0.12)),
            ),
            child: child,
          ),
        ),
      );

  Widget _sectionLabel(String label, IconData icon) => Row(
    children: [
      Icon(icon, color: const Color(0xFF00E5FF), size: 16),
      const SizedBox(width: 8),
      Text(label,
          style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 13)),
    ],
  );
}

// ── Shared UI chips ─────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Text(label,
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.bold)),
  );
}

class _InfoPill extends StatelessWidget {
  final String label;
  final IconData icon;
  const _InfoPill({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: Colors.white38, size: 12),
      const SizedBox(width: 4),
      Text(label,
          style: const TextStyle(color: Colors.white38, fontSize: 11)),
    ],
  );
}

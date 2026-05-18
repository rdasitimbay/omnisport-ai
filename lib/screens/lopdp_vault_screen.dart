import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bóveda LOPDP — panel centralizado de derechos ARCO.
///
/// Permite al usuario:
///  • Ver y revocar los 3 consentimientos granulares (Art. 10 LOPDP).
///  • Subir/actualizar la fotografía de la cédula del tutor.
///  • Ejercer Derechos ARCO: Acceso, Rectificación, Cancelación/Borrado, Oposición.
///  • Ver el historial de auditoría de sus datos.
class LopdpVaultScreen extends StatefulWidget {
  final String athleteUid;
  final String athleteName;

  const LopdpVaultScreen({
    super.key,
    required this.athleteUid,
    required this.athleteName,
  });

  @override
  State<LopdpVaultScreen> createState() => _LopdpVaultScreenState();
}

class _ConsentState {
  bool granted;
  DateTime? grantedAt;
  _ConsentState({required this.granted, this.grantedAt});
}

class _LopdpVaultScreenState extends State<LopdpVaultScreen> {
  bool _loading = true;
  bool _saving  = false;
  String? _errorMsg;

  late _ConsentState _personal;
  late _ConsentState _salud;
  late _ConsentState _notificaciones;

  bool _uploadingPhoto = false;
  String? _tutorPhotoUrl;

  @override
  void initState() {
    super.initState();
    _personal       = _ConsentState(granted: false);
    _salud          = _ConsentState(granted: false);
    _notificaciones = _ConsentState(granted: false);
    _loadConsents();
  }

  // ── Data loading ─────────────────────────────────────────────────────────

  Future<void> _loadConsents() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final uid = widget.athleteUid;
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() ?? {};
      final consents = (data['consents'] as Map<String, dynamic>?) ?? {};

      // Firestore is authoritative; fall back to SharedPreferences if not yet synced.
      if (consents.isEmpty) {
        await _seedFromSharedPreferences();
      } else {
        _personal       = _parseConsent(consents['datosPersonales']);
        _salud          = _parseConsent(consents['datosSalud']);
        _notificaciones = _parseConsent(consents['notificaciones']);
      }
      _tutorPhotoUrl = data['tutorPhotoUrl'] as String?;
    } catch (e) {
      _errorMsg = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  _ConsentState _parseConsent(dynamic raw) {
    if (raw is Map) {
      final granted   = raw['granted'] as bool? ?? false;
      final ts        = raw['grantedAt'];
      final grantedAt = ts is Timestamp ? ts.toDate() : null;
      return _ConsentState(granted: granted, grantedAt: grantedAt);
    }
    return _ConsentState(granted: false);
  }

  Future<void> _seedFromSharedPreferences() async {
    final prefs  = await SharedPreferences.getInstance();
    final nowMs  = prefs.getInt('consent_grantedAtMs');
    final date   = nowMs != null
        ? DateTime.fromMillisecondsSinceEpoch(nowMs)
        : null;
    _personal       = _ConsentState(
      granted:   prefs.getBool('consent_datosPersonales')   ?? false,
      grantedAt: date,
    );
    _salud          = _ConsentState(
      granted:   prefs.getBool('consent_datosSalud')        ?? false,
      grantedAt: date,
    );
    _notificaciones = _ConsentState(
      granted:   prefs.getBool('consent_notificaciones')    ?? false,
      grantedAt: date,
    );
    // Sync to Firestore so next load is authoritative.
    await _persistConsents();
  }

  // ── Persist ───────────────────────────────────────────────────────────────

  Future<void> _persistConsents() async {
    final uid = widget.athleteUid;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'consents': {
        'datosPersonales': {
          'granted':   _personal.granted,
          'grantedAt': _personal.grantedAt != null
              ? Timestamp.fromDate(_personal.grantedAt!)
              : FieldValue.serverTimestamp(),
        },
        'datosSalud': {
          'granted':   _salud.granted,
          'grantedAt': _salud.grantedAt != null
              ? Timestamp.fromDate(_salud.grantedAt!)
              : FieldValue.serverTimestamp(),
        },
        'notificaciones': {
          'granted':   _notificaciones.granted,
          'grantedAt': _notificaciones.grantedAt != null
              ? Timestamp.fromDate(_notificaciones.grantedAt!)
              : FieldValue.serverTimestamp(),
        },
      },
    }, SetOptions(merge: true));
  }

  Future<void> _toggleConsent(String key, _ConsentState state, bool newValue) async {
    setState(() => _saving = true);
    try {
      state.granted   = newValue;
      state.grantedAt = DateTime.now();
      await _persistConsents();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.redAccent),
        );
        state.granted = !newValue; // revert
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── ARCO actions ──────────────────────────────────────────────────────────

  Future<void> _requestDataAccess() async {
    _showArcoDialog(
      title: 'Derecho de Acceso',
      icon: Icons.download_rounded,
      description:
          'Puedes solicitar una copia de todos tus datos en nuestro sistema. '
          'Recibirás un archivo JSON en los próximos 30 días hábiles.',
      confirmLabel: 'Solicitar',
      onConfirm: () async {
        // Write an ARCO access request to Firestore — backend can pick it up.
        await FirebaseFirestore.instance.collection('arco_requests').add({
          'uid':       widget.athleteUid,
          'type':      'ACCESS',
          'status':    'pending',
          'requestedAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Solicitud de acceso enviada. Te contactaremos en ≤ 30 días.'),
              backgroundColor: Color(0xFF00E5FF),
            ),
          );
        }
      },
    );
  }

  Future<void> _requestRectification() async {
    _showArcoDialog(
      title: 'Derecho de Rectificación',
      icon: Icons.edit_rounded,
      description:
          'Para corregir datos incorrectos, contacta al administrador de tu institución '
          'o escríbenos a privacidad@omnisport.ai con el detalle de la corrección.',
      confirmLabel: 'Entendido',
      onConfirm: () async {},
    );
  }

  Future<void> _requestErasure() async {
    _showArcoDialog(
      title: 'Derecho de Cancelación / Borrado',
      icon: Icons.delete_forever_rounded,
      iconColor: Colors.redAccent,
      description:
          'Borraremos TODOS tus datos de manera irreversible (Art. 16 LOPDP). '
          'Esta acción no puede deshacerse. ¿Confirmas el borrado completo de tu perfil?',
      confirmLabel: 'Borrar mis datos',
      isDestructive: true,
      onConfirm: () async {
        try {
          await FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('requestAthleteErasure')
              .call({'uid': widget.athleteUid});

          // Delete the Auth account on client side (self-erasure flow).
          await FirebaseAuth.instance.currentUser?.delete();

          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        } on FirebaseFunctionsException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.message ?? e.code), backgroundColor: Colors.redAccent),
            );
          }
        }
      },
    );
  }

  Future<void> _requestOpposition() async {
    _showArcoDialog(
      title: 'Derecho de Oposición',
      icon: Icons.block_rounded,
      description:
          'Puedes oponerte al tratamiento de tus datos para fines no esenciales '
          '(por ejemplo, comunicaciones de marketing). Esto no afecta la gestión '
          'de asistencia ni las alertas de emergencia.',
      confirmLabel: 'Presentar oposición',
      onConfirm: () async {
        await FirebaseFirestore.instance.collection('arco_requests').add({
          'uid':       widget.athleteUid,
          'type':      'OPPOSITION',
          'status':    'pending',
          'requestedAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Oposición registrada. Responderemos en ≤ 30 días.'),
              backgroundColor: Color(0xFF00E5FF),
            ),
          );
        }
      },
    );
  }

  void _showArcoDialog({
    required String title,
    required IconData icon,
    Color? iconColor,
    required String description,
    required String confirmLabel,
    bool isDestructive = false,
    required Future<void> Function() onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B3E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(icon, color: iconColor ?? const Color(0xFF00E5FF), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        ),
        content: Text(description,
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await onConfirm();
            },
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: isDestructive ? Colors.redAccent : const Color(0xFF00E5FF),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tutor photo upload ────────────────────────────────────────────────────

  Future<void> _uploadTutorPhoto() async {
    final prefs = await SharedPreferences.getInstance();
    String? localPath = prefs.getString('tutor_photo_path');

    File? photo;
    if (localPath != null && File(localPath).existsSync()) {
      photo = File(localPath);
    } else {
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery, imageQuality: 80);
      if (picked == null) return;
      photo = File(picked.path);
    }

    setState(() => _uploadingPhoto = true);
    try {
      final ref = FirebaseStorage.instance.ref(
          'tutor_docs/${widget.athleteUid}/cedula.jpg');
      await ref.putFile(photo);
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.athleteUid)
          .set({'tutorPhotoUrl': url}, SetOptions(merge: true));

      if (mounted) setState(() => _tutorPhotoUrl = url);

      // Clear local pending path
      await prefs.remove('tutor_photo_path');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento del tutor actualizado.'),
            backgroundColor: Color(0xFF00E676),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Bóveda LOPDP',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    color: Color(0xFF00E5FF), strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF001F3F), Color(0xFF000D1A)],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
              : _errorMsg != null
                  ? _buildError()
                  : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(_errorMsg!,
          style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
    ),
  );

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      children: [
        _buildLegalHeader(),
        const SizedBox(height: 20),
        _buildConsentsSection(),
        const SizedBox(height: 20),
        _buildTutorDocSection(),
        const SizedBox(height: 20),
        _buildArcoSection(),
        const SizedBox(height: 20),
        _buildLegalFooter(),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Section: legal header ─────────────────────────────────────────────────

  Widget _buildLegalHeader() {
    return _glassCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
              border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.shield_rounded,
                color: Color(0xFF00E5FF), size: 26),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Privacidad y Gobernanza',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                SizedBox(height: 4),
                Text(
                  'LOPDP Ecuador — Ley Orgánica de Protección de Datos Personales',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section: consents ─────────────────────────────────────────────────────

  Widget _buildConsentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Consentimientos (Art. 10)', Icons.fact_check_rounded),
        const SizedBox(height: 10),
        _buildConsentTile(
          icon: Icons.person_rounded,
          title: 'Datos personales y deportivos',
          subtitle: 'Nombre, fotografía, categoría, membresía',
          state: _personal,
          onToggle: (v) => _toggleConsent('datosPersonales', _personal, v),
        ),
        const SizedBox(height: 8),
        _buildConsentTile(
          icon: Icons.favorite_rounded,
          title: 'Datos de salud y médicos',
          subtitle: 'Aptitud médica, certificaciones de entrenamiento',
          state: _salud,
          onToggle: (v) => _toggleConsent('datosSalud', _salud, v),
        ),
        const SizedBox(height: 8),
        _buildConsentTile(
          icon: Icons.notifications_rounded,
          title: 'Notificaciones al tutor',
          subtitle: 'Alertas de asistencia y emergencias',
          state: _notificaciones,
          onToggle: (v) =>
              _toggleConsent('notificaciones', _notificaciones, v),
        ),
      ],
    );
  }

  Widget _buildConsentTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required _ConsentState state,
    required ValueChanged<bool> onToggle,
  }) {
    final active = state.granted;
    return _glassCard(
      borderColor: active
          ? const Color(0xFF00E5FF).withValues(alpha: 0.35)
          : Colors.white.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(icon,
              color: active ? const Color(0xFF00E5FF) : Colors.white38,
              size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      color: active ? Colors.white : Colors.white60,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
                if (state.grantedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      active
                          ? 'Otorgado: ${_fmtDate(state.grantedAt!)}'
                          : 'Revocado: ${_fmtDate(state.grantedAt!)}',
                      style: TextStyle(
                        color: active
                            ? const Color(0xFF00E5FF).withValues(alpha: 0.7)
                            : Colors.orangeAccent.withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Switch.adaptive(
            value: active,
            onChanged: _saving ? null : onToggle,
            activeColor: const Color(0xFF00E5FF),
            inactiveThumbColor: Colors.white38,
            inactiveTrackColor: Colors.white12,
          ),
        ],
      ),
    );
  }

  // ── Section: tutor document ───────────────────────────────────────────────

  Widget _buildTutorDocSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Documento del tutor (Art. 10)', Icons.badge_rounded),
        const SizedBox(height: 10),
        _glassCard(
          child: Row(
            children: [
              Container(
                width: 56,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white12,
                ),
                child: _tutorPhotoUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _tutorPhotoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image, color: Colors.white38),
                        ),
                      )
                    : const Icon(Icons.upload_file_rounded,
                        color: Colors.white38, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tutorPhotoUrl != null
                          ? 'Cédula del tutor registrada'
                          : 'Sin documento registrado',
                      style: TextStyle(
                        color: _tutorPhotoUrl != null
                            ? const Color(0xFF00E676)
                            : Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text('Fotografía de la cédula del tutor legal',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              TextButton(
                onPressed: _uploadingPhoto ? null : _uploadTutorPhoto,
                child: _uploadingPhoto
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF00E5FF)),
                      )
                    : Text(
                        _tutorPhotoUrl != null ? 'Actualizar' : 'Subir',
                        style: const TextStyle(
                            color: Color(0xFF00E5FF), fontSize: 12),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Section: ARCO rights ──────────────────────────────────────────────────

  Widget _buildArcoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Derechos ARCO', Icons.gavel_rounded),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _arcoButton(
                icon: Icons.download_rounded,
                label: 'Acceso',
                sub: 'Mis datos',
                color: const Color(0xFF00E5FF),
                onTap: _requestDataAccess,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _arcoButton(
                icon: Icons.edit_rounded,
                label: 'Rectificación',
                sub: 'Corregir datos',
                color: const Color(0xFFFFB300),
                onTap: _requestRectification,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _arcoButton(
                icon: Icons.block_rounded,
                label: 'Oposición',
                sub: 'Limitar uso',
                color: Colors.orangeAccent,
                onTap: _requestOpposition,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _arcoButton(
                icon: Icons.delete_forever_rounded,
                label: 'Cancelación',
                sub: 'Borrar perfil',
                color: Colors.redAccent,
                onTap: _requestErasure,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _arcoButton({
    required IconData icon,
    required String label,
    required String sub,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            Text(sub,
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ── Legal footer ──────────────────────────────────────────────────────────

  Widget _buildLegalFooter() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: Colors.white38, size: 16),
              SizedBox(width: 8),
              Text('Base Legal',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          _legalLine('Art. 10 — Consentimiento informado y granular'),
          _legalLine('Art. 13 — Derechos de los titulares'),
          _legalLine('Art. 16 — Derecho al olvido y cancelación'),
          _legalLine('Art. 26 — Tratamiento de datos de menores'),
          _legalLine('Art. 37 — Registro de auditoría inmutable'),
          const SizedBox(height: 8),
          const Text(
            'Responsable: SOFTLUTIONS EC · privacidad@omnisport.ai',
            style: TextStyle(color: Colors.white30, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _legalLine(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        const Text('•  ', style: TextStyle(color: Colors.white30, fontSize: 11)),
        Text(text, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    ),
  );

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _glassCard({required Widget child, Color? borderColor}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: borderColor ?? Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

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

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}

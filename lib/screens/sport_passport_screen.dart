import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:hive/hive.dart';
import '../models/smart_id_credential.dart';
import '../widgets/smart_id_card.dart';
import 'referee_verify_screen.dart';

enum _PassportState { loading, loaded, offline, error }

/// Pasaporte Deportivo Digital — pantalla principal del atleta.
///
/// Flujo de carga:
///   1. Intenta recuperar credencial desde caché Hive (disponible offline).
///   2. Si hay red, llama a generateSmartId CF para refrescar el token (30 días).
///   3. Guarda la credencial nueva en Hive y actualiza la UI.
///
/// Modo Offline: si no hay red pero existe caché válida, muestra la credencial
/// con banner naranja "MODO OFFLINE" y la fecha de última sincronización.
class SportPassportScreen extends StatefulWidget {
  final String athleteId;
  final String athleteName;

  const SportPassportScreen({
    super.key,
    required this.athleteId,
    required this.athleteName,
  });

  @override
  State<SportPassportScreen> createState() => _SportPassportScreenState();
}

class _SportPassportScreenState extends State<SportPassportScreen>
    with SingleTickerProviderStateMixin {
  _PassportState _state = _PassportState.loading;
  SmartIdCredential? _credential;
  String _errorMsg = '';
  late AnimationController _cardAnim;
  late Animation<double> _cardFade;
  late Animation<Offset> _cardSlide;

  static const _cacheBox = 'smart_id_cache';

  @override
  void initState() {
    super.initState();
    _cardAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _cardFade  = CurvedAnimation(parent: _cardAnim, curve: Curves.easeOut);
    _cardSlide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _cardAnim, curve: Curves.easeOutCubic));
    _loadCredential();
  }

  @override
  void dispose() {
    _cardAnim.dispose();
    super.dispose();
  }

  // ── Cache helpers ─────────────────────────────────────────────────────────

  Future<SmartIdCredential?> _loadFromCache() async {
    try {
      final box = await Hive.openBox<dynamic>(_cacheBox);
      final raw = box.get('cred_${widget.athleteId}');
      if (raw == null) return null;
      return SmartIdCredential.fromMap(Map<String, dynamic>.from(raw as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToCache(SmartIdCredential cred) async {
    try {
      final box = await Hive.openBox<dynamic>(_cacheBox);
      await box.put('cred_${widget.athleteId}', cred.toMap());
    } catch (_) {}
  }

  // ── Load pipeline ─────────────────────────────────────────────────────────

  Future<void> _loadCredential() async {
    if (!mounted) return;
    setState(() => _state = _PassportState.loading);

    // Step 1 — restore from cache immediately for instant display.
    final cached = await _loadFromCache();
    if (cached != null && !cached.isExpired) {
      if (mounted) {
        setState(() {
          _credential = cached;
          _state = _PassportState.offline;
        });
        _cardAnim.forward(from: 0);
      }
    }

    // Step 2 — try to refresh from server.
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('generateSmartId')
          .call({'athleteUid': widget.athleteId});

      final data       = Map<String, dynamic>.from(result.data as Map);
      final token      = data['token']      as String;
      final smartIdNum = data['smartIdNum'] as String;
      final isEligible = data['isEligible'] as bool;
      final medicalOk  = data['medicalOk']  as bool;
      final paymentOk  = data['paymentOk']  as bool;
      final expMs      = (data['expMs'] as num).toInt();

      final cred = SmartIdCredential.fromTokenResponse(
        athleteUid: widget.athleteId,
        token:      token,
        smartIdNum: smartIdNum,
        isEligible: isEligible,
        medicalOk:  medicalOk,
        paymentOk:  paymentOk,
        expMs:      expMs,
      );
      await _saveToCache(cred);

      if (mounted) {
        final wasOffline = _state == _PassportState.offline;
        setState(() {
          _credential = cred;
          _state = _PassportState.loaded;
        });
        if (wasOffline) _cardAnim.forward(from: 0);
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted && _credential == null) {
        setState(() {
          _state = _PassportState.error;
          _errorMsg = '${e.code}: ${e.message}';
        });
      } else if (mounted) {
        // Keep showing cached credential in offline mode.
        setState(() => _state = _PassportState.offline);
      }
    } catch (e) {
      if (mounted && _credential == null) {
        setState(() {
          _state = _PassportState.error;
          _errorMsg = e.toString();
        });
      } else if (mounted) {
        setState(() => _state = _PassportState.offline);
      }
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
        title: const Text(
          'Pasaporte Deportivo',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        actions: [
          if (_state != _PassportState.loading)
            IconButton(
              icon: const Icon(CupertinoIcons.refresh, color: Colors.white),
              onPressed: _loadCredential,
              tooltip: 'Renovar pasaporte',
            ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF001F3F), Color(0xFF00264D), Color(0xFF001428)],
          ),
        ),
        child: SafeArea(
          child: switch (_state) {
            _PassportState.loading => _buildLoading(),
            _PassportState.error   => _buildError(),
            _             => _buildPassport(),
          },
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF00E5FF), strokeWidth: 2),
          SizedBox(height: 16),
          Text('Generando pasaporte…', style: TextStyle(color: Colors.white54, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 56),
            const SizedBox(height: 16),
            const Text('No se pudo generar el pasaporte',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_errorMsg, style: const TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadCredential,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: const Color(0xFF001F3F),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPassport() {
    final cred = _credential!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        children: [
          if (_state == _PassportState.offline) _buildOfflineBanner(),
          const SizedBox(height: 16),
          SlideTransition(
            position: _cardSlide,
            child: FadeTransition(
              opacity: _cardFade,
              child: SmartIdCard(credential: cred),
            ),
          ),
          const SizedBox(height: 32),
          _buildEligibilityDetail(cred),
          const SizedBox(height: 24),
          _buildRefereeButton(cred),
          const SizedBox(height: 16),
          _buildLopdpNotice(),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner() {
    final cached = _credential!;
    final syncDate = DateTime.fromMillisecondsSinceEpoch(cached.cachedAtMs);
    final fmt = '${syncDate.day}/${syncDate.month}/${syncDate.year} ${syncDate.hour}:${syncDate.minute.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orangeAccent.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.orangeAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('MODO OFFLINE',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 11,
                        fontWeight: FontWeight.bold, letterSpacing: 1)),
                Text('Última sincronización: $fmt',
                    style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEligibilityDetail(SmartIdCredential cred) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Estado de Elegibilidad',
                  style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1)),
              const SizedBox(height: 16),
              _detailRow(
                icon: Icons.credit_card,
                label: 'Estado de pago',
                value: cred.paymentOk ? 'Al Día' : 'Pendiente',
                ok: cred.paymentOk,
              ),
              const SizedBox(height: 12),
              _detailRow(
                icon: Icons.favorite,
                label: 'Revisión médica',
                value: cred.medicalOk ? 'Vigente (< 6 meses)' : 'Vencida o sin registro',
                ok: cred.medicalOk,
              ),
              const SizedBox(height: 12),
              _detailRow(
                icon: Icons.verified_user,
                label: 'Elegibilidad general',
                value: cred.isEligible ? 'APTO PARA COMPETIR' : 'NO APTO',
                ok: cred.isEligible,
                large: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
    required bool ok,
    bool large = false,
  }) {
    final color = ok ? const Color(0xFF00E676) : Colors.orangeAccent;
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              Text(value,
                  style: TextStyle(
                    color: color,
                    fontSize: large ? 13 : 12,
                    fontWeight: large ? FontWeight.bold : FontWeight.w500,
                  )),
            ],
          ),
        ),
        Icon(ok ? Icons.check_circle : Icons.cancel, color: color, size: 20),
      ],
    );
  }

  Widget _buildRefereeButton(SmartIdCredential cred) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RefereeVerifyScreen(token: cred.token),
          ),
        ),
        icon: const Icon(CupertinoIcons.barcode_viewfinder, size: 20),
        label: const Text('Vista Árbitro (Ofuscada)', style: TextStyle(letterSpacing: 0.5)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF00E5FF),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildLopdpNotice() {
    return Text(
      'Protegido por LOPDP Art. 5 — Minimización de datos.\n'
      'El árbitro solo ve elegibilidad y estado médico.',
      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10, height: 1.5),
      textAlign: TextAlign.center,
    );
  }
}

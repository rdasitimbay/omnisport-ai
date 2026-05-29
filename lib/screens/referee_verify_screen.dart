import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Vista árbitro — resultado de verificación de Smart ID.
///
/// Muestra ÚNICAMENTE: PASA/NO PASA, foto, estado médico y categoría.
/// fullName está deliberadamente omitido (LOPDP Art. 5 — minimización).
/// La verificación ocurre en el servidor (verifySmartId CF) que valida
/// firma HMAC y expiración antes de devolver los datos permitidos.
class RefereeVerifyScreen extends StatefulWidget {
  final String token;

  const RefereeVerifyScreen({super.key, required this.token});

  @override
  State<RefereeVerifyScreen> createState() => _RefereeVerifyScreenState();
}

class _RefereeVerifyScreenState extends State<RefereeVerifyScreen> {
  bool _loading = true;
  Map<String, dynamic>? _result;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('verifySmartId')
          .call({'token': widget.token});
      if (mounted) {
        setState(() {
          _result  = Map<String, dynamic>.from(res.data as Map? ?? {});
          _loading = false;
        });
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() { _loading = false; _errorMsg = e.message ?? e.code; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _errorMsg = e.toString(); });
    }
  }

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
        title: const Text('Verificación Árbitro',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
              : _errorMsg != null
                  ? _buildError()
                  : _buildResult(),
        ),
      ),
    );
  }

  Widget _buildError() {
    final isExpired = _errorMsg?.contains('expirado') == true ||
                      _errorMsg?.contains('deadline') == true;
    final isInvalid = _errorMsg?.contains('inválida') == true ||
                      _errorMsg?.contains('permission') == true;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bigVerdict(false),
            const SizedBox(height: 24),
            Text(
              isExpired ? 'Pasaporte expirado' : isInvalid ? 'Firma inválida' : 'Error de verificación',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_errorMsg ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final r          = _result!;
    final isEligible = r['isEligible'] as bool? ?? false;
    final medicalOk  = r['medicalOk']  as bool? ?? false;
    final category   = r['category']   as String? ?? '';
    final smartIdNum = r['smartIdNum'] as String? ?? '';
    final photoUrl   = r['photoUrl']   as String? ?? '';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            _bigVerdict(isEligible),
            const SizedBox(height: 32),
            _buildPhotoAndDetails(photoUrl, category, smartIdNum, medicalOk),
            const SizedBox(height: 24),
            _buildPrivacyNote(),
          ],
        ),
      ),
    );
  }

  Widget _bigVerdict(bool eligible) {
    final color = eligible ? const Color(0xFF00E676) : const Color(0xFFFF1744);
    final label = eligible ? 'PASA' : 'NO PASA';
    final icon  = eligible ? Icons.check_circle_rounded : Icons.cancel_rounded;

    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.12),
            border: Border.all(color: color, width: 3),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 30, spreadRadius: 4)],
          ),
          child: Icon(icon, color: color, size: 64),
        ),
        const SizedBox(height: 16),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 40,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoAndDetails(
      String photoUrl, String category, String smartIdNum, bool medicalOk) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              // Foto ofuscada con overlay puntillado (privacidad visual)
              Stack(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: photoUrl.isNotEmpty
                          ? Image.network(photoUrl, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _photoFallback())
                          : _photoFallback(),
                    ),
                  ),
                  // Overlay semitransparente — identidad visible pero no legible a distancia
                  Positioned.fill(
                    child: ClipOval(
                      child: Container(color: Colors.black.withValues(alpha: 0.25)),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nombre deliberadamente omitido (LOPDP Art. 5)
                    const Text('IDENTIDAD VERIFICADA',
                        style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
                    const SizedBox(height: 6),
                    if (category.isNotEmpty)
                      _infoRow(Icons.category_rounded, category),
                    const SizedBox(height: 4),
                    _infoRow(
                      Icons.favorite,
                      medicalOk ? 'Médico: Vigente' : 'Médico: No vigente',
                      color: medicalOk ? const Color(0xFF00E5FF) : Colors.orangeAccent,
                    ),
                    const SizedBox(height: 4),
                    Text(smartIdNum,
                        style: const TextStyle(
                          color: Color(0xFF00E5FF), fontSize: 10,
                          fontFamily: 'monospace', letterSpacing: 1,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoFallback() => Container(
    color: const Color(0xFF1A3A6B),
    child: const Icon(Icons.person, color: Colors.white38, size: 36),
  );

  Widget _infoRow(IconData icon, String text, {Color color = Colors.white}) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12))),
      ],
    );
  }

  Widget _buildPrivacyNote() {
    return Text(
      'Vista árbitro — nombre omitido por LOPDP Art. 5.\n'
      'Verificación criptográfica HMAC-SHA256 en servidor.',
      style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10, height: 1.5),
      textAlign: TextAlign.center,
    );
  }
}

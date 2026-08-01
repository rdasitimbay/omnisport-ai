import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/secure_qr_view.dart';

/// Pantalla "DPO SHIELD" — Pase de Acceso QR Dinámico.
///
/// Migrado de JWT local (secreto hardcodeado) a [SecureQRView] que invoca
/// `generateAttendanceToken` en el backend con HMAC-SHA256 + Master Key.
/// El token rota cada 45 s y expira en el servidor (anti-replay).
class QrGeneratorScreen extends StatelessWidget {
  final String? athleteUid;

  const QrGeneratorScreen({Key? key, this.athleteUid}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final targetAthleteUid = athleteUid ?? user?.uid ?? '';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'DPO SHIELD',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 2,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF001F3F), Color(0xFF00E5FF)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "Pase de Acceso",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Muestra este QR al Staff en el acceso.",
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 32),

                        // ── QR Dinámico Seguro ────────────────────────
                        // SecureQRView invoca generateAttendanceToken en
                        // el backend. El token rota cada 45 s y se valida
                        // con HMAC-SHA256 + timingSafeEqual + anti-replay.
                        if (targetAthleteUid.isNotEmpty)
                          SecureQRView(athleteUid: targetAthleteUid)
                        else
                          const Text(
                            'Error: sesión no válida',
                            style: TextStyle(color: Colors.redAccent),
                          ),

                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              CupertinoIcons.shield_lefthalf_fill,
                              color: Color(0xFF00E5FF),
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Text(
                              "Token criptográfico · Servidor verificado",
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

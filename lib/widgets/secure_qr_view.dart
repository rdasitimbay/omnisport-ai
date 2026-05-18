import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';

class SecureQRView extends StatefulWidget {
  final String athleteUid;

  const SecureQRView({Key? key, required this.athleteUid}) : super(key: key);

  @override
  State<SecureQRView> createState() => _SecureQRViewState();
}

class _SecureQRViewState extends State<SecureQRView> {
  late Stream<String> _tokenStream;

  @override
  void initState() {
    super.initState();
    _tokenStream = _generateTokenStream();
  }

  Stream<String> _generateTokenStream() async* {
    while (true) {
      try {
        final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('generateAttendanceToken')
            .call({'athleteUid': widget.athleteUid});
        
        yield result.data['token'] as String;
      } catch (e) {
        debugPrint('Error generating attendance token: $e');
        // En caso de error (ej. sin red), podemos ceder un estado de error
        // o simplemente esperar al siguiente ciclo.
        // No enviamos un token inválido para no comprometer el flujo.
      }
      // Esperar 45 segundos antes de generar el siguiente token
      await Future.delayed(const Duration(seconds: 45));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: _tokenStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(
            child: Text(
              'Error de red.\nReintentando...', 
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.redAccent),
            ),
          );
        }

        final token = snapshot.data!;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: QrImageView(
                data: token,
                version: QrVersions.auto,
                size: 250.0,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF0A192F),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF0A192F),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.security, color: Color(0xFF00E5FF), size: 16),
                SizedBox(width: 8),
                Text(
                  'Protegido LOPDP - Expira en 45s',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

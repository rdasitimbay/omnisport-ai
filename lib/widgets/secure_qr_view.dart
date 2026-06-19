import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SecureQRView extends StatefulWidget {
  final String athleteUid;

  const SecureQRView({super.key, required this.athleteUid});

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
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          yield 'ERROR:unauthenticated';
          await Future.delayed(const Duration(seconds: 15));
          continue;
        }

        final callable = FirebaseFunctions.instance.httpsCallable('generateAttendanceToken');
        final response = await callable.call(<String, dynamic>{
          'athleteUid': widget.athleteUid,
        });

        final token = response.data['token'] as String?;
        if (token != null && token.isNotEmpty) {
          yield token;
        } else {
          yield 'ERROR:token_empty';
        }
      } catch (e) {
        debugPrint('Error generating attendance token: $e');
        final msg = e.toString();
        yield 'ERROR:${msg.length > 40 ? msg.substring(0, 40) : msg}';
      }
      await Future.delayed(const Duration(seconds: 15));
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off, color: Colors.orangeAccent, size: 40),
                SizedBox(height: 12),
                Text(
                  'Sin conexión.\nReintentando en 15s…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
                ),
              ],
            ),
          );
        }

        final token = snapshot.data!;

        if (token.startsWith('ERROR:')) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, color: Colors.orangeAccent, size: 40),
                const SizedBox(height: 12),
                const Text(
                  'Servicio temporalmente no disponible.\nReintentando en 15s…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
                ),
              ],
            ),
          );
        }

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
                backgroundColor: Colors.white,
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
                  'Protegido LOPDP - Expira en 15s',
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

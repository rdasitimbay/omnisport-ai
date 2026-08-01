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

class _SecureQRViewState extends State<SecureQRView> with SingleTickerProviderStateMixin {
  late Stream<String> _tokenStream;
  StreamSubscription<String>? _subscription;
  late AnimationController _controller;
  String? _currentToken;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    );

    _tokenStream = _generateTokenStream();
    _subscription = _tokenStream.listen(
      (token) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            if (token.startsWith('ERROR:')) {
              _errorMessage = token;
              _currentToken = null;
              _controller.stop();
            } else {
              _errorMessage = null;
              _currentToken = token;
              _controller.reverse(from: 1.0); // Reset animation to 15s
            }
          });
        }
      },
      onError: (err) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'ERROR:${err.toString()}';
            _currentToken = null;
            _controller.stop();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
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
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
        ),
      );
    }

    if (_errorMessage != null) {
      final isWifiOff = _errorMessage!.contains('wifi') || _errorMessage!.contains('conn');
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isWifiOff ? Icons.wifi_off : Icons.cloud_off, 
              color: Colors.orangeAccent, 
              size: 40
            ),
            const SizedBox(height: 12),
            Text(
              isWifiOff 
                  ? 'Sin conexión.\nReintentando en 15s…' 
                  : 'Servicio temporalmente no disponible.\nReintentando en 15s…',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_currentToken == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final seconds = (_controller.value * 15).ceil();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                // Círculo de progreso animado (detrás del contenedor blanco del QR)
                SizedBox(
                  width: 290,
                  height: 290,
                  child: CircularProgressIndicator(
                    value: _controller.value,
                    strokeWidth: 6,
                    color: const Color(0xFF00E5FF),
                    backgroundColor: const Color(0xFF00E5FF).withOpacity(0.1),
                  ),
                ),
                // Contenedor blanco con el código QR
                Container(
                  width: 210,
                  height: 210,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withOpacity(0.15),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: _currentToken!,
                    version: QrVersions.auto,
                    size: 180.0,
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
              ],
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.access_time_outlined, color: Color(0xFF00E5FF), size: 18),
                const SizedBox(width: 8),
                Text(
                  'Expira en $seconds s',
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
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

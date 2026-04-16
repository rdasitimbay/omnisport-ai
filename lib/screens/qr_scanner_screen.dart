import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:app/utils/scanner_logic.dart';
import 'package:app/models/athlete.dart'; // Importante: importar el modelo

enum ScanState { scanningAthlete, loadingAthlete, success, waitingGuardian, scanningGuardian, invalid }

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({Key? key}) : super(key: key);

  @override
  _QrScannerScreenState createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal, // Cambiado para evitar bloqueo en Android
  );
  
  // Caché de simulacion offline (TKT-004)
  final Map<String, dynamic> _offlineLogsMap = {};

  ScanState _currentState = ScanState.scanningAthlete;
  
  // Datos temporales tras escaneo
  String? _scannedUid;
  Map<String, dynamic>? _athleteData;
  String _message = 'Escanea el pase del Atleta';
  bool _isProcessing = false;
  DateTime? _lastScanTime; // Para Debounce manual

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    // Filtro Debounce (2 segundos) para no bloquear la lectura del mismo código
    if (_lastScanTime != null && DateTime.now().difference(_lastScanTime!).inSeconds < 2) {
      return;
    }
    _lastScanTime = DateTime.now();
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawValue = barcodes.first.rawValue;
    if (rawValue != null) {
      _processQR(rawValue);
    }
  }

  // Método simulable para las pruebas UI
  @visibleForTesting
  Future<void> simularDeteccion(String jwtToken) async {
    await _processQR(jwtToken);
  }

  Future<void> _processQR(String jwtToken) async {
    setState(() { _isProcessing = true; });

    final validacion = ScannerLogic.validar(jwtToken);

    if (validacion.status == ScanStatus.ilegible) {
      _setInvalid("Código QR Ilegible o Falso");
      return;
    } else if (validacion.status == ScanStatus.expirado) {
      _setInvalid("QR Expirado o Inválido");
      return;
    }

    final String uid = validacion.uid!;

    if (_currentState == ScanState.scanningAthlete) {
      if (mounted) {
        setState(() {
          _scannedUid = uid;
          _currentState = ScanState.loadingAthlete;
        });
      }

      await Future.delayed(const Duration(milliseconds: 600)); // Efecto dramático de red para ver el Skeleton

      try {
        final doc = await FirebaseFirestore.instance.collection('athletes').doc(uid).get();
        if (!doc.exists) {
          _setInvalid("Usuario no encontrado en base de datos");
          return;
        }

        final data = doc.data()!;
        final bool isMinor = _checkIfMinor(data);
        // Aunque tenemos data aquí, UI usará un StreamBuilder para pintar el modelo Athlete
        
        if (mounted) {
          setState(() {
            _athleteData = data;
          });
        }

        if (isMinor) {
          if (mounted) {
            setState(() {
              _currentState = ScanState.waitingGuardian;
              _message = 'Atleta Menor de Edad.\nEscanea Pase del Tutor.';
              _isProcessing = false; // Permitir escanear 2do código
            });
          }
        } else {
          _logAccess(uid, "athlete_solo");
          _simulateOpalAINotification(uid, data['fullName'] ?? 'Atleta'); // Opal AI Simulated Local Push
          _setSuccess("Ingreso Apto");
        }
      } catch (e) {
        _setInvalid("Código QR Ilegible o Falso");
      }
    } else if (_currentState == ScanState.waitingGuardian) {
      // Asumimos que el 2do QR es del tutor autorizando.
      _logAccess(_scannedUid!, "athlete_with_guardian_$uid");
      _setSuccess("Match Completado\nIngreso Apto");
    }
  }

  bool _checkIfMinor(Map<String, dynamic> data) {
    if (data.containsKey('isMinor')) {
      return data['isMinor'] == true;
    }
    if (data.containsKey('fecha_nacimiento') && data['fecha_nacimiento'] != null) {
      final String dob = data['fecha_nacimiento'];
      try {
        final date = DateTime.parse(dob);
        final age = DateTime.now().year - date.year;
        return age < 18;
      } catch (_) {}
    }
    // Retornamos false por defecto. Puedes editar el doc en Firebase con 'isMinor: true' para probar.
    return false;
  }

  void _logAccess(String uid, String method) {
    final timestamp = DateTime.now().toIso8601String();
    _offlineLogsMap['$uid-$timestamp'] = {
      'uid': uid,
      'timestamp': timestamp,
      'method': method,
      'synced': false // flag offline (preparación para TKT-004)
    };
    print("LOG OFFLINE SAVED: ${_offlineLogsMap['$uid-$timestamp']}");
  }

  void _simulateOpalAINotification(String uid, String name) {
    // Fase 1: Simulación Local (Spark Plan Cost Zero)
    final time = DateTime.now().toString().substring(11, 16);
    debugPrint("------------------------------------------");
    debugPrint("🔔 OPAL AI PUSH NOTIFICATION (Simulada)");
    debugPrint("Mensaje: Opal AI informa: $name ha ingresado al complejo a las $time");
    debugPrint("------------------------------------------");
  }

  void _setSuccess(String msg) {
    setState(() {
      _currentState = ScanState.success;
      _message = msg;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _resetScanner();
    });
  }

  void _setInvalid(String msg) {
    setState(() {
      _currentState = ScanState.invalid;
      _message = msg;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _currentState != ScanState.waitingGuardian) _resetScanner();
    });
  }

  void _resetScanner() {
    setState(() {
      _currentState = ScanState.scanningAthlete;
      _message = 'Escanea el pase del Atleta';
      _isProcessing = false;
      _athleteData = null;
      _scannedUid = null;
    });
    
    // IMPORTANTE PARA ANDROID: Reactiva el controlador para continuar leyendo
    try {
      _scannerController.start();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Zero Trust Scanner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // Mobile Scanner Fullscreen
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),
          
          // Overlay Oscurecido para enfoque
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4)
            ),
          ),
          
          // Viewport del Scanner
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _getNeonColor(),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(color: _getNeonColor().withOpacity(0.3), blurRadius: 20, spreadRadius: 2)
                ]
              ),
            ),
          ),
          
          // Texto Guía Superior
          if (_currentState == ScanState.scanningAthlete || _currentState == ScanState.waitingGuardian)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.2,
              left: 20,
              right: 20,
              child: Text(
                _message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _getNeonColor(),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  shadows: [Shadow(color: _getNeonColor(), blurRadius: 10)],
                ),
              ),
            ),

          // Modal Diamond Glass Ofuscado Bottom
          if (_currentState != ScanState.scanningAthlete)
             Positioned(
               bottom: 80,
               left: 24,
               right: 24,
               child: _buildDiamondModal(),
             )
        ],
      ),
    );
  }

  Color _getNeonColor() {
    switch (_currentState) {
      case ScanState.scanningAthlete:
      case ScanState.scanningGuardian:
        return const Color(0xFF00E5FF); // Cyan
      case ScanState.loadingAthlete:
        return Colors.white54; // Placeholder
      case ScanState.success:
        return Colors.greenAccent; // Success Verde Neon
      case ScanState.waitingGuardian:
        return Colors.orangeAccent; // Alerta naranja Match QR
      case ScanState.invalid:
        return Colors.redAccent; // Error
    }
  }

  Widget _buildDiamondModal() {
    final neonColor = _getNeonColor();

    return GestureDetector(
      onTap: () {
        _resetScanner(); // Cierra el modal e invoca resumeCamera() internamente
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: neonColor.withOpacity(0.6), width: 1.5),
              boxShadow: [
                 BoxShadow(color: neonColor.withOpacity(0.15), blurRadius: 20, spreadRadius: 0)
              ]
            ),
            child: _currentState == ScanState.loadingAthlete 
                ? _buildSkeletonLoader(neonColor)
                : _buildModalContent(neonColor),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonLoader(Color neonColor) {
    return Shimmer.fromColors(
      baseColor: Colors.white30,
      highlightColor: neonColor.withOpacity(0.6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80, height: 80,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
          const SizedBox(height: 16),
          Container(width: 150, height: 24, color: Colors.white),
          const SizedBox(height: 8),
          Container(width: 100, height: 16, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildModalContent(Color baseNeonColor) {
    if (_scannedUid == null || _currentState == ScanState.invalid) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: baseNeonColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: baseNeonColor.withOpacity(0.5))
            ),
            child: Text(
              _message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: baseNeonColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5
              ),
            ),
          ),
        ],
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('athletes').doc(_scannedUid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _buildSkeletonLoader(baseNeonColor);
        }

        final model = Athlete.fromMap(_scannedUid!, snapshot.data!.data() as Map<String, dynamic>);
        
        // Lógica de Semáforo Diamond Glass (basado en status)
        Color finalNeonColor = baseNeonColor;
        String displayStatus = "INGRESO APTO";
        String upperStatus = model.status.toUpperCase();
        
        if (upperStatus.contains('ACCESO AUTORIZADO') || upperStatus.contains('AL DÍA')) {
          finalNeonColor = const Color(0xFF50C878); // Verde Esmeralda
          displayStatus = "ACCESO AUTORIZADO";
        } else if (upperStatus.contains('PAGO PENDIENTE')) {
          finalNeonColor = const Color(0xFFFFBF00); // Naranja Ámbar
          displayStatus = "PAGO PENDIENTE";
        } else if (upperStatus.contains('VENCIDA') || upperStatus.contains('DENEGADO')) {
          finalNeonColor = const Color(0xFFDC143C); // Rojo Carmesí
          displayStatus = "ACCESO DENEGADO";
        } else if (upperStatus.contains('INACTIVO')) {
          finalNeonColor = const Color(0xFFB0BEC5); // Gris Frost
          displayStatus = "ATLETA INACTIVO";
        } else {
          displayStatus = model.status.toUpperCase();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: finalNeonColor, width: 2),
                boxShadow: [
                  BoxShadow(color: finalNeonColor.withOpacity(0.3), blurRadius: 15)
                ]
              ),
              child: CircleAvatar(
                backgroundColor: Colors.white24,
                backgroundImage: model.photoUrl.isNotEmpty ? NetworkImage(model.photoUrl) : null,
                child: model.photoUrl.isEmpty ? const Icon(CupertinoIcons.person_fill, color: Colors.white, size: 40) : null,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              model.fullName.split(' ').first.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 2.0),
            ),
            if (model.teamOrCategory.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  model.teamOrCategory.toUpperCase(),
                  style: TextStyle(color: finalNeonColor.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.2),
                ),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: finalNeonColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: finalNeonColor.withOpacity(0.5))
              ),
              child: Text(
                _currentState == ScanState.success ? displayStatus : _message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: finalNeonColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5
                ),
              ),
            ),
            if (_currentState == ScanState.waitingGuardian)
              const Padding(
                padding: EdgeInsets.only(top: 16.0),
                child: CircularProgressIndicator(color: Colors.orangeAccent),
                )
            ],
          );
      },
    );
  }
}

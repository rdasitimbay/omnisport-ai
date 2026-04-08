import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app/utils/scanner_logic.dart';

enum ScanState { scanningAthlete, success, waitingGuardian, scanningGuardian, invalid }

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({Key? key}) : super(key: key);

  @override
  _QrScannerScreenState createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  
  // Caché de simulacion offline (TKT-004)
  final Map<String, dynamic> _offlineLogsMap = {};

  ScanState _currentState = ScanState.scanningAthlete;
  
  // Datos temporales tras escaneo
  String? _scannedUid;
  Map<String, dynamic>? _athleteData;
  String _message = 'Escanea el pase del Atleta';
  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
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
      try {
        final doc = await FirebaseFirestore.instance.collection('athletes').doc(uid).get();
        if (!doc.exists) {
          _setInvalid("Usuario no encontrado en base de datos");
          return;
        }

        final data = doc.data()!;
        final bool isMinor = _checkIfMinor(data);
        
        setState(() {
          _athleteData = data;
          _scannedUid = uid;
        });

        if (isMinor) {
          setState(() {
            _currentState = ScanState.waitingGuardian;
            _message = 'Atleta Menor de Edad.\nEscanea Pase del Tutor.';
            _isProcessing = false; // Permitir escanear 2do código
          });
        } else {
          _logAccess(uid, "athlete_solo");
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
    final String photoBase64 = _athleteData?['photoBase64'] ?? '';
    final String nombreCompleto = _athleteData?['nombre_completo'] ?? _athleteData?['full_name'] ?? 'Desconocido';
    // Ofuscado: Solo mostramos nombre de pila (o los primeros dos si es compuesto, pero con split().first aseguramos no apellidos)
    final String nombrePila = nombreCompleto.split(' ').first;

    return ClipRRect(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_athleteData != null)
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: neonColor, width: 2),
                    boxShadow: [
                      BoxShadow(color: neonColor.withOpacity(0.3), blurRadius: 15)
                    ]
                  ),
                  child: CircleAvatar(
                    backgroundColor: Colors.white24,
                    backgroundImage: photoBase64.isNotEmpty ? MemoryImage(base64Decode(photoBase64)) : null,
                    child: photoBase64.isEmpty ? const Icon(CupertinoIcons.person_fill, color: Colors.white, size: 40) : null,
                  ),
                ),
              const SizedBox(height: 16),
              if (_athleteData != null)
                Text(
                  nombrePila.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 2.0),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: neonColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: neonColor.withOpacity(0.5))
                ),
                child: Text(
                  _currentState == ScanState.success ? "INGRESO APTO" : _message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: neonColor,
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
          ),
        ),
      ),
    );
  }
}

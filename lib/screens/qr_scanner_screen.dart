import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shimmer/shimmer.dart';
import 'package:app/models/athlete.dart';
import '../services/offline_sync_service.dart';
import 'referee_verify_screen.dart';

enum ScanState {
  scanningAthlete,
  loadingAthlete,
  success,
  waitingGuardian,
  scanningGuardian,
  invalid,
}

class QrScannerScreen extends StatefulWidget {
  final FirebaseFirestore? firestore;
  final bool isTestMode;
  const QrScannerScreen({Key? key, this.firestore, this.isTestMode = false})
    : super(key: key);

  @override
  _QrScannerScreenState createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed:
        DetectionSpeed.normal, // Cambiado para evitar bloqueo en Android
  );

  // El caché de simulación offline fue reemplazado por OfflineSyncService (TKT-004)

  ScanState _currentState = ScanState.scanningAthlete;

  // Toggle Ingreso/Salida — seleccionable por el Staff antes de escanear.
  bool _isEntry = true;
  String get _actionLabel => _isEntry ? 'ingreso' : 'salida';

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
    if (_lastScanTime != null &&
        DateTime.now().difference(_lastScanTime!).inSeconds < 2) {
      return;
    }
    _lastScanTime = DateTime.now();

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawValue = barcodes.first.rawValue;
    if (rawValue != null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Detectado: ${rawValue.trim()}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.blueAccent,
          duration: const Duration(seconds: 4),
        ),
      );
      _processQR(rawValue.trim());
    }
  }

  // Método simulable para las pruebas UI
  @visibleForTesting
  Future<void> simularDeteccion(String jwtToken) async {
    await _processQR(jwtToken);
  }

  bool _isSmartIdToken(String raw) {
    final parts = raw.split('.');
    if (parts.length != 3) return false;
    try {
      final padded = base64Url.normalize(parts[0]);
      final header = json.decode(utf8.decode(base64Url.decode(padded))) as Map;
      return header['typ'] == 'SMART_ID';
    } catch (_) {
      return false;
    }
  }

  Future<void> _processQR(String jwtToken) async {
    // Route Smart ID tokens (JWT dot-separated) to referee verification flow.
    if (_isSmartIdToken(jwtToken)) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RefereeVerifyScreen(token: jwtToken)),
      );
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    setState(() {
      _isProcessing = true;
      _currentState = ScanState.loadingAthlete;
    });

    // 1. Obtener Geofencing (Ubicación)
    Map<String, dynamic>? locationData;
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        locationData = {
          'latitude': position.latitude,
          'longitude': position.longitude,
        };
      }
    } catch (e) {
      debugPrint("Geofencing Error: $e");
    }

    // 2. Validar Token en Backend (Sprint 4)
    String resolvedUid = '';
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('validateAttendanceToken')
          .call({
        'token': jwtToken,
        'action': _actionLabel,
        'location': locationData,
      });

      if (result.data['success'] == true) {
        final parts = jwtToken.split(':');
        resolvedUid = parts.length >= 3 ? parts[0] : jwtToken;
      }
    } catch (e) {
      if (e is FirebaseFunctionsException) {
        _setInvalid(e.message ?? "Token Inválido o Falso");
      } else {
        _setInvalid("Error de Red al Validar");
      }
      return;
    }

    if (_currentState == ScanState.loadingAthlete || _currentState == ScanState.scanningAthlete) {
      if (mounted) {
        setState(() {
          _scannedUid = resolvedUid;
          _currentState = ScanState.loadingAthlete;
        });
      }

      await Future.delayed(
        const Duration(milliseconds: 600),
      ); // Efecto dramático de red para ver el Skeleton

      try {
        final doc = await (widget.firestore ?? FirebaseFirestore.instance)
            .collection('athletes')
            .doc(resolvedUid)
            .get();
        if (!doc.exists) {
          _setInvalid("Usuario ($resolvedUid) no encontrado en BD");
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
          // La Cloud Function ya registró el log y envió el Push (Sprint 4)
          // Solo registramos el log offline como backup si se desea, o delegamos todo a la nube.
          _logAccess(resolvedUid, "athlete_solo");
          _setSuccess(_isEntry ? "Ingreso Apto" : "Salida Registrada");
        }
      } catch (e) {
        print("ERROR EN FIRESTORE: $e");
        _setInvalid("Data Error: $e");
      }
    } else if (_currentState == ScanState.waitingGuardian) {
      // Asumimos que el 2do QR es del tutor autorizando.
      _logAccess(_scannedUid!, "athlete_with_guardian_$resolvedUid");
      _setSuccess("Match Completado\nIngreso Apto");
    }
  }

  bool _checkIfMinor(Map<String, dynamic> data) {
    if (data.containsKey('isMinor')) {
      return data['isMinor'] == true;
    }
    if (data.containsKey('fecha_nacimiento') &&
        data['fecha_nacimiento'] != null) {
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
    final logData = {
      'sync_type': 'access_log',
      'uid': uid,
      'timestamp': timestamp,
      'method': method,
    };

    // Fuego y olvido: guardar localmente e intentar sincronizar
    OfflineSyncService.saveModelLocally(logData).then((_) {
      OfflineSyncService.syncLogs(firestore: widget.firestore);
    });
  }

  void _simulateOpalAINotification(String uid, String name) {
    // Fase 1: Simulación Local (Spark Plan Cost Zero)
    final time = DateTime.now().toString().substring(11, 16);
    debugPrint("------------------------------------------");
    debugPrint("🔔 OPAL AI PUSH NOTIFICATION (Simulada)");
    debugPrint(
      "Mensaje: Opal AI informa: $name ha ingresado al complejo a las $time",
    );
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
      if (mounted && _currentState != ScanState.waitingGuardian)
        _resetScanner();
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
    if (!widget.isTestMode) {
      try {
        _scannerController.start();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Zero Trust Scanner',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // ── Toggle Ingreso / Salida ──────────────────────────────
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _buildActionToggle(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Mobile Scanner Fullscreen
          if (!widget.isTestMode)
            MobileScanner(controller: _scannerController, onDetect: _onDetect),

          // Overlay Oscurecido para enfoque
          Container(
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.4)),
          ),

          // Viewport del Scanner
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: _getNeonColor(), width: 3),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: _getNeonColor().withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),

          // Texto Guía Superior
          if (_currentState == ScanState.scanningAthlete ||
              _currentState == ScanState.waitingGuardian)
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
            ),
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

  /// Toggle pill para seleccionar Ingreso / Salida antes de escanear.
  Widget _buildActionToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleOption('Ingreso', Icons.login, true),
          _toggleOption('Salida', Icons.logout, false),
        ],
      ),
    );
  }

  Widget _toggleOption(String label, IconData icon, bool isEntry) {
    final selected = _isEntry == isEntry;
    final color = isEntry
        ? const Color(0xFF00E5FF)  // Cyan para ingreso
        : const Color(0xFFFFAB40); // Naranja para salida
    return GestureDetector(
      onTap: () => setState(() => _isEntry = isEntry),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? color : Colors.white38),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : Colors.white38,
                fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
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
                BoxShadow(
                  color: neonColor.withOpacity(0.15),
                  blurRadius: 20,
                  spreadRadius: 0,
                ),
              ],
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
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
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
              border: Border.all(color: baseNeonColor.withOpacity(0.5)),
            ),
            child: Text(
              _message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: baseNeonColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: (widget.firestore ?? FirebaseFirestore.instance)
          .collection('athletes')
          .doc(_scannedUid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          print("ERROR EN STREAM: ${snapshot.error}");
          return _buildSkeletonLoader(baseNeonColor);
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _buildSkeletonLoader(baseNeonColor);
        }

        final model = Athlete.fromMap(
          _scannedUid!,
          snapshot.data!.data() as Map<String, dynamic>,
        );

        // Lógica de Semáforo Diamond Glass (basado en status)
        Color finalNeonColor = baseNeonColor;
        String displayStatus = "INGRESO APTO";

        // Removemos acentos comunes para la sanitización y evitamos fallos de string
        String lowerStatus = model.status
            .trim()
            .toLowerCase()
            .replaceAll('á', 'a')
            .replaceAll('é', 'e')
            .replaceAll('í', 'i')
            .replaceAll('ó', 'o')
            .replaceAll('ú', 'u');

        if (lowerStatus.contains('acceso autorizado') ||
            lowerStatus.contains('al dia')) {
          finalNeonColor = const Color(0xFF50C878); // Verde Esmeralda
          displayStatus = "ACCESO AUTORIZADO / AL DÍA";
        } else if (lowerStatus.contains('pago pendiente')) {
          finalNeonColor = const Color(0xFFFFBF00); // Naranja Ámbar
          displayStatus = "PAGO PENDIENTE";
        } else if (lowerStatus.contains('vencida') ||
            lowerStatus.contains('vencido') ||
            lowerStatus.contains('denegado')) {
          finalNeonColor = const Color(0xFFDC143C); // Rojo Carmesí
          displayStatus = "ACCESO DENEGADO";
        } else if (lowerStatus.contains('inactivo')) {
          finalNeonColor = const Color(0xFFB0BEC5); // Gris Frost
          displayStatus = "ATLETA INACTIVO";
        } else {
          displayStatus = model.status.trim().toUpperCase();
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
                  BoxShadow(
                    color: finalNeonColor.withOpacity(0.3),
                    blurRadius: 15,
                  ),
                ],
              ),
              child: CircleAvatar(
                backgroundColor: Colors.white24,
                backgroundImage: model.photoUrl.isNotEmpty
                    ? NetworkImage(model.photoUrl)
                    : null,
                child: model.photoUrl.isEmpty
                    ? const Icon(
                        CupertinoIcons.person_fill,
                        color: Colors.white,
                        size: 40,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              model.fullName.split(' ').first.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
              ),
            ),
            if (model.teamOrCategory.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  model.teamOrCategory.toUpperCase(),
                  style: TextStyle(
                    color: finalNeonColor.withOpacity(0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: finalNeonColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: finalNeonColor.withOpacity(0.5)),
              ),
              child: Text(
                _currentState == ScanState.success ? displayStatus : _message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: finalNeonColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            if (_currentState == ScanState.waitingGuardian)
              const Padding(
                padding: EdgeInsets.only(top: 16.0),
                child: CircularProgressIndicator(color: Colors.orangeAccent),
              ),
          ],
        );
      },
    );
  }
}

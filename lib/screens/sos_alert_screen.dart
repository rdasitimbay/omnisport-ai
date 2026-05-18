import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';

/// Tipos de lesión disponibles para el triaje S.O.S.
enum InjuryType {
  contusion('contusion', 'Contusión / Golpe', Icons.sports_mma, Color(0xFF4CAF50)),
  esguince('esguince', 'Esguince / Torcedura', Icons.accessibility_new, Color(0xFFFFAB40)),
  fracturaSospecha('fractura_sospecha', 'Sospecha Fractura', Icons.broken_image, Color(0xFFFF5252)),
  golpeCabeza('golpe_cabeza', 'Golpe en Cabeza', Icons.psychology_alt, Color(0xFFFF1744)),
  dificultadRespiratoria('dificultad_respiratoria', 'Dificultad Respiratoria', Icons.air, Color(0xFFFF1744)),
  heridaAbierta('herida_abierta', 'Herida Abierta', Icons.healing, Color(0xFFFFAB40)),
  desmayo('desmayo', 'Desmayo / Síncope', Icons.airline_seat_flat, Color(0xFFFFAB40)),
  otro('otro', 'Otro / No Clasificado', Icons.help_outline, Color(0xFF78909C));

  final String key;
  final String label;
  final IconData icon;
  final Color color;
  const InjuryType(this.key, this.label, this.icon, this.color);
}

/// Pantalla S.O.S — Botón Rojo de Emergencia Médica.
///
/// Flujo:
/// 1. El staff/atleta presiona el botón rojo (long-press para evitar accidentales).
/// 2. Selecciona el tipo de lesión en un grid visual.
/// 3. Opcionalmente agrega una descripción.
/// 4. El sistema captura GPS y envía la alerta al backend.
/// 5. El backend responde con el protocolo de triaje y notifica al padre.
class SosAlertScreen extends StatefulWidget {
  final String athleteUid;
  final String athleteName;

  const SosAlertScreen({
    super.key,
    required this.athleteUid,
    required this.athleteName,
  });

  @override
  State<SosAlertScreen> createState() => _SosAlertScreenState();
}

class _SosAlertScreenState extends State<SosAlertScreen>
    with SingleTickerProviderStateMixin {
  // Estado
  bool _sosActivated = false;
  InjuryType? _selectedInjury;
  bool _isSending = false;
  Map<String, dynamic>? _protocolResponse;
  final _descriptionController = TextEditingController();

  // Animación del botón rojo
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _triggerSos() async {
    if (_selectedInjury == null || _isSending) return;

    setState(() => _isSending = true);
    HapticFeedback.heavyImpact();

    // Capturar GPS
    double? lat, lng;
    String locationName = 'Ubicación no disponible';
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 5));
        lat = pos.latitude;
        lng = pos.longitude;
        locationName = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      }
    } catch (_) {}

    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('triggerSosAlert')
          .call({
        'athleteUid': widget.athleteUid,
        'injuryType': _selectedInjury!.key,
        'description': _descriptionController.text.trim(),
        'latitude': lat,
        'longitude': lng,
        'locationName': locationName,
      });

      final data = result.data as Map<String, dynamic>;
      setState(() {
        _protocolResponse = data['protocol'] as Map<String, dynamic>?;
        _isSending = false;
      });

      HapticFeedback.mediumImpact();
    } catch (e) {
      setState(() => _isSending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e is FirebaseFunctionsException ? e.message : e}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'S.O.S MÉDICO',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
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
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A0000), Color(0xFF0A192F)],
          ),
        ),
        child: SafeArea(
          child: _protocolResponse != null
              ? _buildTriageProtocol()
              : _sosActivated
                  ? _buildInjurySelector()
                  : _buildRedButton(),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PASO 1: Botón Rojo pulsante — Long Press para activar
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildRedButton() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nombre del atleta
          Text(
            widget.athleteName.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 14,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 40),

          // Botón Rojo con animación de pulso
          GestureDetector(
            onLongPress: () {
              HapticFeedback.heavyImpact();
              setState(() => _sosActivated = true);
            },
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFFFF1744), Color(0xFFB71C1C)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF1744).withValues(alpha: 0.4),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                        BoxShadow(
                          color: const Color(0xFFFF1744).withValues(alpha: 0.2),
                          blurRadius: 60,
                          spreadRadius: 15,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.emergency, color: Colors.white, size: 48),
                          SizedBox(height: 8),
                          Text(
                            'S.O.S',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 32),

          // Instrucción
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app, color: Colors.white38, size: 18),
                SizedBox(width: 8),
                Text(
                  'Mantener presionado para activar',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PASO 2: Selector de tipo de lesión
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildInjurySelector() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            '¿Qué tipo de lesión?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Selecciona para recibir el protocolo de triaje adecuado',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),

          // Grid de tipos de lesión
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: InjuryType.values.map((injury) {
              final selected = _selectedInjury == injury;
              return GestureDetector(
                onTap: () => setState(() => _selectedInjury = injury),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: selected
                        ? injury.color.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? injury.color
                          : Colors.white.withValues(alpha: 0.1),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(injury.icon, color: injury.color, size: 24),
                      const SizedBox(height: 8),
                      Text(
                        injury.label,
                        style: TextStyle(
                          color: selected ? injury.color : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Campo de descripción opcional
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: TextField(
                controller: _descriptionController,
                maxLines: 2,
                maxLength: 200,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Descripción breve (opcional)',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  counterStyle: const TextStyle(color: Colors.white24),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Botón enviar
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _selectedInjury != null && !_isSending
                  ? _triggerSos
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF1744),
                disabledBackgroundColor: Colors.grey.shade800,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 8,
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.emergency_share, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'ENVIAR ALERTA S.O.S',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 16),
          // Cancelar
          Center(
            child: TextButton(
              onPressed: () => setState(() {
                _sosActivated = false;
                _selectedInjury = null;
              }),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white38),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PASO 3: Protocolo de triaje recibido del backend
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildTriageProtocol() {
    final protocol = _protocolResponse!;
    final severity = protocol['severity'] as String;
    final title = protocol['title'] as String;
    final steps = List<String>.from(protocol['steps'] as List);
    final callEmergency = protocol['callEmergency'] as bool;

    final severityColor = severity == 'red'
        ? const Color(0xFFFF1744)
        : severity == 'yellow'
            ? const Color(0xFFFFAB40)
            : const Color(0xFF4CAF50);

    final severityLabel = severity == 'red'
        ? '🔴 EMERGENCIA'
        : severity == 'yellow'
            ? '🟡 PRECAUCIÓN'
            : '🟢 LEVE';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Confirmación de envío
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Alerta enviada · Padre/Tutor notificado',
                    style: TextStyle(
                      color: Color(0xFF4CAF50),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Severidad
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: severityColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              severityLabel,
              style: TextStyle(
                color: severityColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Título del protocolo
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'PROTOCOLO DE PRIMEROS AUXILIOS',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),

          // Pasos del protocolo
          ...steps.asMap().entries.map((entry) {
            final index = entry.key;
            final step = entry.value;
            final isUrgent = step.contains('911') || step.contains('NO ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isUrgent
                          ? severityColor.withValues(alpha: 0.1)
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isUrgent
                            ? severityColor.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: severityColor.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: severityColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            step,
                            style: TextStyle(
                              color: isUrgent ? Colors.white : Colors.white70,
                              fontSize: 14,
                              fontWeight: isUrgent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          // Botón llamar 911
          if (callEmergency) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {
                  // En producción: url_launcher con tel:911
                  HapticFeedback.heavyImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Llamando al ECU-911...'),
                      backgroundColor: Color(0xFFFF1744),
                    ),
                  );
                },
                icon: const Icon(Icons.phone, color: Colors.white),
                label: const Text(
                  'LLAMAR ECU-911',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF1744),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),
          // Volver
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, color: Colors.white38, size: 18),
              label: const Text(
                'Volver al Dashboard',
                style: TextStyle(color: Colors.white38),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

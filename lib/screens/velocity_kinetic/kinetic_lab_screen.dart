import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../services/ai_service.dart';

class KineticLabScreen extends StatefulWidget {
  final String athleteId;
  final String athleteName;
  final String sport;

  const KineticLabScreen({
    super.key,
    required this.athleteId,
    required this.athleteName,
    required this.sport,
  });

  @override
  State<KineticLabScreen> createState() => _KineticLabScreenState();
}

class _KineticLabScreenState extends State<KineticLabScreen> with TickerProviderStateMixin {
  final AIService _aiService = AIService();

  // Biometría interactiva (Métricas base)
  double _velocity = 1.6; // m/s
  double _athleteWeight = 72.0; // kg
  int _heartRate = 124; // BPM
  double _powerOutput = 345.0; // Watts

  // Historial de aceleración (semana actual)
  final List<double> _weeklyAceleracion = [1.2, 1.5, 1.4, 1.8, 1.6, 2.1, 1.9];

  // Controladores de animación
  late AnimationController _pulseController;
  late AnimationController _waveController;

  // Estado del análisis de IA
  bool _isLoadingAI = false;
  Map<String, dynamic>? _aiAnalysisResult;

  @override
  void initState() {
    super.initState();

    // Animación de pulso cardíaco
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    // Animación de onda de fondo
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  // Fórmula física: Ec = 0.5 * m * v^2
  double get _kineticEnergy => 0.5 * _athleteWeight * math.pow(_velocity, 2);

  Future<void> _runAIBiometricAnalysis() async {
    setState(() {
      _isLoadingAI = true;
      _aiAnalysisResult = null;
    });

    try {
      final biometrics = {
        'heartRate': _heartRate,
        'velocity': double.parse(_velocity.toStringAsFixed(2)),
        'power': _powerOutput.toInt(),
        'kineticEnergy': _kineticEnergy.toInt(),
      };

      final result = await _aiService.analyzeBiometrics(
        widget.athleteName,
        widget.sport,
        biometrics,
      );

      setState(() {
        _aiAnalysisResult = result;
        _isLoadingAI = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingAI = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fondo gris claro premium (Canvas Base #f8f9fa)
    const Color canvasBase = Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: canvasBase,
      extendBodyBehindAppBar: true,
      appBar: _buildTopAppBar(context),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 110),
              
              // Encabezado Editorial Asimétrico
              _buildEditorialHeader(),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    
                    // Bento Grid: Tarjetas de Biometría
                    _buildBiometricGrid(),
                    
                    const SizedBox(height: 24),
                    
                    // Gráfico de Curva de Rendimiento (Bleeding Edge)
                    _buildPerformanceCurveCard(),
                    
                    const SizedBox(height: 24),
                    
                    // Simulador Dinámico Interactivo
                    _buildKineticSimulator(),
                    
                    const SizedBox(height: 24),
                    
                    // Gemini AI Biometric Review
                    _buildAIBiometricReviewCard(),
                    
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIDGET BUILDERS
  // ═══════════════════════════════════════════════════════════════════════════

  PreferredSizeWidget _buildTopAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AppBar(
            backgroundColor: Colors.white.withValues(alpha: 0.85),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.chevron_back, color: Color(0xFF191C1D), size: 24),
              onPressed: () => Navigator.pop(context),
            ),
            title: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.bolt_fill, color: Color(0xFF0056B3), size: 18),
                  SizedBox(width: 6),
                  Text(
                    'OMNISPORT-AI',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      fontSize: 18,
                      color: Color(0xFF0056B3),
                    ),
                  ),
                ],
              ),
            ),
            centerTitle: true,
          ),
        ),
      ),
    );
  }

  Widget _buildEditorialHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RENDIMIENTO PRO',
            style: TextStyle(
              fontFamily: 'Inter',
              color: Color(0xFF0056B3),
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Kinetic Lab',
            style: TextStyle(
              fontFamily: 'Manrope',
              color: Color(0xFF191C1D),
              fontWeight: FontWeight.w900,
              fontSize: 44,
              letterSpacing: -1.5,
              height: 0.95,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 4,
            width: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF0056B3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricGrid() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Frecuencia Cardíaca (Grande, con animación de pulso)
        Expanded(
          flex: 4,
          child: _kineticCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'CARDIO',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.black38,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 1.0,
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: 1.0 + (_pulseController.value * 0.15),
                          child: const Icon(
                            CupertinoIcons.heart_fill,
                            color: Color(0xFFFF1744),
                            size: 18,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$_heartRate',
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        color: Color(0xFF191C1D),
                        fontWeight: FontWeight.w900,
                        fontSize: 36,
                        letterSpacing: -1.0,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'BPM',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.black45,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Zona de esfuerzo estable',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.black54,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _softPillButton(
                      label: 'Subir ritmo',
                      onPressed: () {
                        setState(() {
                          _heartRate = _heartRate < 180 ? _heartRate + 15 : 180;
                          _powerOutput = _powerOutput + 25;
                        });
                      },
                    ),
                    _softPillButton(
                      label: 'Calmar',
                      onPressed: () {
                        setState(() {
                          _heartRate = _heartRate > 65 ? _heartRate - 15 : 65;
                          _powerOutput = _powerOutput > 100 ? _powerOutput - 20 : 100;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Potencia & Aceleración (Verticales apilados)
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _kineticCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'POTENCIA',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.black38,
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${_powerOutput.toInt()}',
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            color: Color(0xFF191C1D),
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Text(
                          'W',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.black45,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _kineticCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ACELERACIÓN',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.black38,
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _velocity.toStringAsFixed(1),
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            color: Color(0xFF191C1D),
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Text(
                          'm/s',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.black45,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceCurveCard() {
    return _kineticCard(
      padding: EdgeInsets.zero, // Permitir desbordamiento (Metric Overlap)
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TENDENCIA DE ACELERACIÓN',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.black38,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 1.0,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Esfuerzo Cinemático Semanal',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Color(0xFF191C1D),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Icon(
                  CupertinoIcons.graph_square_fill,
                  color: Color(0xFF0056B3),
                  size: 22,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Gráfico dinámico customizado (CustomPainter)
          SizedBox(
            height: 120,
            width: double.infinity,
            child: CustomPaint(
              painter: BiometricChartPainter(_weeklyAceleracion),
            ),
          ),
          // Etiquetas de días de la semana
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFEDEEEF),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('LUN', style: TextStyle(fontFamily: 'Inter', fontSize: 9, color: Colors.black38, fontWeight: FontWeight.bold)),
                Text('MAR', style: TextStyle(fontFamily: 'Inter', fontSize: 9, color: Colors.black38, fontWeight: FontWeight.bold)),
                Text('MIÉ', style: TextStyle(fontFamily: 'Inter', fontSize: 9, color: Colors.black38, fontWeight: FontWeight.bold)),
                Text('JUE', style: TextStyle(fontFamily: 'Inter', fontSize: 9, color: Colors.black38, fontWeight: FontWeight.bold)),
                Text('VIE', style: TextStyle(fontFamily: 'Inter', fontSize: 9, color: Colors.black38, fontWeight: FontWeight.bold)),
                Text('SÁB', style: TextStyle(fontFamily: 'Inter', fontSize: 9, color: Colors.black38, fontWeight: FontWeight.bold)),
                Text('DOM', style: TextStyle(fontFamily: 'Inter', fontSize: 9, color: Colors.black38, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKineticSimulator() {
    return _kineticCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SIMULADOR CINÉTICO',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.black38,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 1.0,
                ),
              ),
              Icon(
                CupertinoIcons.gauge,
                color: Color(0xFF0056B3),
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Cálculo de Energía de Ejecución',
            style: TextStyle(
              fontFamily: 'Inter',
              color: Color(0xFF191C1D),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          // Indicador dinámico de Energía Cinética
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEDEEEF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ENERGÍA CINÉTICA',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: Colors.black45,
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Fuerza mecánica estimada',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: Colors.black54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${_kineticEnergy.toInt()}',
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        color: Color(0xFF0056B3),
                        fontWeight: FontWeight.w900,
                        fontSize: 32,
                        letterSpacing: -1.0,
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Text(
                      'J',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Color(0xFF0056B3),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Sliders para ajustar parámetros cinéticos
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Velocidad de Saque / Salto',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${_velocity.toStringAsFixed(2)} m/s', style: const TextStyle(fontFamily: 'Manrope', fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0056B3))),
                ],
              ),
              Slider(
                value: _velocity,
                min: 0.5,
                max: 4.0,
                activeColor: const Color(0xFF0056B3),
                inactiveColor: Colors.black12,
                onChanged: (val) {
                  setState(() {
                    _velocity = val;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Masa / Peso Corporal',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${_athleteWeight.toInt()} kg', style: const TextStyle(fontFamily: 'Manrope', fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0056B3))),
                ],
              ),
              Slider(
                value: _athleteWeight,
                min: 45.0,
                max: 110.0,
                activeColor: const Color(0xFF0056B3),
                inactiveColor: Colors.black12,
                onChanged: (val) {
                  setState(() {
                    _athleteWeight = val;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAIBiometricReviewCard() {
    return _kineticCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'GEMINI PERFORMANCE ENGINE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.black38,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                CupertinoIcons.sparkles,
                color: Color(0xFF0056B3),
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'AI Biometric Review',
            style: TextStyle(
              fontFamily: 'Manrope',
              color: Color(0xFF191C1D),
              fontWeight: FontWeight.w900,
              fontSize: 20,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Evalúa de forma predictiva tus rangos de aceleración vertical, potencia mecánica y gasto metabólico instantáneo mediante IA.',
            style: TextStyle(
              fontFamily: 'Inter',
              color: Colors.black54,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          
          if (_isLoadingAI)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF0056B3)),
                    const SizedBox(height: 16),
                    Text(
                      'Procesando telemetría con Gemini...',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: Colors.black.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_aiAnalysisResult != null) ...[
            _buildAIAnalysisDisplay(),
            const SizedBox(height: 16),
          ],
          
          if (!_isLoadingAI)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9999),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0056B3), Color(0xFF003F87)],
                  ),
                ),
                child: ElevatedButton(
                  onPressed: _runAIBiometricAnalysis,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.sparkles, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'ANALIZAR TELEMETRÍA',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAIAnalysisDisplay() {
    final status = _aiAnalysisResult!['status'] ?? 'Apto';
    final performanceScore = _aiAnalysisResult!['performanceScore'] ?? 85;
    final analysis = _aiAnalysisResult!['analysis'] ?? '';
    final List insights = _aiAnalysisResult!['insights'] ?? [];

    Color statusColor = const Color(0xFF00E676); // Verde
    Color statusBg = const Color(0xFF00E676).withValues(alpha: 0.12);
    
    if (status == 'Precaución' || status == 'Sobrecarga') {
      statusColor = const Color(0xFFFFB300); // Ámbar
      statusBg = const Color(0xFFFFB300).withValues(alpha: 0.12);
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEEEF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Row(
                children: [
                  const Text(
                    'Score: ',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Colors.black45, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '$performanceScore%',
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      color: Color(0xFF0056B3),
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            analysis,
            style: const TextStyle(
              fontFamily: 'Inter',
              color: Color(0xFF191C1D),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (insights.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.black12, height: 1),
            const SizedBox(height: 12),
            ...insights.map((ins) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        CupertinoIcons.checkmark_circle_fill,
                        color: Color(0xFF0056B3),
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          ins.toString(),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.black54,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REUSABLE SHELLS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _kineticCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, // Fondo blanco (Card Base #ffffff)
        borderRadius: BorderRadius.circular(16), // xl = 12-16px rounding
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF001A40).withValues(alpha: 0.04), // Sombra suave ambiental
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _softPillButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(9999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEDEEEF), // Recessed surface container secondary
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            color: Color(0xFF0056B3),
            fontWeight: FontWeight.bold,
            fontSize: 9,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER CHART
// ═══════════════════════════════════════════════════════════════════════════

class BiometricChartPainter extends CustomPainter {
  final List<double> data;
  BiometricChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0xFF0056B3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF0056B3).withValues(alpha: 0.18),
          const Color(0xFF0056B3).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final fillPath = Path();

    final stepX = size.width / (data.length - 1);
    final maxVal = data.reduce(math.max);
    final minVal = data.reduce(math.min);
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    double getX(int index) => index * stepX;
    double getY(double val) {
      final normalized = (val - minVal) / range;
      return size.height - (normalized * size.height * 0.7) - (size.height * 0.15);
    }

    path.moveTo(getX(0), getY(data[0]));
    fillPath.moveTo(getX(0), size.height);
    fillPath.lineTo(getX(0), getY(data[0]));

    for (int i = 1; i < data.length; i++) {
      final x = getX(i);
      final y = getY(data[i]);
      
      final prevX = getX(i - 1);
      final prevY = getY(data[i - 1]);
      final cpX1 = prevX + (x - prevX) / 2;
      final cpY1 = prevY;
      final cpX2 = prevX + (x - prevX) / 2;
      final cpY2 = y;
      
      path.cubicTo(cpX1, cpY1, cpX2, cpY2, x, y);
      fillPath.cubicTo(cpX1, cpY1, cpX2, cpY2, x, y);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Dibujar puntos para picos de datos
    final dotPaint = Paint()
      ..color = const Color(0xFFF8F9FA)
      ..style = PaintingStyle.fill;
    
    final dotBorderPaint = Paint()
      ..color = const Color(0xFF0056B3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (int i = 0; i < data.length; i++) {
      final x = getX(i);
      final y = getY(data[i]);
      canvas.drawCircle(Offset(x, y), 5, dotPaint);
      canvas.drawCircle(Offset(x, y), 5, dotBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

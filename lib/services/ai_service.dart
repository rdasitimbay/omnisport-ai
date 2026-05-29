import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

class AIService {
  static const String _apiKey = 'AIzaSyBO5hF0j__knFR3xgOacQMhe-_C_JWdUhU';
  
  // Endpoint v1beta con modelo estable
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  AIService();

  Future<Map<String, dynamic>> generateTrainingRoutine(String athleteName, String discipline) async {
    // Prompt altamente estructurado para recibir JSON puro
    final prompt = '''Genera una rutina de entrenamiento de 3 ejercicios para un $discipline llamado $athleteName. 
    Responde ÚNICAMENTE con un objeto JSON válido con la siguiente estructura:
    {
      "athlete": "$athleteName",
      "discipline": "$discipline",
      "exercises": [
        {
          "name": "Nombre del ejercicio",
          "reps": "Series x Repeticiones (ej: 3x12)",
          "desc": "Descripción técnica breve",
          "focus": "Potencia|Resistencia|Flexibilidad"
        }
      ]
    }''';
    
    final url = Uri.parse('$_baseUrl?key=$_apiKey');
    
    final bodyRequest = jsonEncode({
      "contents": [
        { "parts": [ { "text": prompt } ] }
      ],
      "generationConfig": {
        "temperature": 0.4,
        "topK": 40,
        "topP": 0.95,
        "response_mime_type": "application/json" // Forzamos JSON si el modelo lo permite
      }
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: bodyRequest,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Guard against unexpected API response structure (empty candidates/parts)
        final candidates = data['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          debugPrint('AIService: no candidates in response. Activando Resiliencia.');
          return _getMockRoutineJson(athleteName, discipline);
        }
        final parts = candidates[0]['content']?['parts'] as List?;
        if (parts == null || parts.isEmpty) {
          debugPrint('AIService: no parts in response. Activando Resiliencia.');
          return _getMockRoutineJson(athleteName, discipline);
        }
        final String text = (parts[0]['text'] as String?) ?? '';
        // Limpiamos posibles caracteres extra de markdown si el modelo los incluyó
        final cleanedJson = text.replaceAll('```json', '').replaceAll('```', '').trim();
        return jsonDecode(cleanedJson);
      } else {
        debugPrint('Error de API Gemini (${response.statusCode}). Activando Resiliencia.');
        return _getMockRoutineJson(athleteName, discipline);
      }
    } catch (e) {
      debugPrint('Excepción en AIService: $e. Activando Resiliencia.');
      return _getMockRoutineJson(athleteName, discipline);
    }
  }

  Map<String, dynamic> _getMockRoutineJson(String name, String discipline) {
    return {
      "athlete": name,
      "discipline": discipline,
      "mode": "resilience",
      "exercises": [
        {
          "name": "Calentamiento Dinámico",
          "reps": "3 series x 15 reps",
          "desc": "Movilidad articular completa y saltos suaves para activar el tren inferior.",
          "focus": "Flexibilidad"
        },
        {
          "name": "Sentadilla Explosiva",
          "reps": "4 series x 10 reps",
          "desc": "Baja controlado y sube con máxima potencia. Imprescindible para $discipline.",
          "focus": "Potencia"
        },
        {
          "name": "Core Stability (Plancha)",
          "reps": "3 series x 45 seg",
          "desc": "Mantener alineación perfecta. Estabilidad vital para el control del cuerpo.",
          "focus": "Resistencia"
        }
      ]
    };
  }

  Future<Map<String, dynamic>> analyzeBiometrics(
    String athleteName,
    String discipline,
    Map<String, dynamic> biometrics,
  ) async {
    final heartRate = biometrics['heartRate'] ?? 72;
    final velocity = biometrics['velocity'] ?? 1.2;
    final power = biometrics['power'] ?? 250;
    final kineticEnergy = biometrics['kineticEnergy'] ?? 360;

    final prompt = '''Analiza las métricas biométricas actuales del atleta $athleteName ($discipline):
    - Frecuencia Cardíaca: $heartRate BPM
    - Velocidad de Ejecución: $velocity m/s
    - Potencia Mecánica: $power Watts
    - Energía Cinética Estimada: $kineticEnergy Joules
    
    Responde ÚNICAMENTE con un objeto JSON válido con la siguiente estructura:
    {
      "status": "Apto|Precaución|Sobrecarga",
      "performanceScore": 92,
      "analysis": "Tu recomendación corta de alto rendimiento basada en su deporte...",
      "insights": [
        "Insight biométrico de velocidad 1...",
        "Insight biométrico de carga muscular 2..."
      ]
    }''';

    final url = Uri.parse('$_baseUrl?key=$_apiKey');
    
    final bodyRequest = jsonEncode({
      "contents": [
        { "parts": [ { "text": prompt } ] }
      ],
      "generationConfig": {
        "temperature": 0.3,
        "topK": 40,
        "topP": 0.95,
        "response_mime_type": "application/json"
      }
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: bodyRequest,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          return _getMockAnalysisJson(athleteName, discipline, biometrics);
        }
        final parts = candidates[0]['content']?['parts'] as List?;
        if (parts == null || parts.isEmpty) {
          return _getMockAnalysisJson(athleteName, discipline, biometrics);
        }
        final String text = (parts[0]['text'] as String?) ?? '';
        final cleanedJson = text.replaceAll('```json', '').replaceAll('```', '').trim();
        return jsonDecode(cleanedJson);
      } else {
        return _getMockAnalysisJson(athleteName, discipline, biometrics);
      }
    } catch (e) {
      return _getMockAnalysisJson(athleteName, discipline, biometrics);
    }
  }

  Map<String, dynamic> _getMockAnalysisJson(
    String athleteName,
    String discipline,
    Map<String, dynamic> biometrics,
  ) {
    final heartRate = biometrics['heartRate'] ?? 72;
    final velocity = biometrics['velocity'] ?? 1.2;
    
    String status = "Apto";
    int score = 85;
    String analysis = "Excelente rendimiento dinámico. Tu aceleración vertical se encuentra dentro de los rangos óptimos para potenciar el saque en suspensión en $discipline.";
    List<String> insights = [
      "Aceleración reactiva dentro del percentil 90 para $discipline.",
      "Frecuencia cardíaca controlada ($heartRate BPM). Ritmo de recuperación óptimo."
    ];

    if (heartRate > 160) {
      status = "Precaución";
      score = 72;
      analysis = "Frecuencia cardíaca elevada registrada ($heartRate BPM). Se recomienda moderar los intervalos de potencia y extender el descanso pasivo para evitar fatiga acumulada.";
      insights = [
        "Cardio-esfuerzo en zona anaeróbica. Reducir repeticiones un 15%.",
        "Eficiencia mecánica estable ($velocity m/s) a pesar de la carga cardíaca."
      ];
    } else if (velocity > 2.5) {
      status = "Apto";
      score = 96;
      analysis = "¡Máximo pico de potencia alcanzado! Tu velocidad y coordinación motora demuestran un estado físico óptimo para transiciones explosivas de $discipline.";
      insights = [
        "Velocidad explosiva excepcional de $velocity m/s registrada.",
        "Estabilidad lumbopélvica excelente durante la desaceleración."
      ];
    }

    return {
      "status": status,
      "performanceScore": score,
      "analysis": analysis,
      "insights": insights,
      "mode": "resilience"
    };
  }

  Future<Map<String, dynamic>> predictMatchOutcome(
    String teamA,
    Map<String, dynamic> statsA,
    String teamB,
    Map<String, dynamic> statsB, {
    String disciplina = 'futbol',
  }) async {
    final prompt = '''Realiza una predicción táctica detallada en español para un partido de ${disciplina.toUpperCase()} entre $teamA y $teamB.
    Estadísticas de $teamA:
    - Puntos: ${statsA['puntos']}
    - Partidos Jugados: ${statsA['partidos_jugados']}
    - Victorias: ${statsA['ganados']}
    - Empates: ${statsA['empatados']}
    - Derrotas: ${statsA['perdidos']}
    - Puntos/Goles a favor: ${statsA['goles_favor']}
    - Puntos/Goles en contra: ${statsA['goles_contra']}

    Estadísticas de $teamB:
    - Puntos: ${statsB['puntos']}
    - Partidos Jugados: ${statsB['partidos_jugados']}
    - Victorias: ${statsB['ganados']}
    - Empates: ${statsB['empatados']}
    - Derrotas: ${statsB['perdidos']}
    - Puntos/Goles a favor: ${statsB['goles_favor']}
    - Puntos/Goles en contra: ${statsB['goles_contra']}

    Responde ÚNICAMENTE con un objeto JSON válido con la siguiente estructura:
    {
      "probabilidad_teamA": 55, // Entero de 0 a 100 de victoria para $teamA
      "probabilidad_empate": 10, // Entero de 0 a 100 de empate (para voleibol debe ser 0 ya que no hay empates)
      "probabilidad_teamB": 35, // Entero de 0 a 100 de victoria para $teamB (La suma de los tres debe ser exactamente 100)
      "analisis_tactico": "Un análisis táctico de alto nivel en markdown adaptado al deporte ${disciplina.toUpperCase()}, abordando debilidades, fortalezas y estrategia...",
      "key_matchup": "El enfrentamiento clave en la cancha/pista...",
      "marcador_estimado": "Marcador estimado acorde a ${disciplina.toUpperCase()} (ej: '3 - 1' para sets de voleibol, '82 - 78' para básquetbol, '2 - 1' para fútbol)"
    }''';

    final url = Uri.parse('$_baseUrl?key=$_apiKey');
    
    final bodyRequest = jsonEncode({
      "contents": [
        { "parts": [ { "text": prompt } ] }
      ],
      "generationConfig": {
        "temperature": 0.4,
        "topK": 40,
        "topP": 0.95,
        "response_mime_type": "application/json"
      }
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: bodyRequest,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          return _getMockMatchPrediction(teamA, statsA, teamB, statsB, disciplina);
        }
        final parts = candidates[0]['content']?['parts'] as List?;
        if (parts == null || parts.isEmpty) {
          return _getMockMatchPrediction(teamA, statsA, teamB, statsB, disciplina);
        }
        final String text = (parts[0]['text'] as String?) ?? '';
        final cleanedJson = text.replaceAll('```json', '').replaceAll('```', '').trim();
        return jsonDecode(cleanedJson);
      } else {
        return _getMockMatchPrediction(teamA, statsA, teamB, statsB, disciplina);
      }
    } catch (e) {
      return _getMockMatchPrediction(teamA, statsA, teamB, statsB, disciplina);
    }
  }

  Map<String, dynamic> _getMockMatchPrediction(
    String teamA,
    Map<String, dynamic> statsA,
    String teamB,
    Map<String, dynamic> statsB,
    String disciplina,
  ) {
    double ptsA = (statsA['puntos'] ?? 0).toDouble();
    double ptsB = (statsB['puntos'] ?? 0).toDouble();
    
    int probEmpate = (disciplina == 'voleibol') ? 0 : 10;
    int probA = 45;
    int probB = 45;

    if (ptsA != ptsB) {
      double total = ptsA + ptsB;
      probA = ((ptsA / total) * (100 - probEmpate - 20)).round() + 10;
      probB = ((ptsB / total) * (100 - probEmpate - 20)).round() + 10;
      
      int sum = probA + probB + probEmpate;
      if (sum != 100) {
        probA = probA + (100 - sum);
      }
    }

    // Asegurarse de no salir de límites
    if (probA < 0) { probB += probA; probA = 0; }
    if (probB < 0) { probA += probB; probB = 0; }

    String favor = probA > probB ? teamA : teamB;
    String contra = probA > probB ? teamB : teamA;
    
    String marcadorEstimado = "";
    String analisisTactico = "";
    String keyMatchup = "";

    if (disciplina == 'voleibol') {
      int setsFavor = probA > probB ? 3 : 2;
      int setsContra = probA > probB ? 1 : 3;
      if (probA == probB) {
        setsFavor = 3;
        setsContra = 2;
      }
      marcadorEstimado = "$setsFavor - $setsContra";
      analisisTactico = "### Análisis de Rendimiento de Voleibol\n"
          "El encuentro promete ser de alta intensidad en la red. **$favor** llega con una sólida campaña, sumando **${statsA['puntos'] ?? 0} puntos** en la tabla y mostrando una excelente recepción y bloqueo. Por su parte, **$contra** buscará contrarrestar el saque en suspensión del rival mediante una defensa de campo compacta y transiciones rápidas por las bandas (Zona 4 y Zona 2) para eludir el bloqueo doble.\n\n"
          "### Recomendación de Estrategia\n"
          "- **$teamA:** Asegurar el primer toque y acelerar las colocaciones de segundo golpe para desorganizar el bloqueo.\n"
          "- **$teamB:** Presionar con saques tácticos dirigidos al receptor débil y mantener cobertura de apoyo en el ataque.";
      keyMatchup = "La batalla clave estará en el bloqueo y la defensa sobre la red. El equipo que logre neutralizar los remates del opuesto adversario tendrá un 70% de probabilidades de asegurar la victoria.";
    } else if (disciplina == 'basquetbol') {
      int scoreFavor = probA > probB ? 88 : 80;
      int scoreContra = probA > probB ? 80 : 88;
      if (probA == probB) {
        scoreFavor = 82;
        scoreContra = 82;
      }
      marcadorEstimado = "$scoreFavor - $scoreContra";
      analisisTactico = "### Análisis de Rendimiento de Básquetbol\n"
          "El duelo se definirá por la efectividad en el tiro de media y larga distancia y las posesiones en transición. **$favor** lidera las estadísticas con **${statsA['puntos'] ?? 0} puntos** acumulados, destacando por su bloqueo y continuación (pick and roll). **$contra** apostará por la defensa en zona para frenar las penetraciones y capitalizar rebotes defensivos que permitan contragolpes rápidos.\n\n"
          "### Recomendación de Estrategia\n"
          "- **$teamA:** Mantener la rotación de balón en el perímetro para encontrar tiros abiertos de tres puntos.\n"
          "- **$teamB:** Ajustar las ayudas defensivas en la pintura y evitar segundas oportunidades controlando el rebote defensivo.";
      keyMatchup = "El enfrentamiento crítico se dará en el control de rebotes en ambos tableros. El dominio de la pintura definirá el ritmo de juego.";
    } else {
      // futbol
      int golesFavor = probA > probB ? 2 : 1;
      int golesContra = probA > probB ? 1 : 2;
      if (probA == probB) {
        golesFavor = 1;
        golesContra = 1;
      }
      marcadorEstimado = "$golesFavor - $golesContra";
      analisisTactico = "### Análisis de Rendimiento de Fútbol\n"
          "El encuentro promete ser sumamente cerrado tácticamente. **$favor** llega con una sólida campaña sumando **${statsA['puntos'] ?? 0} puntos** en la liga y mostrando un fútbol balanceado. Por su parte, **$contra** buscará contrarrestar las transiciones rápidas explotando las bandas y manteniendo una estructura defensiva compacta para evitar el juego asociativo por el centro.\n\n"
          "### Recomendación de Estrategia\n"
          "- **$teamA:** Mantener presión alta y circulación vertical rápida para desestabilizar la zaga rival.\n"
          "- **$teamB:** Replegarse en bloque medio-bajo, cerrar pasillos interiores y forzar el juego largo.";
      keyMatchup = "El duelo clave será en la mitad de la cancha, donde se disputará la posesión y el ritmo del partido. Quien logre imponer condiciones tácticas tendrá un 70% de probabilidades de llevarse el encuentro.";
    }

    return {
      "probabilidad_teamA": probA,
      "probabilidad_empate": probEmpate,
      "probabilidad_teamB": probB,
      "analisis_tactico": analisisTactico,
      "key_matchup": keyMatchup,
      "marcador_estimado": marcadorEstimado,
      "mode": "resilience"
    };
  }
}

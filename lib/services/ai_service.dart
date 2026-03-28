import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

class AIService {
  static const String _apiKey = 'AIzaSyBt46ITsjP4gcZQGDbOCk8opx9nmv7Gziw';
  
  // Endpoint v1 con modelo estable para 2026
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent';

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
        final String text = data['candidates'][0]['content']['parts'][0]['text'];
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
}

# CONTEXTO DE AUDITORÍA MÁSTER: OMNISPORT-AI (ERP DEPORTIVO)

## 1. VISIÓN GENERAL DEL PROYECTO
OmniSport-AI es un ERP Deportivo de grado profesional ("El SAP del Deporte") diseñado para centralizar la gestión técnica, médica, administrativa y legal de clubes y federaciones multidisciplinarias (Voleibol, Fútbol, Básquet). El objetivo es la profesionalización absoluta del deporte mediante tecnología de punta.

## 2. ARQUITECTURA Y STACK TECNOLÓGICO
- **Frontend:** Flutter (Apps móviles iOS/Android y Tablet Edition).
- **Backoffice:** React (Panel administrativo web).
- **Backend/Core:** Firebase (Firestore como DB NoSQL, Authentication para identidad y Cloud Functions para lógica serverless).
- **Orquestación:** n8n para automatización de pagos (Kushki/Paymentez) y notificaciones SOS.
- **IA Engine:** Integración de Google AI Studio y NotebookLM para análisis táctico y auditoría reglamentaria.
- **UI/UX Standard:** Estética "Diamond Glass" (estilo translúcido, neón cian, iconografía Cupertino).

## 3. MÓDULOS CRÍTICOS (ÉPICAS)
- **Smart ID (Pasaporte Deportivo):** Identidad digital con QR dinámico para acceso a torneos.
- **Seguridad Activa:** Monitoreo de ingreso/salida de atletas con alertas automáticas a tutores.
- **Módulo Médico & S.O.S:** Botón de emergencia, triaje inmediato y CRM de salud con trazabilidad de lesiones.
- **Scouting Hub:** Plataforma de reclutamiento basada en métricas de rendimiento y salud.
- **Marketing Gen:** Automatización de contenido para redes sociales (Player Cards MVP).

## 4. CUMPLIMIENTO LEGAL (LOPDP ECUADOR) - PRIORIDAD ALTA
El sistema debe cumplir estrictamente con la **Ley Orgánica de Protección de Datos Personales (LOPDP) de Ecuador**.
- **Protección de Menores:** El 80% de los usuarios son menores de edad. Los protocolos de seguridad de datos deben ser de nivel bancario.
- **Privacidad desde el Diseño:** No se permite el acceso a datos sensibles sin un token de consentimiento firmado digitalmente por el tutor legal.
- **Auditoría de Logs:** Registro inalterable de quién accede a qué dato y cuándo.

## 5. ESTÁNDARES DE CÓDIGO Y METODOLOGÍA
- **Arquitectura:** Clean Architecture (Separación clara de Capas: Data, Domain, Presentation).
- **Principios:** SOLID, DRY y KISS.
- **Database Patterns:** Firestore con esquemas de "Aplanamiento" y "Agregaciones" para minimizar lecturas y optimizar costos.
- **Calidad:** Cobertura de Testing Unitario obligatoria para flujos críticos (Pagos, Salud, Registro de Menores).

## 6. INSTRUCCIONES PARA EL AUDITOR (CLAUDE CODE)
Tu misión es actuar como un **Senior Auditor & Security Architect**. Al interactuar con esta base de código deberás:
1. **Identificar Vulnerabilidades:** Revisar `firestore.rules` y controladores para prevenir fugas de datos.
2. **Refactorización Metodológica:** Detectar "Code Smells" o violaciones de Clean Architecture en la carpeta `lib/`.
3. **Optimización de Recursos:** Sugerir mejoras que reduzcan la latencia y el consumo de tokens/lecturas de base de datos.
4. **Validación LOPDP:** Cuestionar cualquier flujo que ponga en riesgo la privacidad de los atletas menores de edad.

---
*Nota: Este documento es la "Única Fuente de Verdad" para el contexto de OmniSport-AI.*ya 
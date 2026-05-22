Plan de Implementación — Corrección de Fallas en iOS, Despliegue de Índices y Plan de Calidad QA Global (iOS, Android y Backoffice)
Este plan detalla las soluciones para corregir el cierre inesperado ("Omnisport-AI falló") de la aplicación en iOS al ingresar a Acceso, Identidad Digital y S.O.S., el despliegue del índice compuesto en la pantalla Historial de Asistencia, e incorpora una estrategia de aseguramiento de calidad (QA) total de extremo a extremo para garantizar que ningún flujo falle en iOS, Android o el Backoffice para tu presentación.

Diagnóstico y Causa Raíz
Cierres Inesperados en iOS (Acceso, Identidad Digital, SOS):

Análisis: Las tres pantallas afectadas (SecureQRView en Acceso, SportPassportScreen en Identidad Digital, SosAlertScreen en SOS) llaman a funciones de Firebase en la nube instanciando el SDK mediante FirebaseFunctions.instanceFor(region: 'us-central1').
Causa Raíz: En iOS, la inicialización regional explícita (instanceFor) del SDK nativo de Firebase Cloud Functions puede provocar fallas de segmentación nativas o excepciones de puntero nulo a nivel de CocoaPods si no están pre-configuradas a nivel de inicialización global de Firebase Core en iOS.
Solución: Dado que la región por defecto de Firebase Cloud Functions es precisamente us-central1, cambiar el llamado al formato estándar y altamente estable FirebaseFunctions.instance resuelve la inconsistencia nativa en el hilo de ejecución de iOS, previniendo el crash y logrando una comunicación estable.
Error al Cargar Historial en "Historial de Asistencia":

Análisis: La pantalla muestra el error: [cloud_firestore/failed-precondition] The query requires an index.
Causa Raíz: El índice compuesto de attendance_logs (athleteUid: ASC, timestamp: DESC) ya está correctamente declarado a nivel de configuración en 
firestore.indexes.json
, pero no se ha desplegado al proyecto Firebase activo.
Solución: Ejecutar el comando de despliegue de índices firebase deploy --only firestore:indexes.
Cambios Propuestos
Componente: Firebase Functions SDK Setup
[MODIFY] 
main.dart
Eliminar la inicialización redundante de emuladores para la región explícita:
diff

-        FirebaseFunctions.instanceFor(region: 'us-central1').useFunctionsEmulator(host, 5001);
[MODIFY] 
secure_qr_view.dart
Cambiar la llamada a FirebaseFunctions.instance.
[MODIFY] 
sport_passport_screen.dart
Cambiar la llamada a FirebaseFunctions.instance.
[MODIFY] 
sos_alert_screen.dart
Cambiar la llamada a FirebaseFunctions.instance.
[MODIFY] 
qr_scanner_screen.dart
Cambiar la llamada a FirebaseFunctions.instance.
[MODIFY] 
rbac_management_screen.dart
Cambiar la llamada a FirebaseFunctions.instance.
[MODIFY] 
attendance_report_screen.dart
Cambiar la llamada a FirebaseFunctions.instance.
[MODIFY] 
lopdp_vault_screen.dart
Cambiar la llamada a FirebaseFunctions.instance.
[MODIFY] 
login_screen.dart
Cambiar la llamada a FirebaseFunctions.instance.
[MODIFY] 
crm_medico_screen.dart
Cambiar la llamada a FirebaseFunctions.instance.
Plan de Verificación de Calidad (QA) Global y Robusto
Para garantizar que absolutamente nada falle y sorprenderte con la estabilidad del sistema, implementamos el siguiente marco estructurado de pruebas de 4 niveles en iOS, Android y el Backoffice Web:

Cambios de Código
Pruebas Unitarias
Pruebas Regresivas
Pruebas de Integración E2E
Protocolo QA Manual iOS & Android
Validación Backoffice Desktop/Web
Demo Inmaculada y Lista
1. Pruebas Unitarias (Foco en Lógica y Modelos)
Validan de forma aislada que los cálculos de negocio, mapeos de datos, serializaciones y manejo de errores se ejecuten de manera correcta.

Modelos: Ejecutar pruebas del modelo 
models_test.dart
 para comprobar la serialización de credenciales de atleta, expiración de tokens, decodificación JWT (SmartIdCredential) sin dependencias de plugins externos.
Servicios: Ejecutar 
services_unit_test.dart
 para validar la lógica del servicio de sincronización offline, el guardado en base de datos local (Hive) y la correcta encriptación de datos sensibles.
Comando de Ejecución: flutter test test/models_test.dart test/services_unit_test.dart
2. Pruebas Regresivas (Evitar Efectos Secundarios)
Garantizan que las correcciones de bugs históricos o de sprints anteriores no se rompan tras estas modificaciones.

Regresiones de Sprint 4: Ejecutar 
regression_sprint4_qa_test.dart
 para asegurar que:
Las conversiones de fechas UTC se mantengan exactas (evitando bugs de diferencias horarias en logs de asistencia).
Los nombres nulos en las tarjetas de hijos no causen excepciones visuales.
La lógica de cálculo de edad para menores de 18 años sea matemáticamente exacta.
El formato JSON de inserción manual de logs de asistencia se mantenga idéntico.
Regresión de Cierres de iOS: Ejecutar 
ios_crash_regression_test.dart
 para verificar que las firmas de los tokens QR cumplan con el formato esperado (SMART_ID), y que el catálogo del triage de S.O.S (InjuryType) no sufra mutaciones inesperadas.
Comando de Ejecución: flutter test test/regression_sprint4_qa_test.dart test/ios_crash_regression_test.dart
3. Pruebas de Integración (Flujos Completos E2E)
Prueban la interacción fluida entre múltiples pantallas, el comportamiento del estado global y el paso de datos de la interfaz a los controladores.

Flujos de Pantallas: Ejecutar 
screens_widget_test.dart
 para simular el inicio de sesión, la navegación del panel principal hacia la pantalla de escáner y la carga de datos del perfil con placeholders mientras se comunica con el servidor.
Integración Backoffice: Ejecutar 
backoffice_integration_test.dart
 para simular la importación masiva de datos en formato CSV, la validación de roles del personal y la generación de reportes consolidados de asistencia.
Comando de Ejecución: flutter test test/screens_widget_test.dart test/backoffice_integration_test.dart
4. Protocolo QA Manual y Verificación Cruzada (Plataforma por Plataforma)
En Dispositivos Móviles (iOS y Android):
Carga Inicial y Estabilidad: Entrar y salir 10 veces seguidas de Acceso (QR), Identidad Digital y SOS para confirmar que la aplicación no genera interrupciones críticas ni ralentizaciones visuales.
Gestión de Permisos Nativos:
Cámara: Negar el permiso de cámara al abrir el lector Zero Trust y verificar que la app muestre un mensaje elegante explicativo en lugar de cerrarse.
Ubicación: Negar el permiso de ubicación al activar un SOS y comprobar que el flujo continúa enviando la alerta médica indicando "Ubicación no disponible" sin romperse.
Modo Offline (Resiliencia de Red):
Activar el Modo Avión en el simulador/dispositivo.
Navegar a Identidad Digital. Verificar que cargue de inmediato los datos desde el caché local (Hive) mostrando la tarjeta con el indicador visual de "Modo Offline".
Navegar a Acceso. Confirmar que la pantalla muestra la advertencia "Sin conexión. Reintentando..." en lugar de un crash.
Desactivar Modo Avión y comprobar que el token QR se regenera automáticamente y la credencial digital se sincroniza de inmediato con el servidor.
Estética de Interfaz (Diamond Glass):
Validar visualmente la consistencia del diseño en dispositivos pequeños (como iPhone SE) y grandes (como iPhone 17 Pro Max / Android Tablets).
Verificar que los degradados en azul marino (#001F3F) a cian fluorescente (#00E5FF), las capas de desenfoque (BackdropFilter sigma 15) y los bordes con brillo translúcido se rendericen de manera fluida a 60/120 FPS sin parpadeos.
En el Backoffice (Administración en Web / Desktop):
Validación del Historial de Asistencia:
Tras desplegar los índices compuestos, abrir el "Historial de Asistencia" en el Backoffice y en la App Móvil.
Asegurar que la lista de atletas se ordene de forma cronológica descendente perfectamente y cargue en menos de 1 segundo de forma reactiva en tiempo real.
Ingesta de Datos CSV:
Realizar una ingesta de prueba usando un archivo CSV con caracteres latinos (tildes, eñes) para confirmar que se codifiquen correctamente en UTF-8 y se registren sin deformar los datos.
Comandos de Despliegue de Índices Firestore
Ejecutar en la terminal el comando de Firebase CLI para activar los índices compuestos que necesita el Historial de Asistencia:

bash

firebase deploy --only firestore:indexes
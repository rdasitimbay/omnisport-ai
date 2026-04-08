# 🏐 OmniSport-AI: Mega ERP de Gestión Deportiva Inteligente

![Build](https://img.shields.io/badge/Build-20.1_Antigravity-orange?style=for-the-badge)
![Security](https://img.shields.io/badge/DPO_Shield-Zero_Trust_Active-red?style=for-the-badge)
![UI](https://img.shields.io/badge/UI-Diamond_Glass_🍏-blue?style=for-the-badge)
![Status](https://img.shields.io/badge/Sprint-1_Completado-green?style=for-the-badge)

**OmniSport-AI** es una plataforma de gestión deportiva de alto rendimiento que fusiona la ingeniería de software avanzada con la auditoría de sistemas tecnológicos. Este Mega ERP está diseñado para ofrecer seguridad inquebrantable y una experiencia de usuario de élite.

---

## 🏗️ Infraestructura y Optimización "Zero-Detritus"

Para garantizar la estabilidad en el desarrollo bajo **macOS (M4)**, se implementó una arquitectura de archivos blindada contra interferencias de procesos en la nube:

* **Ruta de Desarrollo Local:** Migración crítica desde OneDrive a una zona protegida: `~/Documents/ANTIGRAVITY/omnisport-ai.nosync/`.
* **Aislamiento Cloud:** El uso del sufijo `.nosync` impide que iCloud/OneDrive generen metadatos corruptos durante la compilación.
* **Saneamiento de Atributos:** Limpieza sistemática de *resource forks* y *Finder information* mediante `xattr -cr .`, permitiendo un **Code Signing** exitoso para producción.
* **Parche de Compilación Xcode:** Optimización del `Podfile` para suprimir advertencias de cabeceras en frameworks internos (`Nanopb`, `Firebase`, `leveldb`) mediante la flag `CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER`.

---

## 🛡️ DPO Shield: El Pilar de Seguridad Zero Trust

El sistema de acceso implementa un protocolo de seguridad diseñado bajo la normativa de **Protección de Datos Personales (LOPDP)**:

### 1. Validación de Acceso Dinámico
* **Tokens de Rotación:** QRs con validez de **30 segundos** generados mediante JWT para mitigar ataques de replay y capturas de pantalla.
* **Handshake Seguro:** Validación asíncrona que distingue entre accesos **APTOS**, **EXPIRADOS** e **ILEGIBLES/FALSOS**.

### 2. Resiliencia Multiplataforma (Android Fix)
* **Thread Recovery:** Implementación de lógica de autorecuperación en el método `_resetScanner()`.
* **Reseteo de Hilos:** Uso de `_scannerController.start()` con manejo de excepciones para evitar el congelamiento de la cámara en dispositivos Android tras detecciones exitosas.

---

## 🍏 Diamond Glass UI: Experiencia de Vanguardia

Interfaz de usuario inspirada en el diseño moderno de Apple, optimizada para pantallas de alta densidad:
* **Efectos de Cristal:** Uso de `BackdropFilter` con desenfoque gaussiano y gradientes dinámicos.
* **Feedback en Tiempo Real:** Paneles de estado translúcidos que informan la telemetría del escaneo sin interrumpir la visión de la cámara.

---

## 🧪 Control de Calidad y Auditoría

Resultados oficiales de la suite de pruebas unitarias y de integración (vía `test/validator_test.dart`):

| Test ID | Caso de Prueba | Resultado |
| :--- | :--- | :--- |
| **TC-01** | Validar QR vigente y autenticado (DPO Shield) | ✅ PASSED |
| **TC-02** | Bloquear ingreso con QR expirado (>30s) | ✅ PASSED |
| **TC-03** | Detectar y alertar sobre QRs ilegibles o falsos | ✅ PASSED |
| **TC-04** | Validar reset de cámara y recuperación de UI en Android | ✅ PASSED |

---

## 🚀 Despliegue Actual

* **iOS:** Distribuido vía **TestFlight** para pruebas de usuario final.
* **Android:** Generación de **APK Release** optimizada para distribución directa.
* **Repo:** Historial de commits saneado y respaldado en GitHub.

---

## 📅 Roadmap de Próximas Épicas

- [ ] **Sprint 2:** Integración real con **Firebase Firestore** para gestión biográfica de atletas.
- [ ] **Sprint 3:** Implementación del motor de notificaciones **Opal AI** para representantes.
- [ ] **Sprint 4:** Dashboard de telemetría y auditoría de flujos para coordinación.

---
**Director de Proyecto:** Rommel Asitimbay Morales  
**Ingeniería de Desarrollo:** Antigravity AI Engine  
**Hardware de Referencia:** MacBook Air M4 (Local Optimized) 🚀

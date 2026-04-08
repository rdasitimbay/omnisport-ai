# 🏐 OmniSport-AI: El Mega ERP del Deporte Inteligente

![Status](https://img.shields.io/badge/Sprint-1_Completado-green?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-v3.x-02569B?style=for-the-badge&logo=flutter)
![License](https://img.shields.io/badge/Security-DPO_Shield_Active-blue?style=for-the-badge)

**OmniSport-AI** es una plataforma integral de gestión deportiva que fusiona una estética de vanguardia (**Diamond Glass UI**) con un motor de seguridad de grado bancario (**DPO Shield**). Diseñado para coordinadores y clubes que no comprometen la seguridad ni la experiencia del usuario.

---

## 💎 Pilares del Proyecto

### 1. Zero Trust Scanner (DPO Shield) 🛡️
Implementación de acceso mediante QRs dinámicos con rotación de **30 segundos**. 
* **Validación en tiempo real:** Handshake seguro para prevenir capturas de pantalla o fraude.
* **Cumplimiento LOPDP:** Arquitectura diseñada bajo estándares de Protección de Datos Personales (Ecuador).

### 2. Diamond Glass UI 🍏
Interfaz de usuario de alta fidelidad que utiliza efectos de desenfoque gaussiano, gradientes dinámicos y jerarquía visual de élite, optimizada para el rendimiento del procesador **M4**.

### 3. Opal AI Integration (Próximamente) 🤖
Asistente inteligente para la automatización de notificaciones a representantes y telemetría de flujo en eventos deportivos.

---

## 🛠️ Especificaciones Técnicas

* **Framework:** Flutter (Multiplataforma iOS/Android).
* **Backend:** Firebase (Firestore, Auth, Cloud Functions).
* **Seguridad:** JWT (JSON Web Tokens) para validación offline/online.
* **Arquitectura:** Clean Architecture con gestión de estado optimizada.

---

## 🚀 Logros del Sprint 1 (Hitos Alcanzados)

- [x] **Estabilización de Entorno:** Migración exitosa de entornos cloud (OneDrive) a rutas locales protegidas (`.nosync`) para optimización de compilación.
- [x] **Code Signing:** Firma de código validada para producción en iOS y Android.
- [x] **Unit Testing:** Cobertura del 100% en lógica de validación de acceso (4/4 tests passed).
- [x] **Despliegue:** Binarios generados con éxito para **TestFlight** y **APK Release**.

---

## 🔧 Guía de Instalación para Desarrolladores

Para mantener la integridad de la firma de código en macOS, se recomienda trabajar en una ruta local fuera de sincronización cloud:

1.  **Clonar el repositorio:**
    ```bash
    git clone [https://github.com/rdasitimbay/omnisport-ai.git](https://github.com/rdasitimbay/omnisport-ai.git)
    ```
2.  **Limpiar atributos de sistema (Fix para Xcode CodeSign):**
    ```bash
    xattr -cr .
    ```
3.  **Obtener dependencias:**
    ```bash
    flutter pub get
    ```
4.  **Ejecutar pruebas unitarias:**
    ```bash
    flutter test test/validator_test.dart
    ```

---

## 📈 Roadmap de Ingeniería

* **Sprint 2:** Integración real de base de datos de atletas y perfiles biométricos.
* **Sprint 3:** Módulo de pagos y pasarela de suscripciones para torneos.
* **Sprint 4:** Dashboard de telemetría para coordinación de complejos deportivos.

---

> **Nota del Autor:** Este proyecto es desarrollado bajo la coordinación de **Rommel Asitimbay Morales**, combinando ingeniería de software con auditoría de sistemas tecnológicos. 🦾🏐


# app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

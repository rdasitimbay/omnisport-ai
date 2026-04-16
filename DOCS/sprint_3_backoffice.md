# Sprint 3: Backoffice Panel (Estructura Base)

Este documento define la estructura técnica para construir el Panel de Administración (Backoffice) que alimentará de manera masiva la arquitectura Frontend consolidada durante el Sprint 2.

## 1. Arquitectura de Datos: Firestore

La gestión administrativa requerirá interactuar con la siguiente estructura de colecciones:

### 1.1 `athletes` (Colección Principal)
Cada documento es identificado por su `uid` único.
```json
{
  "uid": "auto-generated-or-auth-id",
  "fullName": "Juan Pérez",
  "photoUrl": "https://storage.firebase.com/...",
  "teamOrCategory": "Sub-16 Masculino",
  "paymentStatus": "Pago Pendiente", // o "Al Día"
  "lastMedicalReview": Timestamp(17100000), 
  "representativeUid": "auth-uuid-del-padre-o-tutor",
  "emergencyPhone": "+593999999999",
  "isMinor": true
}
```

### 1.2 `access_logs` (Logs de Seguridad - DPO Shield)
Cada vez que el escáner (o el modo sin conexión) autorice un ingreso, se guarda el registro aquí:
```json
{
  "uid": "athlete-uid",
  "timestamp": Timestamp(17100000),
  "method": "athlete_with_guardian", 
  "synced": true,
  "location": "Puerta Principal"
}
```

## 2. Requerimientos de Backend (Panel de Administración)

El backoffice que generaremos en el Sprint 3 deberá incluir las siguientes vistas clave:

1. **Gestor de Atletas (CRUD)**
   - Tabla de carga masiva (Soporte CSV/Excel).
   - Generación automática de JWTs para QR vinculados al `uid` del atleta recién creado.
   - Sincronización transparente de fotos hacia *Firebase Storage*.

2. **Panel de Alertas Financieras**
   - Gráfico de atletas `paymentStatus == 'Pago Pendiente'`.
   - Botón para enviar recordatorios masivos mediante la red **Opal AI Push**.

3. **Monitor Médico**
   - Vista de tableros de fechas `lastMedicalReview`. Resaltar en rojo atletas con certificaciones vencidas.

## 3. Next Steps
* Diseñar la estructura web con Next.js o Vite enfocada a Desktop.
* Compartir el *Firebase Admin SDK service account* para escrituras privilegiadas.
* Integrar la funcionalidad generadora de Tokens JWT (30s DPO Shield logic) en un generador de PDFs (Impresión de la tarjeta física/Pase Digital).

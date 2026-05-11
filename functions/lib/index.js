"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.syncAccessLog = exports.requestAthleteErasure = exports.logSensitiveAccess = exports.processBulkIngestion = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
admin.initializeApp();
const db = admin.firestore();
// =============================================================================
// SECCIÓN 1: CONSTANTES DE FIRESTORE
// =============================================================================
// WriteBatch: máx 500 ops. Cada atleta = 2 writes → 250 atletas por lote.
const ATHLETES_PER_BATCH = 250;
// Cláusula 'in': máx 30 valores por query → O(N/30) en deduplicación.
const FIRESTORE_IN_LIMIT = 30;
// =============================================================================
// SECCIÓN 4: GUARDS DE AUTENTICACIÓN
// =============================================================================
function assertAdmin(request) {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "No autenticado.");
    }
    if (request.auth.token["role"] !== "admin") {
        throw new https_1.HttpsError("permission-denied", "Solo administradores pueden ejecutar esta operación.");
    }
}
function assertAuthenticated(request) {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "No autenticado.");
    }
    // Art. 10 LOPDP: consent_signed requerido para cualquier operación de datos.
    if (!request.auth.token["consent_signed"]) {
        throw new https_1.HttpsError("permission-denied", "Consentimiento del tutor legal no firmado. Completa el proceso de onboarding.");
    }
}
function assertAdminOrSelf(request, targetUid) {
    assertAuthenticated(request);
    const isAdmin = request.auth.token["role"] === "admin";
    const isSelf = request.auth.uid === targetUid;
    if (!isAdmin && !isSelf) {
        throw new https_1.HttpsError("permission-denied", "Operación no autorizada.");
    }
}
// =============================================================================
// SECCIÓN 5: HELPERS
// =============================================================================
/** Parsea y valida el CSV. Retorna registros válidos y conteo de fallidos. */
function parseAndValidateCsv(csvString) {
    const EMAIL_REGEX = /^[^@]+@[^@]+\.[^@]+/;
    const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;
    const clean = csvString
        .replace(/\r\n/g, "\n")
        .replace(/\r/g, "\n")
        .replace(/﻿/g, "");
    const lines = clean.split("\n").filter((l) => l.trim());
    if (lines.length < 2)
        return { valid: [], failed: 0 };
    const headerLine = lines[0].toLowerCase();
    const sep = headerLine.includes(";") &&
        headerLine.split(";").length > headerLine.split(",").length ? ";" : ",";
    const headers = lines[0].split(sep).map((h) => h.toLowerCase().replace(/﻿/g, "").trim());
    const idx = (matchers) => headers.findIndex((h) => matchers.some((m) => h.includes(m)));
    const nameIdx = idx(["full_name", "nombre"]);
    const dniIdx = idx(["dni"]);
    const emailIdx = idx(["email", "correo"]);
    const phoneIdx = idx(["phone", "telefono"]);
    const teamIdx = idx(["team", "categor"]);
    const consentIdx = idx(["consent_date", "consentimiento"]);
    if (nameIdx === -1 || dniIdx === -1 || consentIdx === -1) {
        throw new https_1.HttpsError("invalid-argument", `Cabecera CSV inválida. Detectadas: ${headers.join(", ")}`);
    }
    const cell = (row, i) => i >= 0 && i < row.length ? row[i].trim() : "";
    const valid = [];
    let failed = 0;
    for (let i = 1; i < lines.length; i++) {
        const row = lines[i].split(sep);
        if (row.join("").trim() === "")
            continue;
        const name = cell(row, nameIdx);
        const dni = cell(row, dniIdx);
        const email = cell(row, emailIdx);
        const phone = cell(row, phoneIdx);
        const team = teamIdx >= 0 ? cell(row, teamIdx) : "Sin Categoría";
        const consentDate = cell(row, consentIdx);
        // Defense in depth — re-validación completa en servidor.
        if (!consentDate || !DATE_REGEX.test(consentDate)) {
            failed++;
            continue;
        }
        if (!dni) {
            failed++;
            continue;
        }
        if (email && !EMAIL_REGEX.test(email)) {
            failed++;
            continue;
        }
        valid.push({ rowNumber: i + 1, name, dni, email, phone, team, consentDate });
    }
    return { valid, failed };
}
/**
 * Verifica duplicados de DNI usando batched 'in' queries.
 * Complejidad: O(N/30) lecturas vs O(N) individual — crítico para ingestas grandes.
 */
async function fetchExistingDnis(dnis) {
    const existingDnis = new Set();
    for (let i = 0; i < dnis.length; i += FIRESTORE_IN_LIMIT) {
        const chunk = dnis.slice(i, i + FIRESTORE_IN_LIMIT);
        const snap = await db.collectionGroup("sensitive_data")
            .where("dni", "in", chunk).get();
        for (const doc of snap.docs) {
            const d = doc.data()["dni"];
            if (d)
                existingDnis.add(d);
        }
    }
    return existingDnis;
}
/**
 * Escribe en audit_logs con Admin SDK (bypasea allow write: if false de las reglas).
 * Retorna el document ID para incluirlo en respuestas Hive como comprobante legal.
 * Art. 37 LOPDP: timestamps generados en servidor, inmutables desde el cliente.
 */
async function writeAuditLog(action, performedBy, metadata) {
    const ref = await db.collection("audit_logs").add({
        action,
        performedBy,
        ...metadata,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    return ref.id;
}
// =============================================================================
// SECCIÓN 6: FUNCIÓN 1 — processBulkIngestion
//
// Callable desde AdminIngestionController.confirmIngestion() en Flutter.
// Retorna IngestionSummaryHive (@HiveType typeId: 10) — cacheable en Hive.
//
// Art. 10 LOPDP: ninguna escritura de datos sensibles desde el cliente.
// Art. 26 LOPDP: consent_date → Firestore Timestamp verificado en servidor.
// Art. 37 LOPDP: evento de ingesta registrado en audit_logs.
// =============================================================================
exports.processBulkIngestion = (0, https_1.onCall)({ region: "us-central1", timeoutSeconds: 300, memory: "512MiB" }, async (request) => {
    assertAdmin(request);
    const { csv, institutionId } = request.data;
    if (!csv || !institutionId) {
        throw new https_1.HttpsError("invalid-argument", "csv e institutionId son requeridos.");
    }
    const executedAtMs = Date.now();
    const adminId = request.auth.uid;
    // ── Paso 1: Validación de formato (defense in depth) ──────────────────
    const { valid: candidates, failed: formatFailed } = parseAndValidateCsv(csv);
    if (candidates.length === 0) {
        await writeAuditLog("BULK_INGESTION_NO_VALID_RECORDS", adminId, {
            institutionId, total: formatFailed, valid: 0, failed: formatFailed,
        });
        return {
            institutionId, total: formatFailed, valid: 0,
            failed: formatFailed, duplicates: 0, batchCount: 0,
            executedAtMs, adminId,
        };
    }
    // ── Paso 2: Deduplicación forense por DNI (batched 'in') ──────────────
    const allDnis = candidates.map((r) => r.dni);
    const existingDnis = await fetchExistingDnis(allDnis);
    const toWrite = candidates.filter((r) => !existingDnis.has(r.dni));
    const duplicates = candidates.length - toWrite.length;
    const totalFailed = formatFailed + duplicates;
    // ── Paso 3: Escritura en WriteBatches de 500 ops (250 atletas/lote) ───
    let batchCount = 0;
    for (let i = 0; i < toWrite.length; i += ATHLETES_PER_BATCH) {
        const chunk = toWrite.slice(i, i + ATHLETES_PER_BATCH);
        const batch = db.batch();
        batchCount++;
        for (const record of chunk) {
            const athleteRef = db.collection("athletes").doc();
            // Documento raíz — datos públicos del atleta en Firestore.
            batch.set(athleteRef, {
                ownerInstitutionId: institutionId,
                full_name: record.name,
                teamOrCategory: record.team,
                paymentStatus: "Pago Pendiente",
                status: "Inactivo",
                photoUrl: "",
                // Art. 26 LOPDP: Timestamp verificado en servidor, no interpolable.
                consent_timestamp: admin.firestore.Timestamp.fromDate(new Date(`${record.consentDate}T00:00:00Z`)),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            // Subcolección /private — datos sensibles LOPDP.
            // Solo Admin SDK puede escribir aquí (allow write: if false en cliente).
            batch.set(athleteRef.collection("private").doc("sensitive_data"), { dni: record.dni, email: record.email, phone: record.phone });
        }
        await batch.commit();
    }
    // ── Paso 4: Registro en audit_logs ────────────────────────────────────
    await writeAuditLog("BULK_INGESTION_COMPLETED", adminId, {
        institutionId,
        total: candidates.length + formatFailed,
        valid: toWrite.length,
        failed: totalFailed,
        duplicates,
        batchCount,
    });
    // ── Respuesta Hive-nativa (@HiveType typeId: 10) ───────────────────────
    return {
        institutionId,
        total: candidates.length + formatFailed,
        valid: toWrite.length,
        failed: totalFailed,
        duplicates,
        batchCount,
        executedAtMs, // Unix ms — Hive int nativo
        adminId,
    };
});
// =============================================================================
// SECCIÓN 7: FUNCIÓN 2 — logSensitiveAccess
//
// Callable desde AdminIngestionController.logDniReveal() en Flutter.
// Retorna AuditLogEntryHive (@HiveType typeId: 11) — cacheable para auditoría offline.
//
// El cliente Flutter NUNCA escribe en audit_logs directamente.
// Art. 37 LOPDP: log inalterable, timestamp de servidor, con identidad del admin.
// =============================================================================
exports.logSensitiveAccess = (0, https_1.onCall)({ region: "us-central1" }, async (request) => {
    assertAdmin(request);
    const { athleteId, action } = request.data;
    if (!athleteId || !action) {
        throw new https_1.HttpsError("invalid-argument", "athleteId y action son requeridos.");
    }
    const token = request.auth.token;
    const adminId = request.auth.uid;
    const adminEmail = token["email"] ?? "";
    const institutionId = token["institutionId"] ?? "";
    const timestampMs = Date.now();
    // Escribe en audit_logs y obtiene el document ID como comprobante legal.
    const logId = await writeAuditLog(action, adminId, {
        athleteId, adminEmail, institutionId,
    });
    // ── Respuesta Hive-nativa (@HiveType typeId: 11) ───────────────────────
    // Flutter cachea esta entrada en Hive para auditoría offline y reporte LOPDP.
    return {
        logId, // ID del documento Firestore — prueba forense de la operación
        action,
        athleteId,
        adminId,
        adminEmail,
        institutionId,
        timestampMs, // Unix ms — Hive int nativo
    };
});
// =============================================================================
// SECCIÓN 8: FUNCIÓN 3 — requestAthleteErasure
//
// Callable desde FirestoreService.requestAthleteErasure() en Flutter.
// Retorna ErasureReceiptHive (@HiveType typeId: 12) — comprobante legal del borrado.
//
// ORDEN CRÍTICO (Art. 37 LOPDP): audit_log PERSISTE antes del borrado de datos.
// Si el borrado falla a mitad, el log queda como evidencia del intento.
//
// Art. 16 LOPDP: derecho al olvido — borrado completo, irreversible y auditado.
// =============================================================================
exports.requestAthleteErasure = (0, https_1.onCall)({ region: "us-central1", timeoutSeconds: 120 }, async (request) => {
    const { uid } = request.data;
    if (!uid)
        throw new https_1.HttpsError("invalid-argument", "uid es requerido.");
    assertAdminOrSelf(request, uid);
    const callerId = request.auth.uid;
    const isSelfErasure = callerId === uid;
    const erasureType = isSelfErasure ? "SELF_ERASURE" : "ADMIN_ERASURE";
    // ── Paso 1: Verifica existencia y captura metadata pre-borrado ─────────
    const athleteRef = db.collection("athletes").doc(uid);
    const athleteSnap = await athleteRef.get();
    if (!athleteSnap.exists) {
        throw new https_1.HttpsError("not-found", `Atleta ${uid} no encontrado.`);
    }
    const institutionId = athleteSnap.data()?.["ownerInstitutionId"] ?? "";
    const athleteName = athleteSnap.data()?.["full_name"] ?? "Desconocido";
    // ── Paso 2: Audit log INICIADO — antes de borrar (Art. 37 LOPDP) ──────
    await writeAuditLog(`${erasureType}_INITIATED`, callerId, {
        targetUid: uid, athleteName, institutionId,
    });
    // ── Paso 3: Borrado recursivo — raíz + todas las subcolecciones ────────
    // recursiveDelete() maneja /private, /sport_details, /historial_entrenamientos.
    await db.recursiveDelete(athleteRef);
    // ── Paso 4: Revocación de refresh tokens ──────────────────────────────
    // Invalida sesiones activas en cualquier dispositivo.
    try {
        await admin.auth().revokeRefreshTokens(uid);
    }
    catch { /* ya expirado */ }
    // ── Paso 5: Borrado de cuenta Auth (solo admin-erasure) ───────────────
    // En self-erasure: el cliente Flutter llama user.delete() tras este retorno.
    if (!isSelfErasure) {
        try {
            await admin.auth().deleteUser(uid);
        }
        catch { /* usuario ya eliminado */ }
    }
    // ── Paso 6: Audit log COMPLETADO — comprobante legal irrefutable ───────
    const completedAtMs = Date.now();
    const receiptId = await writeAuditLog(`${erasureType}_COMPLETED`, callerId, {
        targetUid: uid, institutionId, completedAtMs,
    });
    // ── Respuesta Hive-nativa (@HiveType typeId: 12) ───────────────────────
    // Este comprobante persiste en Hive incluso después de que el perfil
    // haya sido borrado de Firestore — evidencia legal del Derecho al Olvido.
    return {
        receiptId, // ID del audit_log de confirmación — prueba forense
        targetUid: uid,
        erasureType,
        performedBy: callerId,
        institutionId,
        completedAtMs, // Unix ms — Hive int nativo
    };
});
// =============================================================================
// SECCIÓN 9: FUNCIÓN 4 — syncAccessLog (CRÍTICO para OfflineSyncService)
//
// Reemplaza la escritura directa en access_logs desde offline_sync_service.dart.
// La regla 'allow write: if false' en access_logs obliga a que todo log de acceso
// QR pase por esta Cloud Function.
//
// Flutter: llamar desde OfflineSyncService.syncLogs() cuando hay conectividad.
// El servidor corrige el timestamp con la hora del servidor (anti-manipulación).
// Art. 37 LOPDP: el registro de entrada/salida es inalterable una vez en servidor.
// =============================================================================
exports.syncAccessLog = (0, https_1.onCall)({ region: "us-central1" }, async (request) => {
    assertAuthenticated(request);
    const { logs } = request.data;
    if (!Array.isArray(logs) || logs.length === 0) {
        throw new https_1.HttpsError("invalid-argument", "logs debe ser un array no vacío.");
    }
    // Límite de seguridad: máx 100 logs por llamada para evitar abuso.
    if (logs.length > 100) {
        throw new https_1.HttpsError("invalid-argument", "Máximo 100 logs por sincronización.");
    }
    const serverMs = Date.now();
    const batch = db.batch();
    for (const log of logs) {
        if (!log.athleteId || !log.eventType)
            continue;
        const docRef = db.collection("access_logs").doc();
        batch.set(docRef, {
            athleteId: log.athleteId,
            scannedByUid: log.scannedByUid,
            eventType: log.eventType, // 'ENTRY' | 'EXIT'
            locationId: log.locationId ?? "",
            clientMs: log.clientMs, // preservado para auditoría de latencia
            // El timestamp oficial es el del servidor — no manipulable desde el cliente.
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            syncedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    await batch.commit();
    return { syncedCount: logs.length, serverMs };
});
//# sourceMappingURL=index.js.map
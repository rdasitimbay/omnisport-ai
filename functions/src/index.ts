import * as admin from "firebase-admin";
import { Timestamp, FieldValue } from "firebase-admin/firestore";
import * as crypto from "crypto";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";

// Llave maestra. En producción, debería inyectarse vía process.env o Secret Manager.
const MASTER_AES_KEY = process.env.MASTER_AES_KEY || "omnisport-ai-super-secret-dev-key";

// Derivar llave de 32 bytes y IV de 16 bytes de forma determinista para permitir búsquedas (deduplicación)
const ENCRYPTION_KEY = crypto.createHash('sha256').update(MASTER_AES_KEY).digest();
const STATIC_IV = crypto.createHash('md5').update(MASTER_AES_KEY).digest();

export function encryptData(text: string): string {
  if (!text) return text;
  const cipher = crypto.createCipheriv('aes-256-cbc', ENCRYPTION_KEY, STATIC_IV);
  let encrypted = cipher.update(text, 'utf8', 'base64');
  encrypted += cipher.final('base64');
  return encrypted;
}

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
// SECCIÓN 2: CONTRATOS HIVE TYPEADAPTER
//
// REGLA DE ORO: Todos los timestamps se envían como Unix milliseconds (number).
// Hive TypeAdapters no pueden serializar Firestore Timestamp ni DateTime directamente.
// El colega Flutter debe implementar @HiveType con los typeId y @HiveField con los
// índices definidos aquí. Cualquier cambio en este archivo rompe la sincronización.
//
// Tipos primitivos permitidos en Hive sin adaptador custom:
//   String, int, double, bool, List<primitive>, Map<String, primitive>
// =============================================================================

/**
 * @HiveType(typeId: 10)
 * Resultado de ingesta masiva — cacheable para historial de operaciones del admin.
 */
interface IngestionSummaryHive {
  institutionId: string;  // @HiveField(0)
  total:         number;  // @HiveField(1) - registros en el CSV
  valid:         number;  // @HiveField(2) - atletas persistidos correctamente
  failed:        number;  // @HiveField(3) - rechazados por formato/LOPDP
  duplicates:    number;  // @HiveField(4) - DNIs ya existentes en el sistema
  batchCount:    number;  // @HiveField(5) - lotes de WriteBatch ejecutados
  executedAtMs:  number;  // @HiveField(6) - Unix ms del servidor (no del cliente)
  adminId:       string;  // @HiveField(7) - UID del admin que ejecutó la ingesta
}

/**
 * @HiveType(typeId: 11)
 * Entrada de log de acceso a dato sensible — cacheable para auditoría offline.
 * Art. 37 LOPDP: trazabilidad de cada visualización de DNI.
 */
interface AuditLogEntryHive {
  logId:         string;  // @HiveField(0) - Firestore document ID del audit_log
  action:        string;  // @HiveField(1) - ej. 'unmask_dni'
  athleteId:     string;  // @HiveField(2) - UID del atleta afectado
  adminId:       string;  // @HiveField(3) - UID del admin que accedió
  adminEmail:    string;  // @HiveField(4) - email del admin (del JWT)
  institutionId: string;  // @HiveField(5) - institución del admin
  timestampMs:   number;  // @HiveField(6) - Unix ms del servidor
}

/**
 * @HiveType(typeId: 12)
 * Comprobante de borrado LOPDP — cacheable como evidencia del Derecho al Olvido.
 * Art. 16 LOPDP: el comprobante persiste en Hive incluso tras borrar el perfil.
 */
interface ErasureReceiptHive {
  receiptId:     string;  // @HiveField(0) - ID del audit_log como comprobante legal
  targetUid:     string;  // @HiveField(1) - UID del atleta borrado
  erasureType:   string;  // @HiveField(2) - 'SELF_ERASURE' | 'ADMIN_ERASURE'
  performedBy:   string;  // @HiveField(3) - UID del ejecutor
  institutionId: string;  // @HiveField(4) - institución del atleta borrado
  completedAtMs: number;  // @HiveField(5) - Unix ms de confirmación en servidor
}

/**
 * @HiveType(typeId: 13)
 * Cola de logs de acceso QR pendientes de sincronización.
 * Reemplaza la escritura directa en access_logs desde OfflineSyncService.
 * Art. 37 LOPDP: el registro de entrada/salida es inalterable una vez sincronizado.
 */
interface OfflineAccessLogHive {
  athleteId:    string;   // @HiveField(0) - UID del atleta escaneado
  scannedByUid: string;   // @HiveField(1) - UID del usuario que escaneó
  eventType:    string;   // @HiveField(2) - 'ENTRY' | 'EXIT'
  locationId:   string;   // @HiveField(3) - ID del punto de acceso
  clientMs:     number;   // @HiveField(4) - Unix ms del cliente al momento del scan
  synced:       boolean;  // @HiveField(5) - false hasta confirmación del servidor
}

/** Respuesta de syncAccessLog — confirma cada log persistido. */
interface SyncAccessLogResponse {
  syncedCount:  number;   // @HiveField(0) en el response wrapper (no se cachea)
  serverMs:     number;   // @HiveField(1) - Unix ms del servidor al procesar
}

// =============================================================================
// SECCIÓN 3: TIPOS DE REQUEST (entrada desde Flutter)
// =============================================================================

interface IngestionRequest {
  csv:           string;
  institutionId: string;
}

interface LogAccessRequest {
  athleteId: string;
  action:    string;
}

interface ErasureRequest {
  uid: string;
}

interface SyncAccessLogRequest {
  logs: OfflineAccessLogHive[];
}

// =============================================================================
// SECCIÓN 4: EMULATOR BRIDGE + GUARDS DE AUTENTICACIÓN
//
// IS_EMULATOR es true SOLO cuando el proceso corre dentro del Firebase Emulator.
// La variable FUNCTIONS_EMULATOR es inyectada automáticamente por el emulador;
// nunca está presente en Cloud Functions desplegadas en producción.
// =============================================================================

const IS_EMULATOR = process.env["FUNCTIONS_EMULATOR"] === "true";

// Identidad sintética usada en el emulador cuando no se envía token real.
// Equivale a un admin de institución de desarrollo — nunca llega a producción.
const EMULATOR_IDENTITY = {
  uid:   "emulator-admin",
  token: {
    role:           "admin",
    institutionId:  "inst-dev-001",
    consent_signed: true,
    email:          "dev@omnisport.local",
  } as Record<string, unknown>,
};

/**
 * Devuelve el auth real del request, o la identidad sintética en el emulador.
 * Centraliza el acceso a request.auth para que los handlers no necesiten !-asserts.
 */
function resolveAuth(request: CallableRequest) {
  return request.auth ?? EMULATOR_IDENTITY;
}

async function assertAdmin(request: CallableRequest): Promise<void> {
  if (IS_EMULATOR && !request.auth) return;
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "No autenticado.");
  }
  const userDoc = await db.collection("users").doc(request.auth.uid).get();
  if (!userDoc.exists || userDoc.data()?.role !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Solo administradores pueden ejecutar esta operación."
    );
  }
}

function assertAuthenticated(request: CallableRequest): void {
  if (IS_EMULATOR && !request.auth) return;
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "No autenticado.");
  }
  // Art. 10 LOPDP: consent_signed requerido para cualquier operación de datos.
  if (!request.auth.token["consent_signed"]) {
    throw new HttpsError(
      "permission-denied",
      "Consentimiento del tutor legal no firmado. Completa el proceso de onboarding."
    );
  }
}

async function assertAdminOrSelf(request: CallableRequest, targetUid: string): Promise<void> {
  if (IS_EMULATOR && !request.auth) return;
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "No autenticado.");
  }
  
  const auth    = resolveAuth(request);
  const isSelf  = auth.uid === targetUid;
  
  const userDoc = await db.collection("users").doc(auth.uid).get();
  const isAdmin = userDoc.exists && userDoc.data()?.role === "admin";
  
  if (!isAdmin) {
    if (!request.auth.token["consent_signed"]) {
      throw new HttpsError(
        "permission-denied",
        "Consentimiento del tutor legal no firmado. Completa el proceso de onboarding."
      );
    }
  }
  
  if (!isAdmin && !isSelf) {
    throw new HttpsError("permission-denied", "Operación no autorizada.");
  }
}

// =============================================================================
// SECCIÓN 5: HELPERS
// =============================================================================

/** Parsea y valida el CSV. Retorna registros válidos y conteo de fallidos. */
function parseAndValidateCsv(csvString: string): {
  valid: Array<{
    rowNumber: number;
    name: string; dni: string; email: string;
    phone: string; team: string; consentDate: string;
  }>;
  failed: number;
} {
  const EMAIL_REGEX = /^[^@]+@[^@]+\.[^@]+/;
  const DATE_REGEX  = /^\d{4}-\d{2}-\d{2}$/;

  const clean = csvString
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/﻿/g, "");

  const lines = clean.split("\n").filter((l) => l.trim());
  if (lines.length < 2) return { valid: [], failed: 0 };

  const headerLine = lines[0].toLowerCase();
  const sep = headerLine.includes(";") &&
    headerLine.split(";").length > headerLine.split(",").length ? ";" : ",";

  const headers = lines[0].split(sep).map((h) =>
    h.toLowerCase().replace(/﻿/g, "").trim()
  );

  const idx = (matchers: string[]): number =>
    headers.findIndex((h) => matchers.some((m) => h.includes(m)));

  const nameIdx    = idx(["full_name", "nombre"]);
  const dniIdx     = idx(["dni"]);
  const emailIdx   = idx(["email", "correo"]);
  const phoneIdx   = idx(["phone", "telefono"]);
  const teamIdx    = idx(["team", "categor"]);
  const consentIdx = idx(["consent_date", "consentimiento"]);

  if (nameIdx === -1 || dniIdx === -1 || consentIdx === -1) {
    throw new HttpsError(
      "invalid-argument",
      `Cabecera CSV inválida. Detectadas: ${headers.join(", ")}`
    );
  }

  const cell = (row: string[], i: number) =>
    i >= 0 && i < row.length ? row[i].trim() : "";

  const valid: ReturnType<typeof parseAndValidateCsv>["valid"] = [];
  let failed = 0;

  for (let i = 1; i < lines.length; i++) {
    const row = lines[i].split(sep);
    if (row.join("").trim() === "") continue;

    const name        = cell(row, nameIdx);
    const dni         = cell(row, dniIdx);
    const email       = cell(row, emailIdx);
    const phone       = cell(row, phoneIdx);
    const team        = teamIdx >= 0 ? cell(row, teamIdx) : "Sin Categoría";
    const consentDate = cell(row, consentIdx);

    // Defense in depth — re-validación completa en servidor.
    if (!consentDate || !DATE_REGEX.test(consentDate)) { failed++; continue; }
    if (!dni)                                           { failed++; continue; }
    if (email && !EMAIL_REGEX.test(email))              { failed++; continue; }

    valid.push({ rowNumber: i + 1, name, dni, email, phone, team, consentDate });
  }

  return { valid, failed };
}

/**
 * Verifica duplicados de DNI usando batched 'in' queries.
 * Complejidad: O(N/30) lecturas vs O(N) individual — crítico para ingestas grandes.
 */
async function fetchExistingDnis(dnis: string[]): Promise<Set<string>> {
  const existingDnis = new Set<string>();
  // Ciframos los DNIs de la consulta para buscar coincidencias deterministas
  const encryptedDnis = dnis.map(encryptData);
  
  for (let i = 0; i < encryptedDnis.length; i += FIRESTORE_IN_LIMIT) {
    const chunk = encryptedDnis.slice(i, i + FIRESTORE_IN_LIMIT);
    const snap  = await db.collectionGroup("sensitive_data")
      .where("dni", "in", chunk).get();
    for (const doc of snap.docs) {
      const d = (doc.data() as Record<string, unknown>)["dni"] as string | undefined;
      if (d) existingDnis.add(d);
    }
  }
  return existingDnis;
}

/**
 * Escribe en audit_logs con Admin SDK (bypasea allow write: if false de las reglas).
 * Retorna el document ID para incluirlo en respuestas Hive como comprobante legal.
 * Art. 37 LOPDP: timestamps generados en servidor, inmutables desde el cliente.
 */
async function writeAuditLog(
  action:      string,
  performedBy: string,
  metadata:    Record<string, unknown>
): Promise<string> {
  const ref = await db.collection("audit_logs").add({
    action,
    performedBy,
    ...metadata,
    timestamp: FieldValue.serverTimestamp(),
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

export const processBulkIngestion = onCall<IngestionRequest>(
  { region: "us-central1", timeoutSeconds: 300, memory: "512MiB" as const },
  async (request: CallableRequest<IngestionRequest>) => {
    await assertAdmin(request);

    const { csv, institutionId } = request.data;
    if (!csv || !institutionId) {
      throw new HttpsError("invalid-argument", "csv e institutionId son requeridos.");
    }

    const executedAtMs = Date.now();
    const adminId      = resolveAuth(request).uid;

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
      } satisfies IngestionSummaryHive;
    }

    // ── Paso 2: Deduplicación forense por DNI cifrado (batched 'in') ──────────────
    const allDnis      = candidates.map((r) => r.dni);
    const existingDnis = await fetchExistingDnis(allDnis);
    const toWrite      = candidates.filter((r) => !existingDnis.has(encryptData(r.dni)));
    const duplicates   = candidates.length - toWrite.length;
    const totalFailed  = formatFailed + duplicates;

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
          full_name:          record.name,
          teamOrCategory:     record.team,
          paymentStatus:      "Pago Pendiente",
          status:             "Inactivo",
          photoUrl:           "",
          // Art. 26 LOPDP: Timestamp verificado en servidor, no interpolable.
          consent_timestamp: Timestamp.fromDate(
            new Date(`${record.consentDate}T00:00:00Z`)
          ),
          createdAt: FieldValue.serverTimestamp(),
        });

        // Subcolección /private — datos sensibles LOPDP.
        // Solo Admin SDK puede escribir aquí (allow write: if false en cliente).
        batch.set(
          athleteRef.collection("private").doc("sensitive_data"),
          { 
            dni: encryptData(record.dni), 
            email: encryptData(record.email), 
            phone: encryptData(record.phone) 
          }
        );
      }

      await batch.commit();
    }

    // ── Paso 4: Registro en audit_logs ────────────────────────────────────
    await writeAuditLog("BULK_INGESTION_COMPLETED", adminId, {
      institutionId,
      total:      candidates.length + formatFailed,
      valid:      toWrite.length,
      failed:     totalFailed,
      duplicates,
      batchCount,
    });

    // ── Respuesta Hive-nativa (@HiveType typeId: 10) ───────────────────────
    return {
      institutionId,
      total:        candidates.length + formatFailed,
      valid:        toWrite.length,
      failed:       totalFailed,
      duplicates,
      batchCount,
      executedAtMs, // Unix ms — Hive int nativo
      adminId,
    } satisfies IngestionSummaryHive;
  }
);

// =============================================================================
// SECCIÓN 7: FUNCIÓN 2 — logSensitiveAccess
//
// Callable desde AdminIngestionController.logDniReveal() en Flutter.
// Retorna AuditLogEntryHive (@HiveType typeId: 11) — cacheable para auditoría offline.
//
// El cliente Flutter NUNCA escribe en audit_logs directamente.
// Art. 37 LOPDP: log inalterable, timestamp de servidor, con identidad del admin.
// =============================================================================

export const logSensitiveAccess = onCall<LogAccessRequest>(
  { region: "us-central1" },
  async (request: CallableRequest<LogAccessRequest>) => {
    await assertAdmin(request);

    const { athleteId, action } = request.data;
    if (!athleteId || !action) {
      throw new HttpsError("invalid-argument", "athleteId y action son requeridos.");
    }

    const { uid: adminId, token } = resolveAuth(request);
    const adminEmail   = (token["email"] as string | undefined) ?? "";
    const institutionId = (token["institutionId"] as string | undefined) ?? "";
    const timestampMs  = Date.now();

    // Escribe en audit_logs y obtiene el document ID como comprobante legal.
    const logId = await writeAuditLog(action, adminId, {
      athleteId, adminEmail, institutionId,
    });

    // ── Respuesta Hive-nativa (@HiveType typeId: 11) ───────────────────────
    // Flutter cachea esta entrada en Hive para auditoría offline y reporte LOPDP.
    return {
      logId,       // ID del documento Firestore — prueba forense de la operación
      action,
      athleteId,
      adminId,
      adminEmail,
      institutionId,
      timestampMs,  // Unix ms — Hive int nativo
    } satisfies AuditLogEntryHive;
  }
);

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

export const requestAthleteErasure = onCall<ErasureRequest>(
  { region: "us-central1", timeoutSeconds: 120 },
  async (request): Promise<ErasureReceiptHive> => {
    const { uid } = request.data;
    if (!uid) throw new HttpsError("invalid-argument", "uid es requerido.");

    await assertAdminOrSelf(request, uid);

    const callerId      = resolveAuth(request).uid;
    const isSelfErasure = callerId === uid;
    const erasureType   = isSelfErasure ? "SELF_ERASURE" : "ADMIN_ERASURE";

    // ── Paso 1: Verifica existencia y captura metadata pre-borrado ─────────
    const athleteRef  = db.collection("athletes").doc(uid);
    const athleteSnap = await athleteRef.get();

    if (!athleteSnap.exists) {
      throw new HttpsError("not-found", `Atleta ${uid} no encontrado.`);
    }

    const institutionId = (athleteSnap.data()?.["ownerInstitutionId"] as string) ?? "";
    const athleteName   = (athleteSnap.data()?.["full_name"] as string) ?? "Desconocido";

    // ── Paso 2: Audit log INICIADO — antes de borrar (Art. 37 LOPDP) ──────
    await writeAuditLog(`${erasureType}_INITIATED`, callerId, {
      targetUid: uid, athleteName, institutionId,
    });

    // ── Paso 3: Borrado recursivo — raíz + todas las subcolecciones ────────
    // recursiveDelete() maneja /private, /sport_details, /historial_entrenamientos.
    await db.recursiveDelete(athleteRef);

    // ── Paso 4: Revocación de refresh tokens ──────────────────────────────
    // Invalida sesiones activas en cualquier dispositivo.
    try { await admin.auth().revokeRefreshTokens(uid); } catch { /* ya expirado */ }

    // ── Paso 5: Borrado de cuenta Auth (solo admin-erasure) ───────────────
    // En self-erasure: el cliente Flutter llama user.delete() tras este retorno.
    if (!isSelfErasure) {
      try { await admin.auth().deleteUser(uid); } catch { /* usuario ya eliminado */ }
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
      receiptId,    // ID del audit_log de confirmación — prueba forense
      targetUid: uid,
      erasureType,
      performedBy: callerId,
      institutionId,
      completedAtMs, // Unix ms — Hive int nativo
    } satisfies ErasureReceiptHive;
  }
);

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

export const syncAccessLog = onCall<SyncAccessLogRequest>(
  { region: "us-central1" },
  async (request): Promise<SyncAccessLogResponse> => {
    assertAuthenticated(request);

    const { logs } = request.data;
    if (!Array.isArray(logs) || logs.length === 0) {
      throw new HttpsError("invalid-argument", "logs debe ser un array no vacío.");
    }
    // Límite de seguridad: máx 100 logs por llamada para evitar abuso.
    if (logs.length > 100) {
      throw new HttpsError("invalid-argument", "Máximo 100 logs por sincronización.");
    }

    const serverMs = Date.now();
    const batch    = db.batch();

    for (const log of logs) {
      if (!log.athleteId || !log.eventType) continue;
      const docRef = db.collection("access_logs").doc();
      batch.set(docRef, {
        athleteId:    log.athleteId,
        scannedByUid: log.scannedByUid,
        eventType:    log.eventType,    // 'ENTRY' | 'EXIT'
        locationId:   log.locationId ?? "",
        clientMs:     log.clientMs,     // preservado para auditoría de latencia
        // El timestamp oficial es el del servidor — no manipulable desde el cliente.
        timestamp: FieldValue.serverTimestamp(),
        syncedAt:  FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    return { syncedCount: logs.length, serverMs } satisfies SyncAccessLogResponse;
  }
);

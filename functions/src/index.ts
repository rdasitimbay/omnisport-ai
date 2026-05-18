import * as admin from "firebase-admin";
import { Timestamp, FieldValue } from "firebase-admin/firestore";
import * as crypto from "crypto";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";

// =============================================================================
// SECCIÓN 0-A: EMULATOR BRIDGE
// IS_EMULATOR se evalúa en cold-start. FUNCTIONS_EMULATOR lo inyecta el emulador
// automáticamente; nunca está presente en Cloud Functions de producción.
// =============================================================================
const IS_EMULATOR = process.env["FUNCTIONS_EMULATOR"] === "true";

// =============================================================================
// SECCIÓN 0-B: SECRET MANAGER BINDING
//
// En PRODUCCIÓN: el runtime de Cloud Functions v2 inyecta MASTER_AES_KEY desde
// GCP Secret Manager justo antes de cada invocación. El valor NUNCA aparece en
// process.env durante el cold-start ni es accesible para scripts de terceros que
// se ejecuten en la fase de inicialización del módulo.
//
// En EMULADOR: getMasterKey() devuelve la llave de desarrollo sin llamar a
// _masterKeySecret.value(), por lo que no se requiere Secret Manager local.
//
// EGRESS PERMITIDO (solo dominios oficiales de Google):
//   • firestore.googleapis.com   — operaciones de base de datos
//   • fcm.googleapis.com         — notificaciones push (FCM)
//   • secretmanager.googleapis.com — lectura de secretos en producción
//   • oauth2.googleapis.com      — autenticación de service account
// Cualquier llamada HTTP saliente fuera de estos dominios es un indicador de
// compromiso (IOC) y debe generar una alerta en Cloud Monitoring.
// =============================================================================
const _masterKeySecret = defineSecret("MASTER_AES_KEY");

function getMasterKey(): string {
  if (IS_EMULATOR) return "dev-key-omnisport-ai-2026-sprint-3";
  const key = _masterKeySecret.value();
  if (!key) {
    throw new Error("CRITICAL: MASTER_AES_KEY no se pudo recuperar desde Secret Manager.");
  }
  return key;
}

// Cachea la llave derivada por warm instance — idempotente y thread-safe en V8.
let _cachedEncryptionKey: Buffer | null = null;
function getEncryptionKey(): Buffer {
  if (!_cachedEncryptionKey) {
    _cachedEncryptionKey = crypto.createHash("sha256").update(getMasterKey()).digest();
  }
  return _cachedEncryptionKey;
}

// [FIX C-1] NO existe STATIC_IV. Cada cifrado genera su propio IV aleatorio (16 bytes).
// Para búsquedas deterministas se usa hmacForSearch(), nunca encryptData().

/**
 * HMAC-SHA256 determinista — usar EXCLUSIVAMENTE para índices de búsqueda/deduplicación.
 * Es una función de una sola vía: no reversible. Normaliza a mayúsculas antes de hashear
 * para que "1712345678" y "1712345678 " produzcan el mismo hash.
 */
export function hmacForSearch(text: string): string {
  if (!text) return text;
  return crypto
    .createHmac("sha256", getEncryptionKey())
    .update(text.trim().toUpperCase())
    .digest("hex");
}

/**
 * Cifra texto con AES-256-CBC usando un IV aleatorio por cada llamada.
 * Formato de salida: base64(iv) + ":" + base64(ciphertext)
 * El IV se almacena junto al ciphertext y es necesario para descifrar.
 */
export function encryptData(text: string): string {
  if (!text) return text;
  const iv      = crypto.randomBytes(16);
  const cipher  = crypto.createCipheriv("aes-256-cbc", getEncryptionKey(), iv);
  let encrypted = cipher.update(text, "utf8", "base64");
  encrypted    += cipher.final("base64");
  return `${iv.toString("base64")}:${encrypted}`;
}

/**
 * Descifra texto cifrado por encryptData().
 * Espera el formato: base64(iv) + ":" + base64(ciphertext)
 */
export function decryptData(encryptedText: string): string {
  if (!encryptedText || !encryptedText.includes(":")) return encryptedText;
  const colonIdx  = encryptedText.indexOf(":");
  const iv        = Buffer.from(encryptedText.slice(0, colonIdx), "base64");
  const ciphertext = encryptedText.slice(colonIdx + 1);
  const decipher  = crypto.createDecipheriv("aes-256-cbc", getEncryptionKey(), iv);
  let decrypted   = decipher.update(ciphertext, "base64", "utf8");
  decrypted      += decipher.final("utf8");
  return decrypted;
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
// SECCIÓN 4: GUARDS DE AUTENTICACIÓN
// IS_EMULATOR declarado en Sección 0-A (top-of-file).
// =============================================================================

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

// Validación de rol en servidor delegada a Firestore (migración desde Custom Claims).
async function assertAdmin(request: CallableRequest): Promise<void> {
  if (IS_EMULATOR && !request.auth) return;
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "No autenticado.");
  }
  const callerUid = resolveAuth(request).uid;
  const adminSnap = await db.collection("users").doc(callerUid).get();
  if (adminSnap.data()?.["role"] !== "admin") {
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

// [FIX A-1] Migrado a validación en Firestore para alinearse con el modelo actual.
async function assertAdminOrSelf(request: CallableRequest, targetUid: string): Promise<void> {
  assertAuthenticated(request);
  const auth    = resolveAuth(request);
  const isSelf  = auth.uid === targetUid;
  
  let isAdmin = false;
  const adminSnap = await db.collection("users").doc(auth.uid).get();
  if (adminSnap.data()?.["role"] === "admin") {
    isAdmin = true;
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
// [FIX C-1] Deduplicación por HMAC, no por ciphertext.
// hmacForSearch() es determinista y consultable; encryptData() usa IV aleatorio y NO lo es.
// El campo de búsqueda en Firestore es 'dni_hash', no 'dni'.
async function fetchExistingDnis(dnis: string[]): Promise<Set<string>> {
  const existingHashes = new Set<string>();
  const hashedDnis     = dnis.map(hmacForSearch);

  for (let i = 0; i < hashedDnis.length; i += FIRESTORE_IN_LIMIT) {
    const chunk = hashedDnis.slice(i, i + FIRESTORE_IN_LIMIT);
    const snap  = await db.collectionGroup("sensitive_data")
      .where("dni_hash", "in", chunk).get();
    for (const doc of snap.docs) {
      const h = (doc.data() as Record<string, unknown>)["dni_hash"] as string | undefined;
      if (h) existingHashes.add(h);
    }
  }
  return existingHashes;
}

/**
 * Extrae la IP del cliente de un CallableRequest v2.
 * Cloud Run coloca la IP real en x-forwarded-for cuando el cliente llega
 * a través del load balancer de Google; .ip es el balanceador mismo.
 */
function extractIp(request: CallableRequest<unknown>): string {
  const raw = request.rawRequest as {
    ip?: string;
    headers?: Record<string, string | string[] | undefined>;
  } | undefined;
  const forwarded = raw?.headers?.["x-forwarded-for"];
  if (forwarded) {
    const first = Array.isArray(forwarded) ? forwarded[0] : forwarded;
    return first.split(",")[0].trim();
  }
  return raw?.ip ?? "unknown";
}

/**
 * Escribe en audit_logs con Admin SDK (bypasea allow write: if false de las reglas).
 * Retorna el document ID para incluirlo en respuestas Hive como comprobante legal.
 * Art. 37 LOPDP: timestamps generados en servidor, inmutables desde el cliente.
 * sourceIp: dirección IP del solicitante para trazabilidad forense (Art. 37).
 */
async function writeAuditLog(
  action:      string,
  performedBy: string,
  metadata:    Record<string, unknown>,
  sourceIp?:   string
): Promise<string> {
  const ref = await db.collection("audit_logs").add({
    action,
    performedBy,
    ...metadata,
    sourceIp:  sourceIp ?? null,
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
  { region: "us-central1", timeoutSeconds: 300, memory: "512MiB" as const, secrets: [_masterKeySecret] },
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
      }, extractIp(request));
      return {
        institutionId, total: formatFailed, valid: 0,
        failed: formatFailed, duplicates: 0, batchCount: 0,
        executedAtMs, adminId,
      } satisfies IngestionSummaryHive;
    }

    // ── Paso 2: Deduplicación forense por HMAC de DNI (batched 'in') ────────
    // [FIX C-1] fetchExistingDnis retorna Set<hmac>; comparamos con hmacForSearch().
    const allDnis      = candidates.map((r) => r.dni);
    const existingDnis = await fetchExistingDnis(allDnis);
    const toWrite      = candidates.filter((r) => !existingDnis.has(hmacForSearch(r.dni)));
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
        // [FIX C-1] dni_hash: HMAC determinista para consultas de deduplicación.
        //           dni/email/phone: AES con IV aleatorio por registro para recuperación.
        batch.set(
          athleteRef.collection("private").doc("sensitive_data"),
          {
            dni_hash:   hmacForSearch(record.dni),   // índice HMAC para deduplicación
            email_hash: hmacForSearch(record.email), // índice HMAC para auto-link de cuenta
            dni:        encryptData(record.dni),      // AES IV aleatorio — recuperable
            email:      encryptData(record.email),
            phone:      encryptData(record.phone),
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
    }, extractIp(request));

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
  { region: "us-central1", secrets: [_masterKeySecret] },
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
    }, extractIp(request));

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
  { region: "us-central1", timeoutSeconds: 120, secrets: [_masterKeySecret] },
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
    }, extractIp(request));

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
    }, extractIp(request));

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
  { region: "us-central1", secrets: [_masterKeySecret] },
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

// ============================================================================
// MOTOR DE TOKENS DINÁMICOS (SPRINT 4)
// ============================================================================

// TTL oficial del token QR y tolerancia de reloj (red lenta, relojes desincronizados)
const TOKEN_TTL_MS       = 45_000;
const TOKEN_CLOCK_SKEW_MS =  5_000;

/**
 * generateAttendanceToken
 * [FIX C-3] Solo atletas y representantes legales pueden generar tokens QR.
 * Admin/coach VALIDAN — si pudieran también generar, un coach podría registrar
 * asistencia de un atleta ausente físicamente sin ningún control.
 * Campo canónico para la relación padre-hijo: 'parentUid' (un solo nombre).
 */
export const generateAttendanceToken = onCall(
  { enforceAppCheck: false, secrets: [_masterKeySecret] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Debe iniciar sesión.");
    }

    const callerUid  = request.auth.uid;

    // RBAC via Firestore — consistente con la migración global desde Claims.
    const callerDoc  = await db.collection("users").doc(callerUid).get();
    const callerRole = callerDoc.data()?.["role"] as string | undefined;

    // Guard de rol: solo 'athlete' y 'parent' generan tokens.
    if (callerRole !== "athlete" && callerRole !== "parent") {
      throw new HttpsError(
        "permission-denied",
        "Solo el propio atleta o su representante legal puede generar un token QR."
      );
    }

    const requestedAthleteUid = (request.data.athleteUid as string | undefined) ?? callerUid;

    if (callerUid !== requestedAthleteUid) {
      // Un atleta nunca puede generar token para otro atleta.
      if (callerRole !== "parent") {
        throw new HttpsError(
          "permission-denied",
          "Un atleta solo puede generar su propio token QR."
        );
      }

      const athleteDoc = await db.collection("athletes").doc(requestedAthleteUid).get();
      if (!athleteDoc.exists) {
        throw new HttpsError("not-found", "Deportista no encontrado.");
      }

      // [FIX C-3] Campo canónico único: 'parentUid'. Elimina la ambigüedad de
      // parent_uid / representativeUid / parentUid que permitía bypass del check.
      const canonicalParentUid = athleteDoc.data()?.parentUid as string | undefined;
      if (canonicalParentUid !== callerUid) {
        throw new HttpsError(
          "permission-denied",
          "Acceso denegado: no es el representante legal registrado de este deportista."
        );
      }
    }

    const timestamp  = Date.now();
    const dataToHash = `${requestedAthleteUid}:${timestamp}`;
    const hash       = crypto.createHmac("sha256", getMasterKey()).update(dataToHash).digest("hex");

    return { token: `${requestedAthleteUid}:${timestamp}:${hash}` };
  }
);

/**
 * validateAttendanceToken
 * [FIX A-1] RBAC via Custom Claims (no Firestore read).
 * [FIX A-2] Comparación de HMAC con timingSafeEqual (anti timing-attack).
 * [FIX C-2] Anti-replay: transacción Firestore consume el token atómicamente.
 * [FIX M-1] Verificación de institución dentro de la misma transacción.
 */
export const validateAttendanceToken = onCall(
  { enforceAppCheck: false, secrets: [_masterKeySecret] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Debe iniciar sesión.");
    }

    // 1. RBAC via Firestore — consistente con assertAdmin (migración desde Claims).
    const callerUid = request.auth.uid;
    const scannerDoc = await db.collection("users").doc(callerUid).get();
    const scannerRole = scannerDoc.data()?.["role"] as string | undefined;
    const scannerInstitutionId = scannerDoc.data()?.["institutionId"] as string | undefined;
    if (scannerRole !== "admin" && scannerRole !== "coach") {
      throw new HttpsError("permission-denied", "Solo personal autorizado puede escanear.");
    }

    const token    = request.data.token as string | undefined;
    const action   = (request.data.action  as string | undefined) ?? "ingreso";
    const location = (request.data.location as string | null | undefined) ?? null;

    if (!token || typeof token !== "string") {
      throw new HttpsError("invalid-argument", "Token faltante o inválido.");
    }

    const parts = token.split(":");
    if (parts.length !== 3) {
      throw new HttpsError("invalid-argument", "Estructura del token corrupta.");
    }

    const [athleteUid, timestampStr, providedHash] = parts;
    const tokenTimestamp = parseInt(timestampStr, 10);

    if (isNaN(tokenTimestamp) || !athleteUid) {
      throw new HttpsError("invalid-argument", "Timestamp o UID inválido.");
    }

    // 2. Validar expiración antes de cualquier operación costosa.
    const now = Date.now();
    if (now - tokenTimestamp > TOKEN_TTL_MS + TOKEN_CLOCK_SKEW_MS) {
      throw new HttpsError("deadline-exceeded", "El token QR ha expirado.");
    }
    // Rechazar timestamps futuros — previene pre-generación de tokens.
    if (tokenTimestamp > now + TOKEN_CLOCK_SKEW_MS) {
      throw new HttpsError("invalid-argument", "Timestamp del token inválido.");
    }

    // 3. [FIX A-2] Validación criptográfica con comparación segura anti-timing-attack.
    const dataToHash      = `${athleteUid}:${tokenTimestamp}`;
    const expectedHash    = crypto.createHmac("sha256", getMasterKey()).update(dataToHash).digest("hex");
    const providedHashBuf = Buffer.from(providedHash,  "hex");
    const expectedHashBuf = Buffer.from(expectedHash,  "hex");
    const hashValid =
      providedHashBuf.length === expectedHashBuf.length &&
      crypto.timingSafeEqual(providedHashBuf, expectedHashBuf);

    if (!hashValid) {
      throw new HttpsError("unauthenticated", "Firma de token inválida. Posible falsificación.");
    }

    // 4. [FIX C-2 + M-1] Transacción atómica: anti-replay + check de institución
    //    en una sola operación. El ID del doc es HMAC del token completo — único y opaco.
    const tokenDocId  = crypto.createHmac("sha256", getMasterKey()).update(token).digest("hex");
    const tokenDocRef = db.collection("used_tokens").doc(tokenDocId);
    const logRef      = db.collection("attendance_logs").doc();
    let   athleteData: FirebaseFirestore.DocumentData | undefined;

    try {
      await db.runTransaction(async (tx) => {
        const [tokenSnap, athleteSnap] = await Promise.all([
          tx.get(tokenDocRef),
          tx.get(db.collection("athletes").doc(athleteUid)),
        ]);

        // [FIX C-2] Rechazar token ya consumido.
        if (tokenSnap.exists) {
          throw new HttpsError("already-exists", "Token QR ya utilizado. Solicita uno nuevo.");
        }

        if (!athleteSnap.exists) {
          throw new HttpsError("not-found", "Atleta no encontrado en el sistema.");
        }

        // [FIX M-1] Verificar frontera institucional.
        const athleteInstitutionId = athleteSnap.data()?.ownerInstitutionId as string | undefined;
        if (scannerInstitutionId && athleteInstitutionId &&
            scannerInstitutionId !== athleteInstitutionId) {
          throw new HttpsError(
            "permission-denied",
            "El escáner no pertenece a la misma institución que el atleta."
          );
        }

        athleteData = athleteSnap.data();

        // Marcar token como consumido y escribir log de asistencia — ambos atómicos.
        tx.set(tokenDocRef, {
          usedAt:    FieldValue.serverTimestamp(),
          usedBy:    request.auth!.uid,
          athleteUid,
          expiresAt: Timestamp.fromMillis(tokenTimestamp + TOKEN_TTL_MS + TOKEN_CLOCK_SKEW_MS),
        });
        tx.set(logRef, {
          athleteUid,
          scannedBy: request.auth!.uid,
          action,
          location,
          timestamp: FieldValue.serverTimestamp(),
          status:    "valid",
        });
      });
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      throw new HttpsError("internal", "Error al procesar el token.");
    }

    // 5. Notificación Push — fuera de la transacción para no bloquear el flujo de asistencia.
    try {
      if (athleteData) {
        const parentUid   = athleteData.parentUid as string | undefined;
        const athleteName = (athleteData.full_name  as string | undefined) ?? "El deportista";
        const sport       = (athleteData.teamOrCategory as string | undefined) ?? "su disciplina";

        if (parentUid) {
          const parentDoc = await db.collection("users").doc(parentUid).get();
          const fcmToken  = parentDoc.data()?.fcmToken as string | undefined;

          if (fcmToken) {
            const timeOptions: Intl.DateTimeFormatOptions = {
              timeZone: "America/Guayaquil", hour: "2-digit", minute: "2-digit",
            };
            const timeString = new Date().toLocaleTimeString("es-ES", timeOptions);

            const configDoc = await db.collection("app_config").doc("notification_templates").get();
            const templates: Record<string, string> = (configDoc.data() as Record<string, string>) ?? {
              entry_standard:    "¡Hola! {{name}} ha ingresado al entrenamiento de {{sport}} a las {{time}}.",
              exit_standard:     "{{name}} ha finalizado su sesión de {{sport}} de forma segura.",
              entry_motivational:"¡Día de acción! {{name}} ya está en la cancha de {{sport}}. ¡A darle con todo!",
              exit_motivational: "¡Excelente esfuerzo! {{name}} ha culminado su sesión de {{sport}}.",
            };

            const instId = (athleteData.ownerInstitutionId as string | undefined) ?? "default";
            let tone = "standard";
            if (instId !== "default") {
              const instConfig = await db
                .collection(`institutions/${instId}/configuration`).doc("notifications").get();
              if (instConfig.exists) tone = (instConfig.data()?.tone as string) ?? "standard";
            }

            const isEntry      = action === "ingreso";
            const templateKey  = isEntry ? `entry_${tone}` : `exit_${tone}`;
            const bodyTemplate = templates[templateKey] ??
              templates[isEntry ? "entry_standard" : "exit_standard"] ?? "";

            const body  = bodyTemplate
              .replace(/{{name}}/g,  athleteName)
              .replace(/{{sport}}/g, sport)
              .replace(/{{time}}/g,  timeString);
            const title = isEntry ? "Acceso Registrado" : "Salida Registrada";

            await admin.messaging().send({
              token: fcmToken,
              notification: { title, body },
              data: { action, athleteUid },
            });
          }
        }
      }
    } catch (e) {
      console.error("Error enviando notificación push:", e);
    }

    return {
      success: true,
      logId:   logRef.id,
      message: `Asistencia de ${action} registrada correctamente.`,
    };
  }
);

// =============================================================================
// SECCIÓN 10: FUNCIÓN 6 — broadcastEmergencyPush
//
// Triple-lock de seguridad para la operación de mayor impacto del sistema:
//   L-1. Autenticación: request.auth no nulo.
//   L-2. Firestore role check: users/{uid}.role === "admin" (fuente autoritativa).
//        _ensureUserProfile() escribe en Firestore; Custom Claims no están activos
//        hasta que se implemente el trigger de sincronización. Este check garantiza
//        acceso correcto antes de ese trigger.
//   L-3. Custom Claims consistency: si el claim "role" está presente en el JWT
//        debe coincidir con Firestore. Detecta tokens manipulados.
//
// Rate-limit POR INSTITUCIÓN — 5 min — transacción atómica evita doble emisión.
// institutionId se lee del perfil Firestore del admin (o del Custom Claim si existe).
//
// Sanitización: mensaje y título pasan por sanitizeForPush() antes de FCM.
//   Elimina: chars de control, unicode invisible, etiquetas HTML, URIs JS/data.
//
// Validación de destinatarios:
//   - role === "parent" exacto (Firestore query)
//   - fcmToken con longitud mínima FCM_TOKEN_MIN_LEN (tokens legítimos > 100 chars)
//   - Set<string> elimina duplicados antes del envío
//
// FCM: sendEachForMulticast en lotes de máx 500 tokens.
// Art. 37 LOPDP: cada broadcast (o intento fallido de destinatarios = 0)
// queda registrado en audit_logs con mensaje sanitizado y métricas.
// =============================================================================

const BROADCAST_COOLDOWN_MS = 5 * 60 * 1000; // 5 min por institución
const FCM_TOKEN_MIN_LEN     = 100;            // tokens FCM reales > 100 chars
const MSG_MAX_LEN            = 500;
const TITLE_MAX_LEN          = 100;

// Regex precompiladas — aplicadas en orden secuencial dentro de sanitizeForPush().
const _CTRL_CHARS  = /[\x00-\x1F\x7F-\x9F]/g;
const _ZERO_WIDTH  = /[​-‍⁠﻿]/g;
const _HTML_TAGS   = /<[^>]{0,500}>/g;
const _JS_PROTO    = /javascript\s*:/gi;
const _DATA_URI    = /data\s*:[^,]{0,100},/gi;
const _MULTI_SPC   = /[ \t]{2,}/g;

/**
 * Limpia texto antes de enviarlo como payload de FCM.
 * Protege contra: log-injection, unicode invisible, HTML-in-notification,
 * JS/data URIs en el campo data y overflow de longitud.
 */
function sanitizeForPush(raw: string, maxLen: number): string {
  return raw
    .replace(_CTRL_CHARS, " ")
    .replace(_ZERO_WIDTH, "")
    .replace(_HTML_TAGS,  "")
    .replace(_JS_PROTO,   "")
    .replace(_DATA_URI,   "")
    .replace(_MULTI_SPC,  " ")
    .trim()
    .slice(0, maxLen);
}

export const broadcastEmergencyPush = onCall(
  { region: "us-central1", timeoutSeconds: 120, memory: "256MiB" as const, secrets: [_masterKeySecret] },
  async (request) => {
    try {
    // ── L-1: Autenticación ─────────────────────────────────────────────────────
    if (!IS_EMULATOR && !request.auth) {
      throw new HttpsError("unauthenticated", "No autenticado.");
    }
    const callerUid = resolveAuth(request).uid;

    // ── L-2 + L-3: Verificación de rol — doble fuente ─────────────────────────
    let institutionId = "global";
    if (!IS_EMULATOR) {
      const adminSnap     = await db.collection("users").doc(callerUid).get();
      const firestoreRole = adminSnap.data()?.["role"] as string | undefined;

      if (firestoreRole !== "admin") {
        throw new HttpsError(
          "permission-denied",
          "Solo administradores pueden emitir alertas masivas."
        );
      }

      // L-3: si el JWT trae el claim "role", debe concordar con Firestore.
      // Un mismatch indica token manipulado o Custom Claims desincronizados.
      const claimsRole = request.auth?.token["role"] as string | undefined;
      if (claimsRole !== undefined && claimsRole !== "admin") {
        throw new HttpsError(
          "permission-denied",
          "Credenciales de rol inconsistentes. Cierra sesión y vuelve a autenticarte."
        );
      }

      // institutionId: Custom Claim tiene precedencia sobre Firestore.
      const claimsInst = request.auth?.token["institutionId"] as string | undefined;
      institutionId = claimsInst
        ?? (adminSnap.data()?.["institutionId"] as string | undefined)
        ?? "global";
    }

    // ── Sanitización de entrada ────────────────────────────────────────────────
    const message = sanitizeForPush(
      (request.data.message as string | undefined) ?? "", MSG_MAX_LEN
    );
    const title = sanitizeForPush(
      (request.data.title   as string | undefined) ?? "Aviso Importante", TITLE_MAX_LEN
    );

    if (!message) {
      throw new HttpsError("invalid-argument", "El mensaje no puede estar vacío.");
    }

    // ── Rate-limit atómico por institución ────────────────────────────────────
    // Ruta: system_config/rate_limits/{institutionId}
    // La transacción garantiza que dos admins concurrentes de la misma institución
    // no puedan pasar ambos el check y emitir doble alerta.
    const rateLimitRef = db.doc(`system_config/rate_limits/${institutionId}`);
    const now          = Date.now();

    await db.runTransaction(async (tx) => {
      const snap      = await tx.get(rateLimitRef);
      const lastMs    = (snap.data()?.["lastBroadcastMs"] as number | undefined) ?? 0;
      const elapsedMs = now - lastMs;

      if (elapsedMs < BROADCAST_COOLDOWN_MS) {
        const remainingSecs = Math.ceil((BROADCAST_COOLDOWN_MS - elapsedMs) / 1000);
        const mins          = Math.floor(remainingSecs / 60);
        const secs          = remainingSecs % 60;
        throw new HttpsError(
          "resource-exhausted",
          `Rate-limit activo para tu institución. Espera ${mins}m ${secs}s.`
        );
      }

      tx.set(rateLimitRef, {
        lastBroadcastMs: now,
        lastAdminId:     callerUid,
        institutionId,
      }, { merge: true });
    });

    // ── Recoger FCM tokens válidos de representantes ───────────────────────────
    // Filtro Firestore: role === "parent" (campo indexado, query segura).
    // Validación adicional: longitud mínima de token FCM (tokens reales > 100 chars).
    // Set<string> elimina tokens duplicados antes del envío.
    const usersSnap = await db.collection("users")
      .where("role", "==", "parent")
      .get();

    const tokenSet = new Set<string>();
    for (const doc of usersSnap.docs) {
      const t = doc.data()["fcmToken"];
      if (typeof t === "string" && t.length >= FCM_TOKEN_MIN_LEN) {
        tokenSet.add(t);
      }
    }
    const tokens = [...tokenSet];

    if (tokens.length === 0) {
      await writeAuditLog("EMERGENCY_BROADCAST_NO_RECIPIENTS", callerUid, {
        title, message, institutionId, sentAtMs: now,
      }, extractIp(request));
      return {
        sent: 0, failed: 0, recipients: 0,
        warning: "No hay representantes con FCM token válido registrado.",
      };
    }

    // ── Envío por lotes de 500 (límite de sendEachForMulticast) ────────────────
    let totalSent   = 0;
    let totalFailed = 0;

    for (let i = 0; i < tokens.length; i += 500) {
      const chunk    = tokens.slice(i, i + 500);
      const response = await admin.messaging().sendEachForMulticast({
        tokens: chunk,
        notification: { title, body: message },
        data:    { type: "emergency_broadcast", sentAtMs: String(now) },
        android: { priority: "high" },
        apns:    { payload: { aps: { contentAvailable: true, sound: "default" } } },
      });
      totalSent   += response.successCount;
      totalFailed += response.failureCount;
    }

    // ── Audit log LOPDP Art. 37 ───────────────────────────────────────────────
    await writeAuditLog("EMERGENCY_BROADCAST_SENT", callerUid, {
      title, message, institutionId,
      totalSent, totalFailed,
      recipientCount: tokens.length,
      sentAtMs: now,
    }, extractIp(request));

    return { sent: totalSent, failed: totalFailed, recipients: tokens.length };
    } catch (e: any) {
      console.error("ERROR CRÍTICO EN BROADCAST:", e);
      throw new HttpsError("internal", `Error del servidor: ${e.message || e}`);
    }
  }
);

// =============================================================================
// SECCIÓN 11: FUNCIÓN 7 — linkAthleteAccount
//
// Resuelve el vínculo entre el Auth UID del usuario y su documento de atleta.
// Problema: la ingesta masiva crea atletas con IDs auto-generados; el Auth UID
// del usuario no coincide con el ID del documento en /athletes.
//
// Flujo:
//   1. Extrae el email del JWT (request.auth.token.email).
//   2. Calcula HMAC del email (mismo algoritmo que la ingesta).
//   3. Consulta collectionGroup("sensitive_data") por email_hash.
//   4. Si encuentra match, guarda athleteDocId en users/{uid} y lo retorna.
//   5. Si no hay match, retorna { athleteDocId: null } — perfil pendiente de ingesta.
//
// Idempotente: si ya está vinculado, retorna el valor guardado sin queries extra.
// =============================================================================
// =============================================================================
// SECCIÓN 12: PASAPORTE DEPORTIVO DIGITAL (SMART ID)
//
// generateSmartId — emite un JWT firmado con HMAC-SHA256 válido 30 días.
//   Payload público: uid, categoría, institución, elegibilidad, estado médico.
//   Payload privado (omitido en verifySmartId): fullName (LOPDP Art. 5 — minimización).
//
// verifySmartId — valida firma + expiración y retorna vista árbitro (ofuscada):
//   Solo expone isEligible, medicalOk, paymentOk, photoUrl, category, smartIdNum.
//   fullName está deliberadamente ausente para proteger identidad ante árbitros.
//
// Elegibilidad = paymentStatus=="Al Día" && status=="Acceso Autorizado"
// Médico OK    = lastMedicalReview existe y tiene menos de 6 meses.
// =============================================================================

interface SmartIdPayload {
  uid: string; fullName: string; category: string; institutionId: string;
  isEligible: boolean; medicalOk: boolean; paymentOk: boolean;
  photoUrl: string; smartIdNum: string; iat: number; exp: number;
}

function signSmartIdPayload(data: string): string {
  return crypto.createHmac("sha256", getEncryptionKey())
    .update(`SMART_ID_v1:${data}`).digest("base64url");
}

export const generateSmartId = onCall(
  { region: "us-central1", secrets: [_masterKeySecret] },
  async (request) => {
    assertAuthenticated(request);
    const callerUid  = resolveAuth(request).uid;
    const targetUid  = (request.data["athleteUid"] as string | undefined) ?? callerUid;

    if (targetUid !== callerUid) {
      const snap = await db.collection("users").doc(callerUid).get();
      if (snap.data()?.["role"] !== "admin") {
        throw new HttpsError("permission-denied", "Solo puedes generar tu propio pasaporte.");
      }
    }

    const athleteSnap = await db.collection("athletes").doc(targetUid).get();
    if (!athleteSnap.exists) throw new HttpsError("not-found", "Perfil de atleta no encontrado.");

    const d             = athleteSnap.data()!;
    const fullName      = (d["full_name"] ?? d["nombre_completo"] ?? "Atleta") as string;
    const category      = (d["teamOrCategory"] ?? "") as string;
    const institutionId = (d["ownerInstitutionId"] ?? d["institutionId"] ?? "") as string;
    const photoUrl      = (d["photoUrl"] ?? "") as string;
    const paymentOk     = (d["paymentStatus"] as string | undefined) === "Al Día";
    const statusOk      = (d["status"] as string | undefined) === "Acceso Autorizado";
    const lastMedical   = d["lastMedicalReview"] as Timestamp | null | undefined;
    const medicalOk     = !!lastMedical &&
      (Date.now() - lastMedical.toMillis()) < 180 * 24 * 60 * 60 * 1000;
    const isEligible    = paymentOk && statusOk;

    const instSlug    = institutionId.replace(/[^a-zA-Z0-9]/g, "").slice(0, 6).toUpperCase() || "OMNI";
    const uidSlug     = targetUid.replace(/[^a-zA-Z0-9]/g, "").slice(0, 8).toUpperCase();
    const smartIdNum  = `OS-${instSlug}-${uidSlug}`;

    const iat = Math.floor(Date.now() / 1000);
    const exp = iat + 30 * 24 * 3600;

    const payload: SmartIdPayload = {
      uid: targetUid, fullName, category, institutionId,
      isEligible, medicalOk, paymentOk, photoUrl, smartIdNum, iat, exp,
    };

    const header    = Buffer.from(JSON.stringify({ alg: "HS256", typ: "SMART_ID" })).toString("base64url");
    const body      = Buffer.from(JSON.stringify(payload)).toString("base64url");
    const signature = signSmartIdPayload(`${header}.${body}`);
    const token     = `${header}.${body}.${signature}`;

    await db.collection("athletes").doc(targetUid).update({
      smartIdNum,
      smartIdGeneratedAt:  FieldValue.serverTimestamp(),
      smartIdValidUntilMs: exp * 1000,
    });
    await writeAuditLog("SMART_ID_GENERATED", callerUid, { athleteUid: targetUid, smartIdNum, isEligible }, extractIp(request));

    return { token, smartIdNum, isEligible, medicalOk, paymentOk, expMs: exp * 1000 };
  }
);

export const verifySmartId = onCall(
  { region: "us-central1", secrets: [_masterKeySecret] },
  async (request) => {
    assertAuthenticated(request);
    const token = request.data["token"] as string | undefined;
    if (!token) throw new HttpsError("invalid-argument", "token requerido.");

    const parts = token.split(".");
    if (parts.length !== 3) throw new HttpsError("invalid-argument", "Token malformado.");

    const [header, body, sig] = parts;
    const expectedSig = signSmartIdPayload(`${header}.${body}`);

    let sigBuf: Buffer; let expBuf: Buffer;
    try {
      sigBuf = Buffer.from(sig, "base64url");
      expBuf = Buffer.from(expectedSig, "base64url");
    } catch {
      throw new HttpsError("invalid-argument", "Firma con formato inválido.");
    }
    if (sigBuf.length !== expBuf.length || !crypto.timingSafeEqual(sigBuf, expBuf)) {
      throw new HttpsError("permission-denied", "Firma de pasaporte inválida.");
    }

    const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8")) as SmartIdPayload;
    if (payload.exp < Math.floor(Date.now() / 1000)) {
      throw new HttpsError("deadline-exceeded", "Pasaporte expirado.");
    }

    await writeAuditLog("SMART_ID_VERIFIED", resolveAuth(request).uid, {
      smartIdNum: payload.smartIdNum, athleteUid: payload.uid, isEligible: payload.isEligible,
    }, extractIp(request));

    // fullName omitido deliberadamente — vista árbitro (LOPDP Art. 5 minimización).
    return {
      isEligible:  payload.isEligible,
      medicalOk:   payload.medicalOk,
      paymentOk:   payload.paymentOk,
      photoUrl:    payload.photoUrl,
      smartIdNum:  payload.smartIdNum,
      category:    payload.category,
      expMs:       payload.exp * 1000,
    };
  }
);

export const linkAthleteAccount = onCall(
  { region: "us-central1", secrets: [_masterKeySecret] },
  async (request) => {
    if (!IS_EMULATOR && !request.auth) {
      throw new HttpsError("unauthenticated", "No autenticado.");
    }

    const callerUid   = resolveAuth(request).uid;
    const callerEmail = (request.auth?.token["email"] as string | undefined) ?? "";

    // Idempotencia: si ya está vinculado, no re-consultar Firestore.
    const userRef  = db.collection("users").doc(callerUid);
    const userSnap = await userRef.get();
    const existing = userSnap.data()?.["athleteDocId"] as string | undefined;
    if (existing) return { athleteDocId: existing };

    if (!callerEmail) return { athleteDocId: null };

    // Buscar atleta por email_hash en todos los documentos sensitive_data.
    const emailHash = hmacForSearch(callerEmail);
    const snap      = await db.collectionGroup("sensitive_data")
      .where("email_hash", "==", emailHash)
      .limit(1)
      .get();

    if (snap.empty) return { athleteDocId: null };

    // Ruta: athletes/{athleteId}/private/sensitive_data
    // ref.parent = colección "private"; ref.parent.parent = doc athletes/{athleteId}
    const athleteDocId = snap.docs[0].ref.parent.parent?.id ?? null;
    if (!athleteDocId) return { athleteDocId: null };

    // Guardar vínculo en el perfil del usuario — una sola escritura.
    await userRef.update({ athleteDocId, linkedAtMs: FieldValue.serverTimestamp() });

    return { athleteDocId };
  }
);

// =============================================================================
// SECCIÓN 13: FUNCIÓN — triggerSosAlert (Módulo Médico S.O.S)
//
// Alerta de emergencia de lesión con notificación inmediata a padres.
// Captura GPS, tipo de lesión, y devuelve protocolo de triaje instantáneo.
//
// Seguridad:
//   L-1. Autenticación obligatoria.
//   L-2. Rate-limit: 1 alerta cada 2 minutos por atleta (anti-spam).
//   L-3. Rol: coach, admin, o el propio atleta/padre.
// =============================================================================

// Protocolos de triaje según categoría de lesión — basado en guías ATLS.
const TRIAGE_PROTOCOLS: Record<string, {
  severity: "green" | "yellow" | "red";
  title: string;
  steps: string[];
  callEmergency: boolean;
}> = {
  "contusion": {
    severity: "green",
    title: "Contusión / Golpe Menor",
    steps: [
      "Aplicar hielo envuelto en tela por 15-20 minutos.",
      "Elevar la zona afectada si es posible.",
      "Observar signos de hinchazón excesiva.",
      "No aplicar calor en las primeras 48 horas.",
      "Si el dolor persiste más de 30 min, derivar a médico.",
    ],
    callEmergency: false,
  },
  "esguince": {
    severity: "yellow",
    title: "Esguince / Torcedura",
    steps: [
      "Detener la actividad INMEDIATAMENTE.",
      "Aplicar protocolo RICE: Reposo, Hielo, Compresión, Elevación.",
      "Inmovilizar la articulación con vendaje elástico.",
      "No apoyar peso sobre la extremidad afectada.",
      "Derivar a centro médico para radiografía.",
    ],
    callEmergency: false,
  },
  "fractura_sospecha": {
    severity: "red",
    title: "Sospecha de Fractura",
    steps: [
      "NO MOVER al atleta de la posición actual.",
      "Inmovilizar la zona con férula improvisada (tabla, cartón).",
      "Aplicar hielo SIN contacto directo con la piel.",
      "Monitorear signos vitales: pulso, respiración, color de piel.",
      "LLAMAR AL 911 / ECU-911 INMEDIATAMENTE.",
      "Registrar hora exacta del incidente.",
    ],
    callEmergency: true,
  },
  "golpe_cabeza": {
    severity: "red",
    title: "Traumatismo Craneoencefálico",
    steps: [
      "NO permitir que el atleta se levante o camine.",
      "Verificar nivel de consciencia: ¿Responde? ¿Sabe dónde está?",
      "Buscar signos de alarma: vómito, pupilas desiguales, confusión.",
      "Mantener vía aérea despejada (posición lateral si está inconsciente).",
      "LLAMAR AL 911 / ECU-911 INMEDIATAMENTE.",
      "NO administrar líquidos ni medicamentos.",
    ],
    callEmergency: true,
  },
  "dificultad_respiratoria": {
    severity: "red",
    title: "Dificultad Respiratoria / Asma",
    steps: [
      "Sentar al atleta en posición erguida (facilita la respiración).",
      "Aflojar ropa ajustada en cuello y pecho.",
      "Si tiene inhalador prescrito, ayudarlo a usarlo.",
      "Monitorear frecuencia respiratoria cada 30 segundos.",
      "Si no mejora en 5 minutos, LLAMAR AL 911 / ECU-911.",
    ],
    callEmergency: true,
  },
  "herida_abierta": {
    severity: "yellow",
    title: "Herida Abierta / Laceración",
    steps: [
      "Usar guantes si están disponibles.",
      "Aplicar presión directa con gasa limpia para detener sangrado.",
      "Elevar la extremidad afectada por encima del corazón.",
      "NO retirar objetos incrustados.",
      "Cubrir con vendaje estéril y derivar a centro médico.",
    ],
    callEmergency: false,
  },
  "desmayo": {
    severity: "yellow",
    title: "Síncope / Desmayo",
    steps: [
      "Acostar al atleta boca arriba y elevar las piernas.",
      "Aflojar ropa ajustada.",
      "NO echar agua en la cara.",
      "Verificar que la vía aérea esté libre.",
      "Si no recupera consciencia en 1 minuto, LLAMAR AL 911.",
      "Medir temperatura: descartar golpe de calor.",
    ],
    callEmergency: false,
  },
  "otro": {
    severity: "yellow",
    title: "Lesión No Clasificada",
    steps: [
      "Evaluar nivel de consciencia y dolor (escala 1-10).",
      "Detener la actividad deportiva.",
      "Aplicar primeros auxilios básicos según síntomas.",
      "Documentar qué pasó y cuándo.",
      "Contactar al representante legal del atleta.",
      "Derivar a evaluación médica profesional.",
    ],
    callEmergency: false,
  },
};

const SOS_COOLDOWN_MS = 120_000; // 2 minutos

export const triggerSosAlert = onCall(
  { region: "us-central1", timeoutSeconds: 30, memory: "256MiB" as const },
  async (request) => {
    // L-1: Auth
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Debe iniciar sesión.");
    }
    const callerUid = request.auth.uid;

    // Parámetros requeridos
    const athleteUid   = request.data.athleteUid  as string | undefined;
    const injuryType   = (request.data.injuryType as string | undefined) ?? "otro";
    const description  = (request.data.description as string | undefined) ?? "";
    const latitude     = request.data.latitude  as number | undefined;
    const longitude    = request.data.longitude as number | undefined;
    const locationName = (request.data.locationName as string | undefined) ?? "No especificada";

    if (!athleteUid) {
      throw new HttpsError("invalid-argument", "athleteUid es requerido.");
    }

    // L-3: Rol — solo coach, admin, athlete o parent
    const callerDoc  = await db.collection("users").doc(callerUid).get();
    const callerRole = callerDoc.data()?.["role"] as string | undefined;
    const validRoles = ["admin", "coach", "athlete", "parent"];
    if (!callerRole || !validRoles.includes(callerRole)) {
      throw new HttpsError("permission-denied", "No tiene permisos para emitir alertas SOS.");
    }

    // L-2: Rate-limit — último SOS para este atleta
    const recentSos = await db.collection("sos_alerts")
      .where("athleteUid", "==", athleteUid)
      .orderBy("timestamp", "desc")
      .limit(1)
      .get();

    if (!recentSos.empty) {
      const lastTs = recentSos.docs[0].data().timestamp as Timestamp;
      if (Date.now() - lastTs.toMillis() < SOS_COOLDOWN_MS) {
        throw new HttpsError(
          "resource-exhausted",
          "Ya existe una alerta activa para este atleta. Espera 2 minutos."
        );
      }
    }

    // Obtener datos del atleta
    const athleteDoc = await db.collection("athletes").doc(athleteUid).get();
    if (!athleteDoc.exists) {
      throw new HttpsError("not-found", "Atleta no encontrado.");
    }
    const athleteData = athleteDoc.data()!;
    const athleteName = (athleteData.full_name as string) ?? "Atleta";
    const sport       = (athleteData.teamOrCategory as string) ?? "";
    const parentUid   = (athleteData.parentUid as string | undefined);

    // Protocolo de triaje
    const protocol = TRIAGE_PROTOCOLS[injuryType] ?? TRIAGE_PROTOCOLS["otro"];

    // Crear alerta en Firestore
    const alertRef = db.collection("sos_alerts").doc();
    const alertData = {
      athleteUid,
      athleteName,
      sport,
      triggeredBy: callerUid,
      triggeredByRole: callerRole,
      injuryType,
      description: description.slice(0, 500),
      latitude:  latitude  ?? null,
      longitude: longitude ?? null,
      locationName,
      severity: protocol.severity,
      protocolTitle: protocol.title,
      status: "active",
      timestamp: FieldValue.serverTimestamp(),
      resolvedAt: null,
      resolvedBy: null,
    };
    await alertRef.set(alertData);

    // Notificación Push al padre/representante
    let pushSent = false;
    if (parentUid) {
      try {
        const parentDoc = await db.collection("users").doc(parentUid).get();
        const fcmToken  = parentDoc.data()?.fcmToken as string | undefined;

        if (fcmToken) {
          const timeOptions: Intl.DateTimeFormatOptions = {
            timeZone: "America/Guayaquil", hour: "2-digit", minute: "2-digit",
          };
          const timeString = new Date().toLocaleTimeString("es-ES", timeOptions);

          const severity = protocol.severity === "red"
            ? "🔴 EMERGENCIA" : protocol.severity === "yellow"
            ? "🟡 ALERTA" : "🟢 AVISO";

          await admin.messaging().send({
            token: fcmToken,
            notification: {
              title: `${severity}: ${athleteName}`,
              body: `${protocol.title} reportado a las ${timeString}. ${locationName}.`,
            },
            data: {
              type: "sos_alert",
              alertId: alertRef.id,
              athleteUid,
              severity: protocol.severity,
              latitude: String(latitude ?? 0),
              longitude: String(longitude ?? 0),
            },
            android: {
              priority: "high",
              notification: {
                channelId: "sos_alerts",
                priority: "max",
                sound: "default",
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: "default",
                  badge: 1,
                  "content-available": 1,
                },
              },
            },
          });
          pushSent = true;
        }
      } catch (e) {
        console.error("Error enviando push SOS al padre:", e);
      }
    }

    return {
      success: true,
      alertId: alertRef.id,
      pushSent,
      protocol: {
        severity: protocol.severity,
        title: protocol.title,
        steps: protocol.steps,
        callEmergency: protocol.callEmergency,
      },
    };
  }
);

// =============================================================================
// SECCIÓN 14: CRM MÉDICO — registerInjury + issueMedicalDischarge
//
// registerInjury      (admin | coach | medico):
//   Registra una lesión, cambia estado del atleta a "Lesionado / No Apto"
//   y bloquea automáticamente el Smart ID (isEligible = false via statusOk).
//   Notifica a padres/tutores vía FCM.
//
// issueMedicalDischarge  (admin | medico):
//   Emite el alta médica. Restaura estado a "Acceso Autorizado".
//   Actualiza lastMedicalReview. Desbloquea Smart ID.
//   Notifica a padres/tutores.
//
// Art. 9 LOPDP: datos médicos de salud — tratamiento restrictivo.
// Art. 10 LOPDP: se requiere consentimiento consent_datosSalud.
// =============================================================================

const INJURED_STATUS   = "Lesionado / No Apto";
const CLEARED_STATUS   = "Acceso Autorizado";
const MEDICAL_ROLES    = new Set(["admin", "medico", "coach"]);
const DISCHARGE_ROLES  = new Set(["admin", "medico"]);

export const registerInjury = onCall(
  { region: "us-central1", secrets: [_masterKeySecret] },
  async (request) => {
    assertAuthenticated(request);
    const callerUid = resolveAuth(request).uid;

    // RBAC — solo staff médico/admin/coach puede registrar lesiones.
    const callerDoc  = await db.collection("users").doc(callerUid).get();
    const callerRole = callerDoc.data()?.["role"] as string | undefined;
    if (!callerRole || !MEDICAL_ROLES.has(callerRole)) {
      throw new HttpsError("permission-denied", "Solo personal autorizado puede registrar lesiones.");
    }

    const athleteUid   = request.data["athleteUid"]   as string | undefined;
    const injuryType   = request.data["injuryType"]   as string | undefined;
    const description  = (request.data["description"] as string | undefined) ?? "";
    const severity     = (request.data["severity"]    as string | undefined) ?? "yellow";
    const bodyLocation = (request.data["bodyLocation"] as string | undefined) ?? "";
    const documentUrl  = (request.data["documentUrl"] as string | undefined) ?? "";

    if (!athleteUid || !injuryType) {
      throw new HttpsError("invalid-argument", "athleteUid e injuryType son requeridos.");
    }

    const athleteRef  = db.collection("athletes").doc(athleteUid);
    const athleteSnap = await athleteRef.get();
    if (!athleteSnap.exists) {
      throw new HttpsError("not-found", `Atleta ${athleteUid} no encontrado.`);
    }

    const athleteData  = athleteSnap.data()!;
    const athleteName  = (athleteData["full_name"]          as string) ?? "Desconocido";
    const institutionId = (athleteData["ownerInstitutionId"] as string) ?? "";

    // ── 1. Crear registro de lesión ──────────────────────────────────────
    const injuryRef = db
      .collection("medical_records")
      .doc(athleteUid)
      .collection("injuries")
      .doc();

    const injuryData = {
      injuryType,
      description,
      severity,
      bodyLocation,
      status:       "active",
      reportedAt:   FieldValue.serverTimestamp(),
      reportedBy:   callerUid,
      institutionId,
      athleteName,
      documents:    documentUrl ? [documentUrl] : [],
    };

    // ── 2. Actualizar estado del atleta (bloqueo automático Smart ID) ────
    const athleteUpdate = {
      status:          INJURED_STATUS,
      lastInjuryDate:  FieldValue.serverTimestamp(),
    };

    const batch = db.batch();
    batch.set(injuryRef, injuryData);
    batch.update(athleteRef, athleteUpdate);
    await batch.commit();

    // ── 3. Notificar a padres/tutores ────────────────────────────────────
    let pushSent = false;
    try {
      const parentUid = athleteData["parentUid"] as string | undefined;
      if (parentUid) {
        const parentDoc = await db.collection("users").doc(parentUid).get();
        const fcmToken  = parentDoc.data()?.["fcmToken"] as string | undefined;
        if (fcmToken) {
          const timeOpts: Intl.DateTimeFormatOptions = {
            timeZone: "America/Guayaquil", hour: "2-digit", minute: "2-digit",
          };
          const timeStr = new Date().toLocaleTimeString("es-ES", timeOpts);
          await admin.messaging().send({
            token: fcmToken,
            notification: {
              title: `🚨 Lesión reportada: ${athleteName}`,
              body:  `Se ha registrado una lesión (${injuryType}) a las ${timeStr}. El atleta queda en estado "No Apto" hasta recibir alta médica.`,
            },
            data: {
              type:      "injury_registered",
              injuryId:  injuryRef.id,
              athleteUid,
              severity,
            },
            android: { priority: "high" },
            apns:    { payload: { aps: { sound: "default", badge: 1 } } },
          });
          pushSent = true;
        }
      }
    } catch (e) {
      console.error("Error enviando notificación de lesión:", e);
    }

    // ── 4. Audit log ─────────────────────────────────────────────────────
    await writeAuditLog("INJURY_REGISTERED", callerUid, {
      athleteUid, athleteName, institutionId, injuryType, severity, injuryId: injuryRef.id,
    }, extractIp(request));

    return {
      success:  true,
      injuryId: injuryRef.id,
      athleteName,
      newStatus: INJURED_STATUS,
      pushSent,
    };
  }
);

export const issueMedicalDischarge = onCall(
  { region: "us-central1", secrets: [_masterKeySecret] },
  async (request) => {
    assertAuthenticated(request);
    const callerUid = resolveAuth(request).uid;

    // RBAC — solo médico o admin pueden emitir alta.
    const callerDoc  = await db.collection("users").doc(callerUid).get();
    const callerRole = callerDoc.data()?.["role"] as string | undefined;
    if (!callerRole || !DISCHARGE_ROLES.has(callerRole)) {
      throw new HttpsError("permission-denied", "Solo médico o administrador puede emitir alta médica.");
    }

    const athleteUid     = request.data["athleteUid"]     as string | undefined;
    const injuryId       = request.data["injuryId"]       as string | undefined;
    const dischargeDocUrl = (request.data["dischargeDocUrl"] as string | undefined) ?? "";
    const dischargeNotes  = (request.data["dischargeNotes"]  as string | undefined) ?? "";

    if (!athleteUid || !injuryId) {
      throw new HttpsError("invalid-argument", "athleteUid e injuryId son requeridos.");
    }

    const athleteRef  = db.collection("athletes").doc(athleteUid);
    const injuryRef   = db
      .collection("medical_records").doc(athleteUid)
      .collection("injuries").doc(injuryId);

    const [athleteSnap, injurySnap] = await Promise.all([
      athleteRef.get(),
      injuryRef.get(),
    ]);

    if (!athleteSnap.exists) throw new HttpsError("not-found", `Atleta ${athleteUid} no encontrado.`);
    if (!injurySnap.exists)  throw new HttpsError("not-found", `Lesión ${injuryId} no encontrada.`);
    if (injurySnap.data()?.["status"] === "discharged") {
      throw new HttpsError("already-exists", "Esta lesión ya tiene alta médica registrada.");
    }

    const athleteData  = athleteSnap.data()!;
    const athleteName  = (athleteData["full_name"]           as string) ?? "Desconocido";
    const institutionId = (athleteData["ownerInstitutionId"] as string) ?? "";

    // ── 1. Actualizar lesión + estado del atleta ─────────────────────────
    const nowTs = FieldValue.serverTimestamp();
    const batch = db.batch();

    batch.update(injuryRef, {
      status:         "discharged",
      dischargedAt:   nowTs,
      dischargedBy:   callerUid,
      dischargeDocUrl,
      dischargeNotes,
    });
    batch.update(athleteRef, {
      status:              CLEARED_STATUS,
      lastMedicalReview:   nowTs,
    });

    await batch.commit();

    // ── 2. Notificar a padres/tutores ────────────────────────────────────
    let pushSent = false;
    try {
      const parentUid = athleteData["parentUid"] as string | undefined;
      if (parentUid) {
        const parentDoc = await db.collection("users").doc(parentUid).get();
        const fcmToken  = parentDoc.data()?.["fcmToken"] as string | undefined;
        if (fcmToken) {
          await admin.messaging().send({
            token: fcmToken,
            notification: {
              title: `✅ Alta médica: ${athleteName}`,
              body:  `${athleteName} ha recibido el alta médica y está habilitado para competir.`,
            },
            data: { type: "medical_discharge", athleteUid, injuryId },
            android: { priority: "high" },
            apns:    { payload: { aps: { sound: "default", badge: 0 } } },
          });
          pushSent = true;
        }
      }
    } catch (e) {
      console.error("Error enviando notificación de alta médica:", e);
    }

    // ── 3. Audit log ─────────────────────────────────────────────────────
    await writeAuditLog("MEDICAL_DISCHARGE_ISSUED", callerUid, {
      athleteUid, athleteName, institutionId, injuryId, dischargeDocUrl,
    }, extractIp(request));

    return {
      success:    true,
      injuryId,
      athleteName,
      newStatus: CLEARED_STATUS,
      pushSent,
    };
  }
);

// =============================================================================
// SECCIÓN 15: RUTINAS AUTOMÁTICAS DE LIMPIEZA — MINIMIZACIÓN Y CONSERVACIÓN
//
// Art. 9 LOPDP: principio de minimización — solo conservar datos el tiempo necesario.
// Art. 37 LOPDP: audit_logs conservados 24 meses; luego eliminados automáticamente.
//
// scheduledPurgeUsedTokens : diario — elimina used_tokens con más de 2 horas.
//   Los tokens solo necesitan durar TOKEN_TTL_MS (45s) + margen; retener más
//   es innecesario y ocupa Firestore sin valor.
//
// scheduledLopdpMaintenance : mensual (día 1, 03:00 America/Guayaquil) —
//   • Elimina audit_logs con más de 24 meses.
//   • Anonimiza attendance_logs con más de 12 meses (scannedBy → "ANONYMIZED",
//     location → null): conserva la estadística de asistencia sin identificar al
//     personal que escaneó.
// =============================================================================

export const scheduledPurgeUsedTokens = onSchedule(
  {
    schedule:  "every 24 hours",
    timeZone:  "America/Guayaquil",
    region:    "us-central1",
  },
  async () => {
    const cutoff = Timestamp.fromMillis(Date.now() - 2 * 3600_000); // 2 hours ago
    const snap   = await db.collection("used_tokens")
      .where("usedAt", "<", cutoff)
      .limit(500)
      .get();

    if (snap.empty) return;

    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    console.log(`[purgeUsedTokens] Eliminados ${snap.size} tokens expirados.`);
  }
);

export const scheduledLopdpMaintenance = onSchedule(
  {
    schedule:  "0 3 1 * *",           // 03:00 el día 1 de cada mes
    timeZone:  "America/Guayaquil",
    region:    "us-central1",
  },
  async () => {
    const now = Date.now();

    // ── 1. Eliminar audit_logs con más de 24 meses ────────────────────────
    const auditCutoff = Timestamp.fromMillis(now - 24 * 30 * 24 * 3600_000);
    const oldLogs = await db.collection("audit_logs")
      .where("timestamp", "<", auditCutoff)
      .limit(500)
      .get();

    if (!oldLogs.empty) {
      const auditBatch = db.batch();
      oldLogs.docs.forEach((d) => auditBatch.delete(d.ref));
      await auditBatch.commit();
      console.log(`[lopdpMaintenance] audit_logs eliminados: ${oldLogs.size}`);
    }

    // ── 2. Anonimizar attendance_logs con más de 12 meses ─────────────────
    // Conserva el registro estadístico (quién asistió, cuándo) pero elimina
    // la identidad del operador que escaneó y la ubicación GPS.
    const attendanceCutoff = Timestamp.fromMillis(now - 12 * 30 * 24 * 3600_000);
    const oldAttendance = await db.collection("attendance_logs")
      .where("timestamp", "<", attendanceCutoff)
      .where("scannedBy", "!=", "ANONYMIZED")
      .limit(500)
      .get();

    if (!oldAttendance.empty) {
      const attBatch = db.batch();
      oldAttendance.docs.forEach((d) =>
        attBatch.update(d.ref, { scannedBy: "ANONYMIZED", location: null })
      );
      await attBatch.commit();
      console.log(`[lopdpMaintenance] attendance_logs anonimizados: ${oldAttendance.size}`);
    }

    // ── 3. Eliminar arco_requests resueltos con más de 6 meses ───────────
    const arcoCutoff = Timestamp.fromMillis(now - 6 * 30 * 24 * 3600_000);
    const oldArco = await db.collection("arco_requests")
      .where("requestedAt", "<", arcoCutoff)
      .where("status", "==", "resolved")
      .limit(500)
      .get();

    if (!oldArco.empty) {
      const arcoBatch = db.batch();
      oldArco.docs.forEach((d) => arcoBatch.delete(d.ref));
      await arcoBatch.commit();
      console.log(`[lopdpMaintenance] arco_requests resueltos eliminados: ${oldArco.size}`);
    }

    console.log("[lopdpMaintenance] Mantenimiento mensual LOPDP completado.");
  }
);


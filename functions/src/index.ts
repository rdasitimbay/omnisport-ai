import * as admin from "firebase-admin";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";

admin.initializeApp();
const db = admin.firestore();

// ─── CONSTANTES ────────────────────────────────────────────────────────────────

// Firestore WriteBatch: máx 500 operaciones por lote.
// Cada atleta genera 2 escrituras (root + private/sensitive_data) → 250 por batch.
const MAX_OPS_PER_BATCH = 500;
const ATHLETES_PER_BATCH = MAX_OPS_PER_BATCH / 2;

// Firestore 'in' query: máx 30 valores por cláusula.
const FIRESTORE_IN_LIMIT = 30;

// ─── TIPOS ────────────────────────────────────────────────────────────────────

interface ValidatedRecord {
  rowNumber: number;
  name: string;
  dni: string;
  email: string;
  phone: string;
  team: string;
  consentDate: string;
}

interface IngestionRequest {
  csv: string;
  institutionId: string;
}

interface IngestionResponse {
  total: number;
  valid: number;
  failed: number;
}

interface LogAccessRequest {
  athleteId: string;
  action: string;
}

interface ErasureRequest {
  uid: string;
}

// ─── GUARDS DE AUTENTICACIÓN ───────────────────────────────────────────────────

function assertAdmin(request: CallableRequest): void {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "No autenticado.");
  }
  if (request.auth.token["role"] !== "admin") {
    throw new HttpsError("permission-denied", "Solo administradores pueden ejecutar esta operación.");
  }
}

function assertAdminOrSelf(request: CallableRequest, targetUid: string): void {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "No autenticado.");
  }
  const isAdmin = request.auth.token["role"] === "admin";
  const isSelf = request.auth.uid === targetUid;
  if (!isAdmin && !isSelf) {
    throw new HttpsError("permission-denied", "Operación no autorizada.");
  }
}

// ─── HELPERS DE PARSING ────────────────────────────────────────────────────────

function parseAndValidateCsv(csvString: string): {
  valid: ValidatedRecord[];
  failed: number;
} {
  const EMAIL_REGEX = /^[^@]+@[^@]+\.[^@]+/;
  const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;

  const clean = csvString
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/﻿/g, "");

  const lines = clean.split("\n").filter((l) => l.trim());
  if (lines.length < 2) return { valid: [], failed: 0 };

  const headerLine = lines[0].toLowerCase();
  const separator = headerLine.includes(";") &&
    headerLine.split(";").length > headerLine.split(",").length
    ? ";"
    : ",";

  const headers = lines[0].split(separator).map((h) =>
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
      `Cabecera CSV inválida. Columnas detectadas: ${headers.join(", ")}`
    );
  }

  const cell = (row: string[], i: number): string =>
    i >= 0 && i < row.length ? row[i].trim() : "";

  const valid: ValidatedRecord[] = [];
  let failed = 0;

  for (let i = 1; i < lines.length; i++) {
    const row = lines[i].split(separator);
    if (row.join("").trim() === "") continue;

    const name        = cell(row, nameIdx);
    const dni         = cell(row, dniIdx);
    const email       = cell(row, emailIdx);
    const phone       = cell(row, phoneIdx);
    const team        = teamIdx >= 0 ? cell(row, teamIdx) : "Sin Categoría";
    const consentDate = cell(row, consentIdx);

    // Defense in depth: re-validación completa en servidor.
    if (!consentDate || !DATE_REGEX.test(consentDate)) { failed++; continue; }
    if (!dni)                                           { failed++; continue; }
    if (email && !EMAIL_REGEX.test(email))              { failed++; continue; }

    valid.push({ rowNumber: i + 1, name, dni, email, phone, team, consentDate });
  }

  return { valid, failed };
}

// Consulta masiva de DNIs existentes usando 'in' (máx 30 por query).
// Más eficiente que N lecturas individuales — O(N/30) en vez de O(N).
async function fetchExistingDnis(dnis: string[]): Promise<Set<string>> {
  const existingDnis = new Set<string>();
  for (let i = 0; i < dnis.length; i += FIRESTORE_IN_LIMIT) {
    const chunk = dnis.slice(i, i + FIRESTORE_IN_LIMIT);
    const snap = await db
      .collectionGroup("sensitive_data")
      .where("dni", "in", chunk)
      .get();
    snap.docs.forEach((doc) => {
      const d = doc.data()["dni"] as string | undefined;
      if (d) existingDnis.add(d);
    });
  }
  return existingDnis;
}

// ─── FUNCIÓN 1: processBulkIngestion ──────────────────────────────────────────
//
// Recibe el CSV desde AdminIngestionController.confirmIngestion().
// Flujo:
//   1. Guard: solo admins.
//   2. Re-valida el CSV (defense in depth).
//   3. Consulta duplicados con batched 'in' queries.
//   4. Escribe atletas válidos en batches de 500 operaciones (250 atletas).
//   5. Convierte consent_date a Firestore Timestamp.
//   6. Registra el evento en audit_logs.
//
// Art. 10 LOPDP: ninguna escritura de datos sensibles desde el cliente Flutter.
// Art. 26 LOPDP: consent_timestamp se persiste como Timestamp verificado en servidor.

export const processBulkIngestion = onCall<IngestionRequest, IngestionResponse>(
  { region: "us-central1", timeoutSeconds: 300, memory: "512MiB" },
  async (request) => {
    assertAdmin(request);

    const { csv, institutionId } = request.data;

    if (!csv || !institutionId) {
      throw new HttpsError("invalid-argument", "csv e institutionId son requeridos.");
    }

    // ── Paso 1: Validación de formato ──────────────────────────────────────
    const { valid: candidates, failed: formatFailed } = parseAndValidateCsv(csv);

    if (candidates.length === 0) {
      await writeAuditLog("BULK_INGESTION_NO_VALID_RECORDS", request.auth!.uid, {
        institutionId,
        total: formatFailed,
        valid: 0,
        failed: formatFailed,
      });
      return { total: formatFailed, valid: 0, failed: formatFailed };
    }

    // ── Paso 2: Verificación de duplicados (batched 'in') ──────────────────
    const allDnis = candidates.map((r) => r.dni);
    const existingDnis = await fetchExistingDnis(allDnis);

    const toWrite = candidates.filter((r) => !existingDnis.has(r.dni));
    const duplicateCount = candidates.length - toWrite.length;
    const totalFailed = formatFailed + duplicateCount;

    // ── Paso 3: Escritura en batches de 500 operaciones ───────────────────
    for (let i = 0; i < toWrite.length; i += ATHLETES_PER_BATCH) {
      const chunk = toWrite.slice(i, i + ATHLETES_PER_BATCH);
      const batch = db.batch();

      for (const record of chunk) {
        const athleteRef = db.collection("athletes").doc();

        // Documento raíz — datos públicos del atleta.
        batch.set(athleteRef, {
          ownerInstitutionId: institutionId,
          full_name: record.name,
          teamOrCategory: record.team,
          paymentStatus: "Pago Pendiente",
          status: "Inactivo",
          // Art. 26 LOPDP: consent_timestamp como Timestamp verificado en servidor.
          consent_timestamp: admin.firestore.Timestamp.fromDate(
            new Date(`${record.consentDate}T00:00:00Z`)
          ),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          photoUrl: "",
        });

        // Subcolección /private — datos sensibles segregados.
        // Art. 10 LOPDP: solo Admin SDK puede escribir aquí desde el servidor.
        const privateRef = athleteRef.collection("private").doc("sensitive_data");
        batch.set(privateRef, {
          dni: record.dni,
          email: record.email,
          phone: record.phone,
        });
      }

      await batch.commit();
    }

    // ── Paso 4: Registro en audit_logs ────────────────────────────────────
    // Art. 37 LOPDP: registro inalterable de la operación de ingesta.
    await writeAuditLog("BULK_INGESTION_COMPLETED", request.auth!.uid, {
      institutionId,
      total: candidates.length + formatFailed,
      valid: toWrite.length,
      failed: totalFailed,
    });

    return {
      total: candidates.length + formatFailed,
      valid: toWrite.length,
      failed: totalFailed,
    };
  }
);

// ─── FUNCIÓN 2: logSensitiveAccess ────────────────────────────────────────────
//
// Registra en audit_logs cada vez que un admin desenmascara un DNI.
// El cliente Flutter NUNCA escribe directamente en audit_logs (allow write: if false).
//
// Art. 37 LOPDP: registro inalterable, firmado por servidor, con timestamp de Firestore.
// Art. 10 LOPDP: trazabilidad de acceso a datos sensibles de menores.

export const logSensitiveAccess = onCall<LogAccessRequest, void>(
  { region: "us-central1" },
  async (request) => {
    assertAdmin(request);

    const { athleteId, action } = request.data;

    if (!athleteId || !action) {
      throw new HttpsError("invalid-argument", "athleteId y action son requeridos.");
    }

    const adminToken = request.auth!.token;

    await db.collection("audit_logs").add({
      action,
      athleteId,
      adminId: request.auth!.uid,
      adminEmail: adminToken["email"] ?? null,
      adminInstitutionId: adminToken["institutionId"] ?? null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
);

// ─── FUNCIÓN 3: requestAthleteErasure ─────────────────────────────────────────
//
// Implementa el Derecho al Olvido (Art. 16 LOPDP) de forma segura y auditada.
// Puede ser invocada por:
//   - El propio atleta (auto-borrado desde profile_screen.dart).
//   - Un admin (borrado por solicitud de tutor legal o resolución legal).
//
// Flujo:
//   1. Guard: admin o self.
//   2. Registra INICIO del borrado (audit log persiste antes de borrar datos).
//   3. Elimina recursivamente el documento del atleta y todas sus subcolecciones.
//   4. Revoca los refresh tokens del usuario (invalida sesiones activas).
//   5. Si es borrado por admin: elimina también la cuenta de Firebase Auth.
//   6. Registra CONFIRMACIÓN del borrado.
//
// Art. 16 LOPDP: borrado completo e irreversible, auditado con timestamp de servidor.
// Art. 37 LOPDP: el audit_log del borrado persiste ANTES de borrar los datos.

export const requestAthleteErasure = onCall<ErasureRequest, void>(
  { region: "us-central1", timeoutSeconds: 120 },
  async (request) => {
    const { uid } = request.data;

    if (!uid) {
      throw new HttpsError("invalid-argument", "uid es requerido.");
    }

    assertAdminOrSelf(request, uid);

    const callerId = request.auth!.uid;
    const isSelfErasure = callerId === uid;
    const erasureType = isSelfErasure ? "SELF_ERASURE" : "ADMIN_ERASURE";

    // ── Paso 1: Verifica que el atleta existe ─────────────────────────────
    const athleteRef = db.collection("athletes").doc(uid);
    const athleteSnap = await athleteRef.get();

    if (!athleteSnap.exists) {
      throw new HttpsError("not-found", `Atleta ${uid} no encontrado en Firestore.`);
    }

    // ── Paso 2: Audit log ANTES de borrar (Art. 37 LOPDP) ────────────────
    // El log debe existir aunque el borrado falle a mitad de camino.
    await writeAuditLog(`${erasureType}_INITIATED`, callerId, {
      targetUid: uid,
      athleteName: athleteSnap.data()?.["full_name"] ?? "Desconocido",
      institutionId: athleteSnap.data()?.["ownerInstitutionId"] ?? null,
    });

    // ── Paso 3: Borrado recursivo con Admin SDK ───────────────────────────
    // recursiveDelete elimina el doc raíz + todas sus subcolecciones
    // (/private, /sport_details, /historial_entrenamientos, etc.).
    await db.recursiveDelete(athleteRef);

    // ── Paso 4: Revocación de tokens (invalida sesiones activas) ──────────
    // Si el usuario tiene sesión abierta en otro dispositivo, quedará bloqueado
    // en el próximo request porque consent_signed y role ya no existen.
    try {
      await admin.auth().revokeRefreshTokens(uid);
    } catch {
      // Si la cuenta ya no existe en Auth, no es un error crítico.
    }

    // ── Paso 5: Borrado de cuenta Auth (solo admin-initiated) ─────────────
    // En self-erasure, el cliente llama user.delete() tras este CF retornar.
    // En admin-erasure, no hay cliente activo, así que borramos aquí.
    if (!isSelfErasure) {
      try {
        await admin.auth().deleteUser(uid);
      } catch {
        // Usuario puede no existir en Auth si fue creado solo en Firestore.
      }
    }

    // ── Paso 6: Confirmación en audit_logs ────────────────────────────────
    await writeAuditLog(`${erasureType}_COMPLETED`, callerId, {
      targetUid: uid,
      deletedAt: new Date().toISOString(),
    });
  }
);

// ─── HELPER INTERNO: writeAuditLog ────────────────────────────────────────────
//
// Escritura centralizada en audit_logs. Se usa desde todas las funciones.
// El Admin SDK bypasea 'allow write: if false' de las reglas Firestore.
// Art. 37 LOPDP: timestamps generados en servidor, no manipulables desde el cliente.

async function writeAuditLog(
  action: string,
  performedBy: string,
  metadata: Record<string, unknown>
): Promise<void> {
  await db.collection("audit_logs").add({
    action,
    performedBy,
    ...metadata,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
}

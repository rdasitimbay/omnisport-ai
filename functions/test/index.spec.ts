/**
 * Unit tests — functions/src/index.ts
 *
 * LOPDP compliance coverage:
 *   Art. 10  — consent_signed required for every data operation
 *   Art. 16  — Right to Erasure: order of operations + receipt integrity
 *   Art. 26  — Admin-only write access for bulk ingestion of minors' data
 *   Art. 37  — Audit log: server-timestamped, immutable, written before destructive ops
 *
 * Strategy: mock firebase-admin and firebase-functions/v2/https before the module
 * loads; capture each onCall handler via the mock; call handlers directly with
 * crafted CallableRequest objects. No real Firebase connection required.
 */

// ─── HMAC helper — mirrors hmacForSearch() in index.ts ───────────────────────
// Used to build mock Firestore docs that match what fetchExistingDnis() reads.
import * as crypto from "crypto";

const _TEST_KEY = crypto.createHash("sha256")
  .update(process.env["MASTER_AES_KEY"] ?? "omnisport-ai-super-secret-dev-key")
  .digest();

function testHmac(text: string): string {
  return crypto.createHmac("sha256", _TEST_KEY)
    .update(text.trim().toUpperCase())
    .digest("hex");
}

// ─── Shared types ─────────────────────────────────────────────────────────────

interface MockToken {
  role?: string;
  institutionId?: string;
  consent_signed?: boolean;
  email?: string;
  [key: string]: unknown;
}

interface MockAuth {
  uid: string;
  token: MockToken;
}

interface MockRequest {
  data: Record<string, unknown>;
  auth?: MockAuth;
}

type HandlerFn = (req: MockRequest) => Promise<unknown>;

// ─── Firestore mock plumbing ──────────────────────────────────────────────────

const mockBatchSet    = jest.fn().mockReturnThis();
const mockBatchCommit = jest.fn().mockResolvedValue(undefined);
const mockBatch = { set: mockBatchSet, commit: mockBatchCommit };

const mockAuditAdd = jest.fn().mockResolvedValue({ id: "audit-abc-123" });

const mockCollectionGroupGet = jest.fn().mockResolvedValue({ docs: [] });
const mockCollectionGroupRef = {
  where: jest.fn().mockReturnThis(),
  get:   mockCollectionGroupGet,
};

const mockRevokeRefreshTokens = jest.fn().mockResolvedValue(undefined);
const mockDeleteUser          = jest.fn().mockResolvedValue(undefined);
const mockRecursiveDelete     = jest.fn().mockResolvedValue(undefined);

const mockFileDelete = jest.fn().mockResolvedValue(undefined);
const mockDeleteFiles = jest.fn().mockResolvedValue(undefined);
const mockBucket = {
  file: jest.fn(() => ({ delete: mockFileDelete })),
  deleteFiles: mockDeleteFiles,
};
const mockStorage = jest.fn(() => ({
  bucket: jest.fn(() => mockBucket),
}));

// Mutable so individual tests can swap for 'not-found' scenarios.
let currentAthleteSnap = {
  exists: true,
  data: (): Record<string, unknown> => ({
    ownerInstitutionId: "inst-001",
    full_name: "Atleta Test",
  }),
};

const makeDocRef = () => ({
  id: "athlete-abc-123",
  get: jest.fn().mockImplementation(() => Promise.resolve(currentAthleteSnap)),
  collection: jest.fn(() => ({
    doc: jest.fn(() => ({ id: "sensitive_data" })),
  })),
});

// Returns a user snap where role:"admin" for the canonical admin uid, "athlete" otherwise.
// This mirrors what assertAdmin / assertAdminOrSelf read from db.collection("users").
const mockUserDocDelete = jest.fn().mockResolvedValue(undefined);
const mockUserDocFactory = (uid: string) => ({
  id: uid,
  get: jest.fn().mockResolvedValue({
    exists: true,
    data: () => (uid === "admin-uid-001" ? { role: "admin" } : { role: "athlete" }),
  }),
  delete: mockUserDocDelete,
});

const mockDbInstance = {
  batch:           jest.fn(() => mockBatch),
  collection:      jest.fn((name: string) => {
    if (name === "audit_logs") return { add: mockAuditAdd };
    if (name === "users")      return { doc: jest.fn(mockUserDocFactory) };
    // "athletes" and any other collection
    return { doc: jest.fn(makeDocRef), add: jest.fn() };
  }),
  collectionGroup: jest.fn(() => mockCollectionGroupRef),
  recursiveDelete: mockRecursiveDelete,
};

// ─── firebase-admin mock ──────────────────────────────────────────────────────

jest.mock("firebase-admin", () => ({
  initializeApp: jest.fn(),
  firestore: Object.assign(
    jest.fn(() => mockDbInstance),
    {
      FieldValue: { serverTimestamp: () => "SERVER_TIMESTAMP" },
      Timestamp:  { fromDate: (d: Date) => d },
    }
  ),
  auth: jest.fn(() => ({
    revokeRefreshTokens: mockRevokeRefreshTokens,
    deleteUser:          mockDeleteUser,
  })),
  storage: mockStorage,
}));

// ─── firebase-functions/v2/https mock — captures handlers ────────────────────

class MockHttpsError extends Error {
  code: string;
  constructor(code: string, message: string) {
    super(message);
    this.code = code;
    this.name = "HttpsError";
  }
}

// Populated during module load (each onCall call appends one entry).
const handlers: Record<string, HandlerFn> = {};
let handlerIdx = 0;
const HANDLER_ORDER = [
  "processBulkIngestion",
  "logSensitiveAccess",
  "requestAthleteErasure",
  "deleteUserAccount",
  "linkParentToAthlete",
  "syncAccessLog",
  "generateAttendanceToken",
  "validateAttendanceToken",
  "broadcastEmergencyPush",
  "generateSmartId",
  "verifySmartId",
  "linkAthleteAccount",
  "triggerSosAlert",
  "registerInjury",
  "issueMedicalDischarge",
  "getAttendanceReport",
] as const;

jest.mock("firebase-functions/v2/https", () => ({
  onCall: jest.fn((_opts: unknown, handler: HandlerFn) => {
    const name = HANDLER_ORDER[handlerIdx++];
    handlers[name] = handler;
    return { __mocked: name };
  }),
  HttpsError: MockHttpsError,
}));

// Load the module under test — triggers all four onCall registrations.
// jest.mock() calls above are hoisted above this import, so mocks are live first.
// eslint-disable-next-line @typescript-eslint/no-require-imports
require("../src/index");

// ─── Request factories ────────────────────────────────────────────────────────

const adminReq = (data: Record<string, unknown>): MockRequest => ({
  data,
  auth: {
    uid: "admin-uid-001",
    token: {
      role: "admin",
      institutionId: "inst-001",
      consent_signed: true,
      email: "admin@club.ec",
    },
  },
});

const coachReq = (data: Record<string, unknown>): MockRequest => ({
  data,
  auth: {
    uid: "coach-uid-001",
    token: { role: "coach", institutionId: "inst-001", consent_signed: true },
  },
});

const unauthReq = (data: Record<string, unknown>): MockRequest => ({ data });

const noConsentReq = (data: Record<string, unknown>): MockRequest => ({
  data,
  auth: { uid: "athlete-no-consent", token: { role: "athlete", consent_signed: false } },
});

// ─── CSV fixtures ─────────────────────────────────────────────────────────────

const VALID_CSV = [
  "full_name,dni,email,phone,team,consent_date",
  "Jugador Uno,1712345678,uno@test.ec,0991234567,Sub-17,2024-01-15",
  "Jugador Dos,1798765432,dos@test.ec,0997654321,Sub-20,2024-02-20",
].join("\n");

const INVALID_DATE_CSV = [
  "full_name,dni,email,phone,team,consent_date",
  "Jugador Uno,1712345678,uno@test.ec,0991234567,Sub-17,2024-01-15",
  "Jugador Mal,1799999999,mal@test.ec,0990000000,Sub-17,15/01/2024", // dd/mm/yyyy rejected
].join("\n");

const HEADER_ONLY_CSV = "full_name,dni,email,phone,team,consent_date\n";

// =============================================================================
// SUITE 1: processBulkIngestion
// =============================================================================

describe("processBulkIngestion", () => {
  const H = handlers["processBulkIngestion"];

  beforeEach(() => {
    jest.clearAllMocks();
    mockBatchCommit.mockResolvedValue(undefined);
    mockAuditAdd.mockResolvedValue({ id: "audit-abc-123" });
    mockCollectionGroupGet.mockResolvedValue({ docs: [] });
    currentAthleteSnap = {
      exists: true,
      data: () => ({ ownerInstitutionId: "inst-001", full_name: "Atleta Test" }),
    };
  });

  // ── Success paths ────────────────────────────────────────────────────────────

  it("ingests valid CSV and returns a complete IngestionSummaryHive object", async () => {
    const result = await H(adminReq({ csv: VALID_CSV, institutionId: "inst-001" })) as Record<string, unknown>;

    expect(result).toMatchObject({
      institutionId: "inst-001",
      total:         2,
      valid:         2,
      failed:        0,
      duplicates:    0,
      batchCount:    1,
      adminId:       "admin-uid-001",
    });
    // executedAtMs must be a Unix ms integer (Hive int-compatible)
    expect(typeof result["executedAtMs"]).toBe("number");
    expect(mockBatchCommit).toHaveBeenCalledTimes(1);
    // One audit log for BULK_INGESTION_COMPLETED
    expect(mockAuditAdd).toHaveBeenCalledTimes(1);
  });

  it("counts format failures separately from valid records", async () => {
    const result = await H(adminReq({ csv: INVALID_DATE_CSV, institutionId: "inst-001" })) as Record<string, unknown>;

    expect(result["total"]).toBe(2);
    expect(result["valid"]).toBe(1);
    expect(result["failed"]).toBe(1);
    expect(result["duplicates"]).toBe(0);
  });

  it("detects duplicate DNIs and skips re-writing them", async () => {
    // Simulate '1712345678' already in Firestore sensitive_data.
    // fetchExistingDnis reads the dni_hash field — provide the HMAC, not the raw DNI.
    mockCollectionGroupGet.mockResolvedValueOnce({
      docs: [{ data: () => ({ dni_hash: testHmac("1712345678") }) }],
    });

    const result = await H(adminReq({ csv: VALID_CSV, institutionId: "inst-001" })) as Record<string, unknown>;

    expect(result["duplicates"]).toBe(1);
    expect(result["valid"]).toBe(1);
    // Only 1 athlete written, still 1 batch commit
    expect(mockBatchCommit).toHaveBeenCalledTimes(1);
  });

  it("returns zero writes when all records are duplicates — no batch commit", async () => {
    mockCollectionGroupGet.mockResolvedValue({
      docs: [
        { data: () => ({ dni_hash: testHmac("1712345678") }) },
        { data: () => ({ dni_hash: testHmac("1798765432") }) },
      ],
    });

    const result = await H(adminReq({ csv: VALID_CSV, institutionId: "inst-001" })) as Record<string, unknown>;

    expect(result["valid"]).toBe(0);
    expect(result["duplicates"]).toBe(2);
    expect(mockBatchCommit).not.toHaveBeenCalled();
  });

  // ── LOPDP Art. 37 — Audit trail even on no-op ────────────────────────────────

  it("[Art. 37] writes BULK_INGESTION_NO_VALID_RECORDS audit log when CSV has no data rows", async () => {
    await H(adminReq({ csv: HEADER_ONLY_CSV, institutionId: "inst-001" }));

    expect(mockAuditAdd).toHaveBeenCalledWith(
      expect.objectContaining({ action: "BULK_INGESTION_NO_VALID_RECORDS" })
    );
    expect(mockBatchCommit).not.toHaveBeenCalled();
  });

  // ── LOPDP Art. 26 — Admin-only write access ───────────────────────────────────

  it("[Art. 26] rejects unauthenticated caller with 'unauthenticated'", async () => {
    await expect(
      H(unauthReq({ csv: VALID_CSV, institutionId: "inst-001" }))
    ).rejects.toMatchObject({ code: "unauthenticated" });
    expect(mockBatchCommit).not.toHaveBeenCalled();
  });

  it("[Art. 26] rejects coach role with 'permission-denied'", async () => {
    await expect(
      H(coachReq({ csv: VALID_CSV, institutionId: "inst-001" }))
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  it("[Art. 26] rejects missing csv field with 'invalid-argument'", async () => {
    await expect(
      H(adminReq({ institutionId: "inst-001" }))
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("[Art. 26] rejects missing institutionId with 'invalid-argument'", async () => {
    await expect(
      H(adminReq({ csv: VALID_CSV }))
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("[Art. 26] rejects invalid CSV headers with 'invalid-argument'", async () => {
    const badHeadersCsv = "nombre_completo,cedula,correo\nJugador,123,a@b.com";
    await expect(
      H(adminReq({ csv: badHeadersCsv, institutionId: "inst-001" }))
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });
});

// =============================================================================
// SUITE 2: logSensitiveAccess
// =============================================================================

describe("logSensitiveAccess", () => {
  const H = handlers["logSensitiveAccess"];

  beforeEach(() => {
    jest.clearAllMocks();
    mockAuditAdd.mockResolvedValue({ id: "audit-log-xyz" });
  });

  // ── Success path ─────────────────────────────────────────────────────────────

  it("creates audit log and returns a complete AuditLogEntryHive object", async () => {
    const result = await H(
      adminReq({ athleteId: "athlete-001", action: "unmask_dni" })
    ) as Record<string, unknown>;

    expect(result).toMatchObject({
      logId:         "audit-log-xyz",
      action:        "unmask_dni",
      athleteId:     "athlete-001",
      adminId:       "admin-uid-001",
      adminEmail:    "admin@club.ec",
      institutionId: "inst-001",
    });
    // timestampMs must be a Unix ms integer (Hive int-compatible)
    expect(typeof result["timestampMs"]).toBe("number");
    expect(mockAuditAdd).toHaveBeenCalledTimes(1);
  });

  // ── LOPDP Art. 37 — Immutable audit trail ────────────────────────────────────

  it("[Art. 37] rejects unauthenticated caller — no audit log written", async () => {
    await expect(
      H(unauthReq({ athleteId: "athlete-001", action: "unmask_dni" }))
    ).rejects.toMatchObject({ code: "unauthenticated" });
    expect(mockAuditAdd).not.toHaveBeenCalled();
  });

  it("[Art. 37] rejects coach role with 'permission-denied'", async () => {
    await expect(
      H(coachReq({ athleteId: "athlete-001", action: "unmask_dni" }))
    ).rejects.toMatchObject({ code: "permission-denied" });
    expect(mockAuditAdd).not.toHaveBeenCalled();
  });

  it("[Art. 37] rejects missing athleteId with 'invalid-argument'", async () => {
    await expect(
      H(adminReq({ action: "unmask_dni" }))
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("[Art. 37] rejects missing action with 'invalid-argument'", async () => {
    await expect(
      H(adminReq({ athleteId: "athlete-001" }))
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });
});

// =============================================================================
// SUITE 3: requestAthleteErasure
// =============================================================================

describe("requestAthleteErasure", () => {
  const H = handlers["requestAthleteErasure"];

  beforeEach(() => {
    jest.clearAllMocks();
    // Default: athlete exists
    currentAthleteSnap = {
      exists: true,
      data: () => ({ ownerInstitutionId: "inst-001", full_name: "Atleta Test" }),
    };
    mockAuditAdd.mockResolvedValue({ id: "receipt-xyz-789" });
    mockRevokeRefreshTokens.mockResolvedValue(undefined);
    mockDeleteUser.mockResolvedValue(undefined);
    mockRecursiveDelete.mockResolvedValue(undefined);
  });

  it("[Art. 16] admin erasure: deletes data, revokes tokens, deletes auth account", async () => {
    const result = await H(adminReq({ uid: "athlete-abc-123" })) as Record<string, unknown>;

    expect(result).toMatchObject({
      targetUid:   "athlete-abc-123",
      erasureType: "ADMIN_ERASURE",
      performedBy: "admin-uid-001",
    });
    expect(typeof result["completedAtMs"]).toBe("number");
    expect(mockRecursiveDelete).toHaveBeenCalledTimes(1);
    expect(mockRevokeRefreshTokens).toHaveBeenCalledWith("athlete-abc-123");
    expect(mockDeleteUser).toHaveBeenCalledWith("athlete-abc-123");

    // Borrado en cascada: Firestore (users) y Storage
    expect(mockUserDocDelete).toHaveBeenCalledTimes(1);
    expect(mockFileDelete).toHaveBeenCalledTimes(1);
    expect(mockDeleteFiles).toHaveBeenCalledWith({ prefix: "tutor_docs/athlete-abc-123/" });
  });

  it("[Art. 37] INITIATED audit log is written BEFORE recursiveDelete", async () => {
    // Track call order
    const callOrder: string[] = [];
    mockAuditAdd.mockImplementation((doc: Record<string, unknown>) => {
      callOrder.push(doc["action"] as string);
      return Promise.resolve({ id: "receipt-xyz-789" });
    });
    mockRecursiveDelete.mockImplementation(() => {
      callOrder.push("recursiveDelete");
      return Promise.resolve();
    });

    await H(adminReq({ uid: "athlete-abc-123" }));

    expect(callOrder[0]).toBe("ADMIN_ERASURE_INITIATED");
    expect(callOrder[1]).toBe("recursiveDelete");
    expect(callOrder[2]).toBe("ADMIN_ERASURE_COMPLETED");
  });

  // ── LOPDP Art. 16 — Self erasure ─────────────────────────────────────────────

  it("[Art. 16] self-erasure: deletes data but does NOT delete auth account", async () => {
    const selfReq: MockRequest = {
      data: { uid: "self-uid-001" },
      auth: { uid: "self-uid-001", token: { role: "athlete", consent_signed: true } },
    };

    const result = await H(selfReq) as Record<string, unknown>;

    expect(result["erasureType"]).toBe("SELF_ERASURE");
    expect(mockRecursiveDelete).toHaveBeenCalledTimes(1);
    expect(mockRevokeRefreshTokens).toHaveBeenCalledWith("self-uid-001");
    // Client is responsible for calling user.delete() after receiving the receipt
    expect(mockDeleteUser).not.toHaveBeenCalled();
  });

  // ── LOPDP Art. 10 & 16 — Auth guards ─────────────────────────────────────────

  it("[Art. 10] rejects unauthenticated caller — no data modified", async () => {
    await expect(
      H(unauthReq({ uid: "athlete-abc-123" }))
    ).rejects.toMatchObject({ code: "unauthenticated" });
    expect(mockRecursiveDelete).not.toHaveBeenCalled();
  });

  it("[Art. 10] rejects caller without consent_signed — no data modified", async () => {
    await expect(
      H(noConsentReq({ uid: "athlete-abc-123" }))
    ).rejects.toMatchObject({ code: "permission-denied" });
    expect(mockRecursiveDelete).not.toHaveBeenCalled();
  });

  it("[Art. 16] rejects cross-user erasure (non-admin erasing someone else)", async () => {
    const attackerReq: MockRequest = {
      data: { uid: "victim-uid-999" },
      auth: { uid: "attacker-uid-001", token: { role: "coach", consent_signed: true } },
    };

    await expect(H(attackerReq)).rejects.toMatchObject({ code: "permission-denied" });
    expect(mockRecursiveDelete).not.toHaveBeenCalled();
  });

  it("[Art. 16] returns 'not-found' when athlete document does not exist", async () => {
    currentAthleteSnap = { exists: false, data: () => ({}) };

    await expect(
      H(adminReq({ uid: "ghost-uid-000" }))
    ).rejects.toMatchObject({ code: "not-found" });
    expect(mockRecursiveDelete).not.toHaveBeenCalled();
  });

  it("[Art. 16] rejects missing uid field with 'invalid-argument'", async () => {
    await expect(H(adminReq({}))).rejects.toMatchObject({ code: "invalid-argument" });
  });
});

// =============================================================================
// SUITE 4: syncAccessLog
// =============================================================================

describe("syncAccessLog", () => {
  const H = handlers["syncAccessLog"];

  const consentedReq = (data: Record<string, unknown>): MockRequest => ({
    data,
    auth: { uid: "coach-uid-001", token: { role: "coach", consent_signed: true } },
  });

  const sampleLog = {
    athleteId:    "athlete-001",
    scannedByUid: "coach-001",
    eventType:    "ENTRY",
    locationId:   "gate-A",
    clientMs:     1_715_000_000_000,
    synced:       false,
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockBatchCommit.mockResolvedValue(undefined);
  });

  // ── Success path ─────────────────────────────────────────────────────────────

  it("syncs a batch of logs and returns syncedCount + serverMs", async () => {
    const logs = [sampleLog, { ...sampleLog, eventType: "EXIT" }];
    const result = await H(consentedReq({ logs })) as Record<string, unknown>;

    expect(result["syncedCount"]).toBe(2);
    expect(typeof result["serverMs"]).toBe("number");
    expect(mockBatchCommit).toHaveBeenCalledTimes(1);
  });

  it("silently skips logs with missing athleteId or eventType — only valid ones written", async () => {
    const logs = [
      { ...sampleLog, athleteId: "" }, // skipped (empty athleteId)
      sampleLog,                       // written
    ];

    const result = await H(consentedReq({ logs })) as Record<string, unknown>;

    expect(result["syncedCount"]).toBe(2); // input count, not written count
    expect(mockBatchSet).toHaveBeenCalledTimes(1); // only the valid log
  });

  // ── LOPDP Art. 10 — Consent & authentication ─────────────────────────────────

  it("[Art. 10] rejects unauthenticated caller with 'unauthenticated'", async () => {
    await expect(
      H(unauthReq({ logs: [sampleLog] }))
    ).rejects.toMatchObject({ code: "unauthenticated" });
    expect(mockBatchCommit).not.toHaveBeenCalled();
  });

  it("[Art. 10] rejects caller without consent_signed with 'permission-denied'", async () => {
    await expect(
      H(noConsentReq({ logs: [sampleLog] }))
    ).rejects.toMatchObject({ code: "permission-denied" });
    expect(mockBatchCommit).not.toHaveBeenCalled();
  });

  // ── LOPDP Art. 37 — Anti-abuse / payload validation ──────────────────────────

  it("[Art. 37] rejects empty logs array with 'invalid-argument'", async () => {
    await expect(
      H(consentedReq({ logs: [] }))
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("[Art. 37] rejects non-array logs payload with 'invalid-argument'", async () => {
    await expect(
      H(consentedReq({ logs: "not-an-array" }))
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("[Art. 37] rejects > 100 logs per call (DoS prevention)", async () => {
    const bigBatch = Array.from({ length: 101 }, () => ({ ...sampleLog }));
    await expect(
      H(consentedReq({ logs: bigBatch }))
    ).rejects.toMatchObject({ code: "invalid-argument" });
    expect(mockBatchCommit).not.toHaveBeenCalled();
  });
});

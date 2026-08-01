import { validateAttendanceToken } from '../src/index';
import * as crypto from 'crypto';

const mockTxGet = jest.fn();
const mockTxSet = jest.fn();

jest.mock('firebase-admin', () => {
  const mockDb = {
    collection: jest.fn().mockReturnThis(),
    doc: jest.fn().mockReturnThis(),
    get: jest.fn().mockResolvedValue({
      exists: true,
      data: () => ({ role: 'admin', institutionId: 'inst-001', ownerInstitutionId: 'inst-001', full_name: 'Atleta Test' }),
    }),
    set: jest.fn().mockResolvedValue(true),
    batch: jest.fn().mockReturnValue({ set: jest.fn(), commit: jest.fn() }),
    runTransaction: jest.fn().mockImplementation(async (fn: (tx: unknown) => Promise<void>) => {
      const tx = { get: mockTxGet, set: mockTxSet };
      return fn(tx);
    }),
  };
  const firestoreMock: jest.Mock = jest.fn().mockReturnValue(mockDb);
  (firestoreMock as unknown as Record<string, unknown>).FieldValue = {
    serverTimestamp: jest.fn().mockReturnValue('server_timestamp'),
  };
  return {
    firestore: firestoreMock,
    app: jest.fn(),
    initializeApp: jest.fn(),
  };
});

const MASTER_AES_KEY = process.env['MASTER_AES_KEY'] || 'omnisport-ai-super-secret-dev-key';

describe('Dynamic QR Token Engine (Sprint 4)', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // Default: tokenSnap → not used yet; athleteSnap → exists
    mockTxGet
      .mockResolvedValueOnce({ exists: false, data: () => ({}) })
      .mockResolvedValueOnce({
        exists: true,
        data: () => ({ ownerInstitutionId: 'inst-001', full_name: 'Atleta Test' }),
      });
  });

  it('rejects a token that is older than 45 seconds (e.g. 2 minutes)', async () => {
    const uid = 'athlete_123';
    const oldTimestamp = Date.now() - (2 * 60 * 1000); // 2 minutes ago
    const hash = crypto.createHmac('sha256', MASTER_AES_KEY)
      .update(`${uid}:${oldTimestamp}`)
      .digest('hex');

    const req = {
      auth: {
        uid: 'admin_scanner_123',
        token: { role: 'admin', institutionId: 'inst-001' },
      },
      data: { token: `${uid}:${oldTimestamp}:${hash}` },
      rawRequest: null as unknown,
    };

    await expect(
      (validateAttendanceToken as unknown as { run: (r: unknown) => Promise<unknown> }).run(req)
    ).rejects.toMatchObject({
      code: 'deadline-exceeded',
      message: 'El token QR ha expirado.',
    });
  });

  it('accepts a valid, recently generated token', async () => {
    const uid = 'athlete_123';
    const currentTimestamp = Date.now();
    const hash = crypto.createHmac('sha256', MASTER_AES_KEY)
      .update(`${uid}:${currentTimestamp}`)
      .digest('hex');

    const req = {
      auth: {
        uid: 'admin_scanner_123',
        token: { role: 'admin', institutionId: 'inst-001' },
      },
      data: {
        token: `${uid}:${currentTimestamp}:${hash}`,
        action: 'ingreso',
      },
      rawRequest: null as unknown,
    };

    const result = await (validateAttendanceToken as unknown as { run: (r: unknown) => Promise<Record<string, unknown>> }).run(req);

    expect(result['success']).toBe(true);
    expect(typeof result['message']).toBe('string');
    // Both token consumption and attendance log are written atomically via tx.set
    expect(mockTxSet).toHaveBeenCalledTimes(2);
  });

  it('rejects a tampered token (invalid HMAC)', async () => {
    const uid = 'athlete_123';
    const currentTimestamp = Date.now();

    const req = {
      auth: {
        uid: 'admin_scanner_123',
        token: { role: 'admin', institutionId: 'inst-001' },
      },
      data: { token: `${uid}:${currentTimestamp}:deadbeef` },
      rawRequest: null as unknown,
    };

    await expect(
      (validateAttendanceToken as unknown as { run: (r: unknown) => Promise<unknown> }).run(req)
    ).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  it('[Art. 26] rejects a coach trying to validate a token from a different institution', async () => {
    mockTxGet
      .mockReset()
      .mockResolvedValueOnce({ exists: false, data: () => ({}) })
      .mockResolvedValueOnce({
        exists: true,
        data: () => ({ ownerInstitutionId: 'inst-OTHER', full_name: 'Atleta Foráneo' }),
      });

    const uid = 'athlete_123';
    const ts = Date.now();
    const hash = crypto.createHmac('sha256', MASTER_AES_KEY)
      .update(`${uid}:${ts}`)
      .digest('hex');

    const req = {
      auth: {
        uid: 'coach_scanner',
        token: { role: 'coach', institutionId: 'inst-001' },
      },
      data: { token: `${uid}:${ts}:${hash}`, action: 'ingreso' },
      rawRequest: null as unknown,
    };

    await expect(
      (validateAttendanceToken as unknown as { run: (r: unknown) => Promise<unknown> }).run(req)
    ).rejects.toMatchObject({ code: 'permission-denied' });
  });

  it('[C-2] rejects a replayed (already-used) token', async () => {
    mockTxGet
      .mockReset()
      .mockResolvedValueOnce({ exists: true, data: () => ({}) }); // tokenSnap already exists

    const uid = 'athlete_123';
    const ts = Date.now();
    const hash = crypto.createHmac('sha256', MASTER_AES_KEY)
      .update(`${uid}:${ts}`)
      .digest('hex');

    const req = {
      auth: {
        uid: 'admin_scanner_123',
        token: { role: 'admin', institutionId: 'inst-001' },
      },
      data: { token: `${uid}:${ts}:${hash}` },
      rawRequest: null as unknown,
    };

    await expect(
      (validateAttendanceToken as unknown as { run: (r: unknown) => Promise<unknown> }).run(req)
    ).rejects.toMatchObject({ code: 'already-exists' });
    expect(mockTxSet).not.toHaveBeenCalled();
  });
});

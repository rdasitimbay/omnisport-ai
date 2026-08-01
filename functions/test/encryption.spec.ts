import { encryptData, decryptData, hmacForSearch } from '../src/index';

jest.mock('firebase-admin', () => ({
  initializeApp: jest.fn(),
  firestore: jest.fn(() => ({})),
}));

jest.mock('firebase-functions/v2/https', () => ({
  onCall: jest.fn(),
  HttpsError: jest.fn(),
}));

describe('Encryption Module (LOPDP Compliance)', () => {
  // hmacForSearch is deterministic — used for Firestore deduplication index
  it('hmacForSearch returns the same hash for the same input (determinism required for dedup)', () => {
    const input = '1234567890';
    const hash1 = hmacForSearch(input);
    const hash2 = hmacForSearch(input);

    expect(hash1).toBeDefined();
    expect(hash1).not.toBe(input);
    expect(hash1).toBe(hash2);
  });

  it('hmacForSearch normalises whitespace and case before hashing', () => {
    expect(hmacForSearch('1712345678')).toBe(hmacForSearch('  1712345678  '));
    expect(hmacForSearch('abc')).toBe(hmacForSearch('ABC'));
  });

  // encryptData uses a random IV — ciphertext must differ each call (semantic security)
  it('encryptData produces different ciphertext on successive calls (random IV)', () => {
    const input = '1234567890';
    const ct1 = encryptData(input);
    const ct2 = encryptData(input);

    expect(ct1).toBeDefined();
    expect(ct1).not.toBe(input);
    expect(ct1).not.toBe(ct2); // non-deterministic — any equality here is a bug
  });

  it('decryptData(encryptData(x)) === x (round-trip correctness)', () => {
    const plain = 'Dato sensible LOPDP: 1712345678';
    expect(decryptData(encryptData(plain))).toBe(plain);
  });

  it('encryptData returns empty string for empty input', () => {
    expect(encryptData('')).toBe('');
  });

  it('decryptData returns the input unchanged when it contains no colon separator', () => {
    expect(decryptData('not-encrypted')).toBe('not-encrypted');
  });

  it('encryptData produces different outputs for different inputs', () => {
    const ct1 = encryptData('Juan Perez');
    const ct2 = encryptData('Maria Lopez');
    expect(ct1).not.toBe(ct2);
  });
});

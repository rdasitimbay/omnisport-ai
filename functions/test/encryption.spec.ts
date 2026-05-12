import { encryptData } from '../src/index';

jest.mock('firebase-admin', () => ({
  initializeApp: jest.fn(),
  firestore: jest.fn(() => ({})),
}));

jest.mock('firebase-functions/v2/https', () => ({
  onCall: jest.fn(),
  HttpsError: jest.fn(),
}));

describe('Encryption Module (LOPDP Compliance)', () => {
  it('should encrypt data deterministically (same input = same output)', () => {
    const input = '1234567890';
    const hash1 = encryptData(input);
    const hash2 = encryptData(input);
    
    expect(hash1).toBeDefined();
    expect(hash1).not.toBe(input);
    expect(hash1).toBe(hash2); // Determinism check for deduplication
  });

  it('should return empty string if input is empty', () => {
    expect(encryptData('')).toBe('');
  });

  it('should produce different outputs for different inputs', () => {
    const hash1 = encryptData('Juan Perez');
    const hash2 = encryptData('Maria Lopez');
    expect(hash1).not.toBe(hash2);
  });
});

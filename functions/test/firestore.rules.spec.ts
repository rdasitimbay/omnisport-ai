import { assertFails, initializeTestEnvironment, RulesTestEnvironment } from '@firebase/rules-unit-testing';
import * as fs from 'fs';
import * as path from 'path';
import * as net from 'net';

let testEnv: RulesTestEnvironment | null = null;
let emulatorAvailable = false;

async function isPortOpen(host: string, port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    socket.setTimeout(500);
    socket.once('connect', () => { socket.destroy(); resolve(true); });
    socket.once('timeout', () => { socket.destroy(); resolve(false); });
    socket.once('error', () => { socket.destroy(); resolve(false); });
    socket.connect(port, host);
  });
}

beforeAll(async () => {
  emulatorAvailable = await isPortOpen('127.0.0.1', 8080);
  if (!emulatorAvailable) return;

  const rulesPath = path.resolve(__dirname, '../../firestore.rules');
  const rules = fs.readFileSync(rulesPath, 'utf8');

  testEnv = await initializeTestEnvironment({
    projectId: 'omnisport-ai-test',
    firestore: { rules, host: '127.0.0.1', port: 8080 },
  });
});

afterAll(async () => {
  await testEnv?.cleanup();
});

afterEach(async () => {
  await testEnv?.clearFirestore();
});

describe('Firestore Security Rules: LOPDP Access & RBAC Guards', () => {
  it('should deny writing to athletes/private/sensitive_data for non-admin users', async () => {
    if (!emulatorAvailable || !testEnv) {
      console.warn('  ⚠  Firestore emulator not running — skipping rules test (start with: firebase emulators:start --only firestore)');
      return;
    }

    const userContext = testEnv.authenticatedContext('user_123', {
      email: 'user@test.com',
    });

    const db = userContext.firestore();
    const ref = db.collection('athletes').doc('athlete_123').collection('private').doc('sensitive_data');

    await assertFails(ref.set({ dni: 'encrypted_base64_string' }));
  });

  it('should deny a parent user from reading the entire athletes collection (list read)', async () => {
    if (!emulatorAvailable || !testEnv) return;

    // Simulate authenticated parent context
    const parentContext = testEnv.authenticatedContext('parent_123', {
      email: 'parent@test.com',
    });

    const db = parentContext.firestore();
    // Attempting a collection read (list query) without individual athlete limits
    const ref = db.collection('athletes');

    await assertFails(ref.get());
  });
});

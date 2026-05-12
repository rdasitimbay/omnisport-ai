import { assertFails, initializeTestEnvironment, RulesTestEnvironment } from '@firebase/rules-unit-testing';
import * as fs from 'fs';
import * as path from 'path';

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  const rulesPath = path.resolve(__dirname, '../../firestore.rules');
  const rules = fs.readFileSync(rulesPath, 'utf8');
  
  testEnv = await initializeTestEnvironment({
    projectId: 'omnisport-ai-test',
    firestore: {
      rules: rules,
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

describe('Firestore Security Rules: athletes/private (LOPDP)', () => {
  it('should deny writing to athletes/private/sensitive_data for non-admin users', async () => {
    // Contexto de usuario autenticado pero sin rol 'admin'
    const userContext = testEnv.authenticatedContext('user_123', {
      email: 'user@test.com',
      // No tiene rol admin en el token
    });
    
    // Intentamos escribir en la subcolección privada (donde se guarda el DNI cifrado)
    const db = userContext.firestore();
    const ref = db.collection('athletes').doc('athlete_123').collection('private').doc('sensitive_data');
    
    // Debe fallar porque la regla exige request.auth.token.role == 'admin' o que sea el propio servidor (admin SDK)
    await assertFails(ref.set({ dni: 'encrypted_base64_string' }));
  });
});

const admin = require('firebase-admin');
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
admin.initializeApp({ projectId: 'demo-omnisport' });

const db = admin.firestore();

async function seed() {
  await db.collection('app_config').doc('notification_templates').set({
    entry_standard: '¡Hola! {{name}} ha ingresado al entrenamiento de {{sport}} a las {{time}}.',
    exit_standard: '{{name}} ha finalizado su sesión de {{sport}} de forma segura.',
    entry_motivational: '¡Día de acción! {{name}} ya está en la cancha de {{sport}}. ¡A darle con todo!',
    exit_motivational: '¡Excelente esfuerzo! {{name}} ha culminado su sesión de {{sport}}.',
    entry_security: 'Notificación de Seguridad: Ingreso registrado para {{name}} en {{sport}} a las {{time}}.',
    exit_security: 'Notificación de Seguridad: Salida registrada para {{name}} en {{sport}}.'
  });
  console.log('Templates seeded successfully!');
}

seed().catch(console.error);

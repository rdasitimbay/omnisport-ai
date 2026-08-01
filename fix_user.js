const admin = require('firebase-admin');
admin.initializeApp();

const uid = 'QKMTwYj8a0bsA5i9sjSCAxGVycl1';

admin.firestore().collection('users').doc(uid).set({
  email: 'asitimbay.rommel@gmail.com',
  role: 'admin',
  createdAt: admin.firestore.FieldValue.serverTimestamp()
}, { merge: true }).then(() => {
  console.log('User profile created/updated as admin!');
  process.exit(0);
}).catch(err => {
  console.error(err);
  process.exit(1);
});

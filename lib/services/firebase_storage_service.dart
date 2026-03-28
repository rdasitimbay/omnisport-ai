import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebaseStorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Sube una imagen a 'perfiles/{athleteId}.jpg' y actualiza Firestore.
  /// [imageFile] puede ser Uint8List (Web) o String (Path en Móvil).
  Future<String> uploadImage({
    required String athleteId,
    required dynamic imageFile,
    required String fileName,
  }) async {
    try {
      // Verificar sesión antes de subir (evita error 403)
      try {
        if (_auth.currentUser == null) {
          debugPrint("Auth: No hay usuario. Intentando login anónimo...");
          await _auth.signInAnonymously();
        }
      } on FirebaseAuthException catch (authErr) {
        if (authErr.code == 'configuration-not-found') {
          throw Exception('Error de Configuración: Por favor, activa el Inicio de Sesión "Anónimo" en tu consola de Firebase.');
        }
        rethrow;
      }

      final Reference ref = _storage.ref().child('perfiles').child('$athleteId.jpg');

      UploadTask uploadTask;
      
      if (kIsWeb) {
        // En Web usamos putData con metadata para asegurar el tipo MIME
        uploadTask = ref.putData(
          imageFile, 
          SettableMetadata(contentType: 'image/jpeg'),
        );
      } else {
        // En Móvil usamos el path del archivo
        uploadTask = ref.putFile(File(imageFile));
      }

      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      // Actualizar el photoUrl directamente en el documento del atleta en Firestore
      await _firestore.collection('atletas').doc(athleteId).update({
        'photoUrl': downloadUrl,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      return downloadUrl;
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') {
        debugPrint('Aviso: Objeto no encontrado en Storage, continuando...');
        return '';
      }
      debugPrint('Error de Firebase en StorageService: ${e.code}');
      rethrow;
    } catch (e) {
      debugPrint('Error general en FirebaseStorageService: $e');
      throw Exception('Error al procesar la imagen: $e');
    }
  }
}

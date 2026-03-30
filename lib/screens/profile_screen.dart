import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../services/firestore_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'terms_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String athleteId;
  final String athleteName;
  final String? photoBase64;

  const ProfileScreen({
    Key? key,
    required this.athleteId,
    required this.athleteName,
    this.photoBase64,
  }) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  final FirestoreService _firestoreService = FirestoreService();
  
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    // Asegurar sesión activa al cargar el perfil
    _ensureAuth();
  }

  Future<void> _ensureAuth() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
        debugPrint("Perfil: Sesión anónima iniciada.");
      }
    } catch (e) {
      debugPrint("Error asegurando Auth en Perfil: $e");
    }
  }

  Future<void> _showImageSourceActionSheet() async {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Elegir de Galería'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickAndUploadImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Tomar Foto'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickAndUploadImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      // Compresión agresiva para evitar el límite de 1MB de Firestore
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 30, 
        maxWidth: 400,
        maxHeight: 400,
      );
      
      if (image == null) return;

      setState(() => _isUploading = true);

      // Convertir imagen a Base64
      final Uint8List imageBytes = await image.readAsBytes();
      final String base64String = base64Encode(imageBytes);

      // Guardar directamente en Firestore (campo photoBase64)
      await _firestoreService.updateAthleteData(widget.athleteId, {
        'photoBase64': base64String,
        'hasPhoto': true,
      });
      
      setState(() {
        _isUploading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Perfil actualizado con éxito! ✨'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Error al procesar Base64: $e");
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al procesar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '??';
    List<String> parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Mi Perfil', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _firestoreService.getAthleteData(widget.athleteId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final data = snapshot.data!.data() ?? {};
          final String currentPhotoBase64 = data['photoBase64'] ?? widget.photoBase64 ?? '';
          final String currentPhone = data['telefono'] ?? '';

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 40),
                _buildAvatarSection(currentPhotoBase64),
                const SizedBox(height: 24),
                Text(
                  FirebaseAuth.instance.currentUser?.displayName?.isNotEmpty == true
                      ? FirebaseAuth.instance.currentUser!.displayName!
                      : widget.athleteName,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Atleta de Alto Rendimiento',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 48),
                _buildInfoCard(currentPhone),
                const SizedBox(height: 40),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const TermsScreen()),
                    );
                  },
                  child: const Text(
                    'Ver Políticas de Privacidad y Términos',
                    style: TextStyle(color: Colors.grey, decoration: TextDecoration.underline),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => _showDeleteConfirmationDialog(),
                  child: const Text(
                    'Eliminar mi cuenta y mis datos',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildAvatarSection(String currentPhotoBase64) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF003F87), width: 4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 78,
              backgroundColor: const Color(0xFF003F87), // Azul corporativo
              backgroundImage: currentPhotoBase64.isNotEmpty
                  ? MemoryImage(base64Decode(currentPhotoBase64))
                  : null,
              child: currentPhotoBase64.isEmpty
                  ? Text(
                      _getInitials(widget.athleteName),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    )
                  : null,
            ),
          ),
          if (_isUploading)
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          Positioned(
            bottom: 4,
            right: 4,
            child: GestureDetector(
              onTap: _isUploading ? null : _showImageSourceActionSheet,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFF003F87),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String currentPhone) {
    final user = FirebaseAuth.instance.currentUser;
    
    // Si FirebaseAuth tiene un número, usamos ese. Si no, el de Firestore. Si no, vacío.
    String displayPhone = (user?.phoneNumber != null && user!.phoneNumber!.isNotEmpty) 
        ? user.phoneNumber! 
        : currentPhone;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.email_outlined, 'Email', user?.email?.isNotEmpty == true ? user!.email! : 'Sin correo'),
          const Divider(height: 32),
          _buildEditablePhoneRow(displayPhone),
          const Divider(height: 32),
          _buildInfoRow(Icons.calendar_today_outlined, 'Usuario desde', 'Marzo 2026'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF003F87), size: 22),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildEditablePhoneRow(String currentPhone) {
    bool isEmpty = currentPhone.isEmpty;
    return Row(
      children: [
        const Icon(Icons.phone_android_outlined, color: Color(0xFF003F87), size: 22),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Teléfono', style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text(
                isEmpty ? 'Añadir número' : currentPhone,
                style: TextStyle(
                  fontSize: 15, 
                  fontWeight: isEmpty ? FontWeight.normal : FontWeight.w600,
                  fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                  color: isEmpty ? Colors.grey : Colors.black87,
                )
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(isEmpty ? Icons.add_circle_outline : Icons.edit, color: Colors.grey, size: 20),
          onPressed: () => _showEditPhoneDialog(currentPhone),
        )
      ],
    );
  }

  Future<void> _showEditPhoneDialog(String currentPhone) async {
    TextEditingController controller = TextEditingController(text: currentPhone);
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Editar Teléfono', style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: 'Ej. +593 9 123 4567',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newPhone = controller.text.trim();
                await _firestoreService.updateAthleteData(widget.athleteId, {
                  'telefono': newPhone,
                });
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      }
    );
  }

  Future<void> _showDeleteConfirmationDialog() async {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('¿Estás seguro?', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          content: const Text('Esta acción borrará permanentemente tu perfil, fotos y rutinas de entrenamiento.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user != null) {
                    await _firestoreService.deleteAthleteData(user.uid);
                    await user.delete();
                  }
                  
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (route) => false,
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al eliminar: $e. Puede que necesites reconectarte recientemente para esta acción.'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Eliminar'),
            ),
          ],
        );
      }
    );
  }
}

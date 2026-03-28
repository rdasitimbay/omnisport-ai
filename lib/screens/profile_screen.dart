import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../services/firestore_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  
  String? _currentPhotoBase64;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _currentPhotoBase64 = widget.photoBase64;
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

  Future<void> _pickAndUploadImage() async {
    try {
      // Compresión agresiva para evitar el límite de 1MB de Firestore
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
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
        _currentPhotoBase64 = base64String;
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
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 40),
            _buildAvatarSection(),
            const SizedBox(height: 24),
            Text(
              widget.athleteName,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Atleta de Alto Rendimiento',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 48),
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
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
              backgroundImage: (_currentPhotoBase64 != null && _currentPhotoBase64!.isNotEmpty)
                  ? MemoryImage(base64Decode(_currentPhotoBase64!))
                  : null,
              child: (_currentPhotoBase64 == null || _currentPhotoBase64!.isEmpty)
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
              onTap: _isUploading ? null : _pickAndUploadImage,
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

  Widget _buildInfoCard() {
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
          _buildInfoRow(Icons.email_outlined, 'Email', 'juan.perez@atletismo.com'),
          const Divider(height: 32),
          _buildInfoRow(Icons.phone_android_outlined, 'Teléfono', '+593 9 123 4567'),
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
}

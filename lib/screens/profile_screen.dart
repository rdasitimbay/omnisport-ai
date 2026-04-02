import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../services/firestore_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
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
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  final FirestoreService _firestoreService = FirestoreService();
  
  bool _isUploading = false;
  bool _isLoading = true;
  bool _isSaving = false;

  // Form Controllers
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _clubController;
  
  String? _selectedGender;
  DateTime? _selectedDate;
  String _currentPhotoBase64 = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _clubController = TextEditingController(text: 'Santana (Asignado)');
    
    _ensureAuth();
    _loadProfileData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _clubController.dispose();
    super.dispose();
  }

  Future<void> _ensureAuth() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (e) {
      debugPrint("Auth Error: $e");
    }
  }

  Future<void> _loadProfileData() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('athletes').doc(widget.athleteId).get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _nameController.text = data['full_name'] ?? data['nombre_completo'] ?? widget.athleteName;
          _phoneController.text = data['phone'] ?? data['telefono'] ?? '';
          
          final String gender = data['gender'] ?? '';
          if (['Male', 'Female', 'Other'].contains(gender)) {
            _selectedGender = gender;
          }
          
          if (data['birth_date'] != null) {
            _selectedDate = (data['birth_date'] as Timestamp).toDate();
          }
          
          _currentPhotoBase64 = data['photoBase64'] ?? widget.photoBase64 ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading profile: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    
    try {
      Map<String, dynamic> rootData = {
        'full_name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'gender': _selectedGender ?? '',
        'birth_date': _selectedDate != null ? Timestamp.fromDate(_selectedDate!) : null,
      };
      
      Map<String, dynamic> sportData = {
        'sport_type': 'volleyball',
        'club_id': 'Santana',
      };
      
      await _firestoreService.upsertAthleteProfile(widget.athleteId, rootData, sportData);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Perfil guardado exitosamente! ✅'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar datos: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(2005),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF003F87), 
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
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
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 30, 
        maxWidth: 400,
        maxHeight: 400,
      );
      
      if (image == null) return;

      setState(() => _isUploading = true);

      final Uint8List imageBytes = await image.readAsBytes();
      final String base64String = base64Encode(imageBytes);

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
          const SnackBar(content: Text('Foto de perfil actualizada ✨'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
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
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA), // Surface Color M3
        appBar: AppBar(
          title: const Text('Mi Perfil', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : _buildForm(context),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24.0,
        right: 24.0,
        top: 24.0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAvatarSection(),
            const SizedBox(height: 32),
            
            // Sección Datos Personales
            const Text('Datos Personales', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF003F87))),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _nameController,
              decoration: _buildInputDecoration('Nombre Completo', Icons.person_outline),
              validator: (v) => v!.isEmpty ? 'Ingresa tu nombre' : null,
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: _buildInputDecoration('Teléfono Móvil', Icons.phone_outlined),
            ),
            const SizedBox(height: 16),
            
            DropdownButtonFormField<String>(
              value: _selectedGender,
              decoration: _buildInputDecoration('Género', Icons.wc_outlined),
              items: ['Male', 'Female', 'Other']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedGender = val),
            ),
            const SizedBox(height: 16),
            
            InkWell(
              onTap: () => _selectDate(context),
              child: InputDecorator(
                decoration: _buildInputDecoration('Fecha de Nacimiento', Icons.calendar_today_outlined),
                child: Text(
                  _selectedDate == null 
                    ? 'Seleccionar fecha' 
                    : DateFormat('dd / MM / yyyy').format(_selectedDate!),
                  style: TextStyle(color: _selectedDate == null ? Colors.grey[600] : Colors.black87),
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Sección Datos Deportivos
            const Text('Logística Deportiva', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF003F87))),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _clubController,
              readOnly: true,
              decoration: _buildInputDecoration('Club Deportivo', Icons.shield_outlined).copyWith(
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
            
            const SizedBox(height: 60),
            
            // Compliance & Arco
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const TermsScreen()));
                },
                child: const Text(
                  'Ver Políticas de Privacidad y Términos',
                  style: TextStyle(color: Colors.grey, decoration: TextDecoration.underline),
                ),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: _showDeleteConfirmationDialog,
                child: const Text('Eliminar mi cuenta y mis datos', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 32),
            _buildBottomActions(),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF003F87)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF003F87), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );
  }

  Widget _buildAvatarSection() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF003F87), width: 4),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8)),
              ],
            ),
            child: CircleAvatar(
              radius: 68,
              backgroundColor: const Color(0xFF003F87), 
              backgroundImage: _currentPhotoBase64.isNotEmpty
                  ? MemoryImage(base64Decode(_currentPhotoBase64))
                  : null,
              child: _currentPhotoBase64.isEmpty
                  ? Text(_getInitials(widget.athleteName), style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold))
                  : null,
            ),
          ),
          if (_isUploading)
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), shape: BoxShape.circle),
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
          Positioned(
            bottom: 4,
            right: 4,
            child: GestureDetector(
              onTap: _isUploading ? null : _showImageSourceActionSheet,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: Color(0xFF003F87), shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    if (_isLoading) return const SizedBox.shrink();
    
    return ElevatedButton(
      onPressed: _isSaving ? null : _saveProfile,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF003F87),
        disabledBackgroundColor: Colors.grey.shade300,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: _isSaving 
        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
        : const Text('GUARDAR CAMBIOS', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
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
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                try {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user != null) {
                    await _firestoreService.deleteAthleteData(user.uid);
                    try {
                      await GoogleSignIn().signOut();
                      await GoogleSignIn().disconnect();
                    } catch (_) {}
                    await user.delete();
                    await FirebaseAuth.instance.signOut();
                  }
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al eliminar: $e. Reautentícate si es necesario.'), backgroundColor: Colors.red),
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

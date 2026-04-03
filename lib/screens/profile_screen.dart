import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
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
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00E5FF), 
              onPrimary: Colors.black,
              surface: Color(0xFF001F3F),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF001F3F),
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
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(10)), margin: const EdgeInsets.only(bottom: 24)),
                    ListTile(
                      leading: const Icon(CupertinoIcons.photo, color: Colors.white),
                      title: const Text('Elegir de Galería', style: TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.of(context).pop();
                        _pickAndUploadImage(ImageSource.gallery);
                      },
                    ),
                    ListTile(
                      leading: const Icon(CupertinoIcons.camera, color: Colors.white),
                      title: const Text('Tomar Foto', style: TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.of(context).pop();
                        _pickAndUploadImage(ImageSource.camera);
                      },
                    ),
                  ],
                ),
              ),
            ),
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
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('Mi Perfil', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          flexibleSpace: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.white.withOpacity(0.05)),
            ),
          ),
        ),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF001F3F), Color(0xFF00E5FF)],
            ),
          ),
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator(color: Colors.white)) 
            : _buildForm(context),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAvatarSection(),
              const SizedBox(height: 48),
              
              _buildSectionHeader('DATOS PERSONALES'),
              const SizedBox(height: 16),
              
              _buildGlassContainer(
                child: Column(
                  children: [
                    _buildGlassTextField(
                      controller: _nameController,
                      label: 'Nombre Completo',
                      icon: CupertinoIcons.person,
                      validator: (v) => v!.isEmpty ? 'Ingresa tu nombre' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildGlassTextField(
                      controller: _phoneController,
                      label: 'Teléfono Móvil',
                      icon: CupertinoIcons.phone,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),
                    _buildGlassDropdown(),
                    const SizedBox(height: 16),
                    _buildGlassDatePicker(),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              _buildSectionHeader('LOGÍSTICA DEPORTIVA'),
              const SizedBox(height: 16),
              
              _buildGlassContainer(
                child: _buildGlassTextField(
                  controller: _clubController,
                  label: 'Club Deportivo',
                  icon: CupertinoIcons.shield,
                  readOnly: true,
                ),
              ),
              
              const SizedBox(height: 48),
              _buildBottomActions(),
              const SizedBox(height: 24),
              
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const TermsScreen()));
                  },
                  child: Text(
                    'Políticas de Privacidad y Términos',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), decoration: TextDecoration.underline, fontSize: 13),
                  ),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: _showDeleteConfirmationDialog,
                  child: Text('Eliminar cuenta y datos', style: TextStyle(color: Colors.red.withOpacity(0.7), fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF), letterSpacing: 2),
    );
  }

  Widget _buildGlassContainer({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildGlassTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool readOnly = false,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.8), size: 20),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  Widget _buildGlassDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedGender,
      dropdownColor: const Color(0xFF001F3F),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'Género',
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
        prefixIcon: Icon(CupertinoIcons.person_2, color: Colors.white.withOpacity(0.8), size: 20),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
      ),
      items: ['Male', 'Female', 'Other']
          .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(color: Colors.white))))
          .toList(),
      onChanged: (val) => setState(() => _selectedGender = val),
    );
  }

  Widget _buildGlassDatePicker() {
    return InkWell(
      onTap: () => _selectDate(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Fecha de Nacimiento',
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
          prefixIcon: Icon(CupertinoIcons.calendar, color: Colors.white.withOpacity(0.8), size: 20),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
        ),
        child: Text(
          _selectedDate == null 
            ? 'Seleccionar fecha' 
            : DateFormat('dd / MM / yyyy').format(_selectedDate!),
          style: TextStyle(color: _selectedDate == null ? Colors.white38 : Colors.white, fontSize: 15),
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
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 3),
              boxShadow: [
                BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.2), blurRadius: 20, spreadRadius: 2),
              ],
            ),
            child: CircleAvatar(
              radius: 68,
              backgroundColor: Colors.white12,
              backgroundImage: (_currentPhotoBase64.isNotEmpty && _currentPhotoBase64.length > 50)
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
                decoration: const BoxDecoration(color: Color(0xFF00E5FF), shape: BoxShape.circle),
                child: const Icon(CupertinoIcons.camera_fill, color: Colors.black87, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF00E5FF), Color(0xFF00BFA5)],
        ),
        boxShadow: [
          BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _isSaving ? null : _saveProfile,
          child: Center(
            child: _isSaving 
              ? const CircularProgressIndicator(color: Colors.black87)
              : const Text('GUARDAR CAMBIOS', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteConfirmationDialog() async {
    return showDialog(
      context: context,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            backgroundColor: const Color(0xFF001F3F),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.red.withOpacity(0.3))),
            title: const Text('¿Estás seguro?', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            content: const Text('Esta acción borrará permanentemente tu perfil, fotos y rutinas.', style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: Colors.white60))),
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
                        SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.8), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        );
      }
    );
  }
}

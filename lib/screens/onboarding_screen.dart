import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/preferences_service.dart';
import '../l10n/app_localizations.dart';
import 'auth_gateway.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  static const int _totalPages = 4;

  // Consent state (page 3)
  bool _consentPersonal     = false;
  bool _consentSalud        = false;
  bool _consentNotificaciones = false;
  Uint8List? _tutorPhotoBytes;
  bool       _tutorDocIsPdf  = false;
  String?    _tutorDocName;
  bool       _pickingPhoto   = false;

  bool get _allConsentsAccepted =>
      _consentPersonal && _consentSalud && _consentNotificaciones;

  bool get _canProceed =>
      _currentPage < (_totalPages - 1) || _allConsentsAccepted;

  Future<void> _pickTutorPhoto() async {
    setState(() => _pickingPhoto = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true,
      );
      if (result != null && result.files.single.bytes != null && mounted) {
        final file = result.files.single;
        setState(() {
          _tutorPhotoBytes = file.bytes;
          _tutorDocIsPdf   = (file.extension?.toLowerCase() == 'pdf');
          _tutorDocName    = file.name;
        });
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<void> _completeOnboarding() async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();

    // Persist consent timestamps — synced to Firestore post-auth from LopdpVaultScreen.
    await prefs.setBool('consent_datosPersonales', _consentPersonal);
    await prefs.setBool('consent_datosSalud', _consentSalud);
    await prefs.setBool('consent_notificaciones', _consentNotificaciones);
    await prefs.setInt('consent_grantedAtMs', nowMs);
    // El documento del tutor se sube desde la Bóveda LOPDP post-autenticación.
    // En mobile, guardamos la ruta temporal solo si dart:io está disponible.
    if (!kIsWeb && _tutorPhotoBytes != null) {
      await prefs.setBool('tutor_doc_pending', true);
    }

    await PreferencesService().setHasSeenOnboarding(true);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AuthGateway()),
    );
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else if (_allConsentsAccepted) {
      _completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_currentPage < _totalPages - 1)
            TextButton(
              onPressed: _completeOnboarding,
              child: Text(
                loc.skip,
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF001F3F), Color(0xFF00E5FF)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: _currentPage == _totalPages - 1
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    _buildInfoSlide(
                      icon: CupertinoIcons.person,
                      title: loc.onboardingSlide1Title,
                      description: loc.onboardingSlide1Desc,
                    ),
                    _buildInfoSlide(
                      icon: CupertinoIcons.sparkles,
                      title: loc.onboardingSlide2Title,
                      description: loc.onboardingSlide2Desc,
                    ),
                    _buildInfoSlide(
                      icon: CupertinoIcons.lock_shield,
                      title: loc.onboardingSlide3Title,
                      description: loc.onboardingSlide3Desc,
                    ),
                    _buildConsentSlide(),
                  ],
                ),
              ),
              // Progress dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_totalPages, (i) => _buildDot(index: i)),
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canProceed ? _nextPage : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF003F87),
                      disabledBackgroundColor: Colors.white24,
                      disabledForegroundColor: Colors.white38,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 5,
                      shadowColor: Colors.black45,
                    ),
                    child: Text(
                      _currentPage == _totalPages - 1
                          ? 'Aceptar y Empezar'
                          : loc.next,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Slide informativo genérico ────────────────────────────────────────────

  Widget _buildInfoSlide({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 80, color: Colors.white),
                  const SizedBox(height: 32),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Slide 4 — Consentimiento LOPDP ───────────────────────────────────────

  Widget _buildConsentSlide() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_rounded,
                    color: Color(0xFF00E5FF), size: 40),
                const SizedBox(height: 12),
                const Text(
                  'Consentimiento LOPDP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Necesitamos tu autorización para los siguientes tratamientos de datos (Art. 10 LOPDP Ecuador). Puedes revocarlos desde la Bóveda LOPDP en cualquier momento.',
                  style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 20),

                _buildConsentCheckbox(
                  icon: CupertinoIcons.person_crop_circle_fill,
                  title: 'Datos personales y deportivos',
                  description:
                      'Nombre, fotografía, categoría deportiva y membresía de club.',
                  value: _consentPersonal,
                  onChanged: (v) => setState(() => _consentPersonal = v ?? false),
                ),
                const SizedBox(height: 12),

                _buildConsentCheckbox(
                  icon: Icons.favorite_rounded,
                  title: 'Datos de salud y médicos',
                  description:
                      'Estado de aptitud médica y certificaciones de entrenamiento.',
                  value: _consentSalud,
                  onChanged: (v) => setState(() => _consentSalud = v ?? false),
                ),
                const SizedBox(height: 12),

                _buildConsentCheckbox(
                  icon: Icons.notifications_rounded,
                  title: 'Notificaciones al tutor',
                  description:
                      'Alertas de entrada/salida y notificaciones de emergencia.',
                  value: _consentNotificaciones,
                  onChanged: (v) =>
                      setState(() => _consentNotificaciones = v ?? false),
                ),

                const SizedBox(height: 20),
                const Divider(color: Colors.white24),
                const SizedBox(height: 16),

                // Photo upload — opcional
                const Text(
                  'Documento del tutor (opcional)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Fotografía de la cédula del tutor legal para acreditar la autorización.',
                  style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
                ),
                const SizedBox(height: 12),
                _buildPhotoUploadArea(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConsentCheckbox({
    required IconData icon,
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: value
              ? const Color(0xFF00E5FF).withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value
                ? const Color(0xFF00E5FF).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.15),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: value ? const Color(0xFF00E5FF) : Colors.white38,
                size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        color: value ? Colors.white : Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 3),
                  Text(description,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11, height: 1.4)),
                ],
              ),
            ),
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF00E5FF),
              checkColor: const Color(0xFF001F3F),
              side: const BorderSide(color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoUploadArea() {
    return GestureDetector(
      onTap: _pickingPhoto ? null : _pickTutorPhoto,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _tutorPhotoBytes != null
                ? const Color(0xFF00E676).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.15),
            style: BorderStyle.solid,
            width: 1.2,
          ),
        ),
        child: _tutorPhotoBytes != null
            ? Row(
                children: [
                  // Previsualización: imagen o icono PDF
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _tutorDocIsPdf
                        ? Container(
                            width: 56, height: 40,
                            color: Colors.white.withValues(alpha: 0.08),
                            child: const Icon(Icons.picture_as_pdf_rounded,
                                color: Color(0xFFFF7043), size: 24),
                          )
                        : Image.memory(_tutorPhotoBytes!,
                            width: 56, height: 40, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Documento seleccionado',
                            style: TextStyle(
                                color: Color(0xFF00E676),
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        Text(
                          _tutorDocName ?? 'Se subirá al completar el registro',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                    onPressed: () => setState(() {
                      _tutorPhotoBytes = null;
                      _tutorDocName    = null;
                    }),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.upload_file_rounded,
                      color: Colors.white38, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _pickingPhoto ? 'Seleccionando…' : 'Subir cédula tutor (JPG · PNG · PDF)',
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDot({required int index}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 5),
      height: 8,
      width: _currentPage == index ? 24 : 8,
      decoration: BoxDecoration(
        color: _currentPage == index
            ? Colors.white
            : Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

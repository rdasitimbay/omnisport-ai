import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../l10n/app_localizations.dart';
import '../services/preferences_service.dart';
import 'terms_screen.dart';
import 'language_picker_screen.dart';
import 'onboarding_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isLogin = true;
  bool _acceptedTerms = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      UserCredential? userCredential;
      if (kIsWeb) {
        // signInWithPopup devuelve el UserCredential directamente en el mismo await.
        // signInWithRedirect navega fuera de la app y requiere getRedirectResult()
        // en initState para procesar el resultado — mucho más frágil en desarrollo.
        final googleProvider = GoogleAuthProvider();
        userCredential = await FirebaseAuth.instance.signInWithPopup(googleProvider);
      } else {
        final GoogleSignInAccount? googleUser = await GoogleSignIn(
          serverClientId: '430589318678-vvjddb5b9fpieq7dlodcloe1a3fkbtqp.apps.googleusercontent.com',
        ).signIn();
        final GoogleSignInAuthentication? googleAuth = await googleUser?.authentication;
        if (googleAuth != null) {
          final credential = GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );
          userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
        }
      }
      if (userCredential?.user != null) await _ensureUserProfile(userCredential!.user!);
    } on FirebaseAuthException catch (e) {
      final loc = AppLocalizations.of(context);
      String message = loc.loginErrorGoogle;
      if (e.code == 'user-not-found' || e.code == 'invalid-credential' || e.code == 'user-disabled') {
        message = loc.loginErrorGoogleNotFound;
      }
      _showError(message);
    } catch (e) {
      final loc = AppLocalizations.of(context);
      _showError('${loc.loginErrorGoogle}: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _ensureUserProfile(User user) async {
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final docSnap = await docRef.get();
    if (!docSnap.exists) {
      final role = (user.email == 'asitimbay.rommel@gmail.com' || user.email == 'admin@omnisport.ai') ? 'admin' : 'user';
      await docRef.set({
        'email': user.email ?? 'Sin correo',
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // Si aún no hay vínculo con un documento de atleta, intentar el auto-link.
    // La CF linkAthleteAccount busca por email_hash en sensitive_data y guarda
    // el athleteDocId en users/{uid} para que AuthGateway pueda enrutar correctamente.
    final refreshed = await docRef.get();
    if (refreshed.data()?['athleteDocId'] == null &&
        refreshed.data()?['role'] != 'admin') {
      try {
        await FirebaseFunctions.instance
            .httpsCallable('linkAthleteAccount')
            .call();
      } catch (e) {
        debugPrint('linkAthleteAccount: $e');
      }
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _isLoading = true);
    try {
      final appleProvider = AppleAuthProvider();
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithRedirect(appleProvider);
      } else {
        final userCredential = await FirebaseAuth.instance.signInWithProvider(appleProvider);
        if (userCredential.user != null) await _ensureUserProfile(userCredential.user!);
      }
    } catch (e) {
      final loc = AppLocalizations.of(context);
      _showError('${loc.loginErrorApple}: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      final loc = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.loginFillFields)),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        if (userCredential.user != null) await _ensureUserProfile(userCredential.user!);
      } else {
        final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        if (userCredential.user != null) await _ensureUserProfile(userCredential.user!);
      }
    } on FirebaseAuthException catch (e) {
      final loc = AppLocalizations.of(context);
      String message = loc.loginErrorGeneric;
      if (e.code == 'user-not-found') message = loc.loginErrorNotFound;
      if (e.code == 'wrong-password') message = loc.loginErrorWrongPass;
      if (e.code == 'invalid-credential') message = 'Correo o contraseña incorrectos';
      if (e.code == 'email-already-in-use') message = loc.loginErrorEmailUsed;
      if (e.code == 'weak-password') message = loc.loginErrorWeakPass;
      if (e.code == 'operation-not-allowed') {
        message = loc.loginErrorNotAllowed;
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _glassInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.1),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.white, width: 2),
      ),
    );
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
          // Botón debug-only: reinicia onboarding para pruebas
          if (kDebugMode)
            IconButton(
              icon: const Icon(CupertinoIcons.arrow_counterclockwise, color: Colors.white54, size: 22),
              tooltip: 'Reiniciar onboarding (debug)',
              onPressed: () async {
                final prefs = PreferencesService();
                await prefs.setHasSeenOnboarding(false);
                if (!context.mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                );
              },
            ),
          IconButton(
            icon: const Icon(CupertinoIcons.globe, color: Colors.white, size: 28),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LanguagePickerScreen(fromLogin: true)),
              );
            },
          )
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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 80.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Glowing Icon
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.3),
                        blurRadius: 30,
                        spreadRadius: 10,
                      )
                    ],
                  ),
                  child: const Icon(Icons.sports_volleyball, size: 80, color: Colors.white),
                ),
                const SizedBox(height: 16),
                const Text(
                  'OMNISPORT-AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 48),
                
                // Glassmorphism Card
                ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                    child: Container(
                      padding: const EdgeInsets.all(32.0),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2), 
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: Colors.white),
                            decoration: _glassInputDecoration(loc.loginEmailLabel, Icons.email),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            style: const TextStyle(color: Colors.white),
                            decoration: _glassInputDecoration(loc.loginPasswordLabel, Icons.lock),
                          ),
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            value: _acceptedTerms,
                            onChanged: (value) {
                              setState(() => _acceptedTerms = value ?? false);
                            },
                            title: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const TermsScreen()),
                                );
                              },
                              child: Text(
                                loc.loginTerms,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Colors.white,
                                ),
                              ),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            activeColor: Colors.orange, // High contrast
                            checkColor: Colors.black,
                            side: const BorderSide(color: Colors.white, width: 2),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              onPressed: () {
                                if (!_acceptedTerms) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Debes aceptar los términos para continuar'), backgroundColor: Colors.orange),
                                  );
                                  return;
                                }
                                if (!_isLoading) {
                                  debugPrint("--- INTENTANDO LOGIN ---");
                                  _submit();
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF003F87),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 5,
                              ),
                              child: _isLoading 
                                ? const SizedBox(
                                    height: 24, width: 24,
                                    child: CircularProgressIndicator(color: Color(0xFF003F87), strokeWidth: 3),
                                  )
                                : Text(
                                    _isLogin ? loc.loginButton : loc.registerButton,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.3))),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(loc.loginOr, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              ),
                              Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.3))),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _socialButton(
                                icon: Icons.g_mobiledata,
                                color: Colors.white,
                                label: 'Google',
                                onPressed: (_isLoading || !_acceptedTerms) ? null : _signInWithGoogle,
                              ),
                              const SizedBox(width: 20),
                              _socialButton(
                                icon: Icons.apple,
                                color: Colors.white,
                                label: 'Apple',
                                onPressed: (_isLoading || !_acceptedTerms) ? null : _signInWithApple,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          TextButton(
                            onPressed: () => setState(() => _isLogin = !_isLogin),
                            child: Text(
                              _isLogin ? loc.loginToggleRegister : loc.loginToggleLogin,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _socialButton({required IconData icon, required Color color, required String label, VoidCallback? onPressed}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

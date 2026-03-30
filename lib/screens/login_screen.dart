import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter/foundation.dart';
import 'terms_screen.dart';

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
    // La captura de redirección ahora se maneja globalmente en main.dart
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      if (kIsWeb) {
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        await FirebaseAuth.instance.signInWithRedirect(googleProvider);
      } else {
        final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
        final GoogleSignInAuthentication? googleAuth = await googleUser?.authentication;
        if (googleAuth != null) {
          final credential = GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );
          await FirebaseAuth.instance.signInWithCredential(credential);
        }
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Error al ingresar con Google';
      if (e.code == 'user-not-found' || e.code == 'invalid-credential' || e.code == 'user-disabled') {
        message = 'Cuenta no encontrada o inválida. Por favor, regístrate de nuevo';
      }
      _showError(message);
    } catch (e) {
      _showError('Error al ingresar con Google: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _isLoading = true);
    try {
      final appleProvider = AppleAuthProvider();
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithRedirect(appleProvider);
      } else {
        await FirebaseAuth.instance.signInWithProvider(appleProvider);
      }
    } catch (e) {
      _showError('Error al ingresar con Apple: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor completa todos los campos')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Ocurrió un error';
      if (e.code == 'user-not-found') message = 'Cuenta no encontrada. Por favor, regístrate de nuevo';
      if (e.code == 'wrong-password') message = 'Contraseña incorrecta';
      if (e.code == 'email-already-in-use') message = 'El email ya está en uso';
      if (e.code == 'weak-password') message = 'La contraseña es muy débil';
      if (e.code == 'operation-not-allowed') {
        message = '¡Error! Debes habilitar Email/Password en la consola de Firebase.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF003F87), Color(0xFF001F44)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sports_volleyball, size: 80, color: Colors.white),
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
                const SizedBox(height: 32),
                Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Correo Electrónico',
                            prefixIcon: Icon(Icons.email),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: Icon(Icons.lock),
                          ),
                        ),
                        const SizedBox(height: 8),
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
                            child: const Text(
                              'He leído y acepto los Términos de Uso y Política de Privacidad',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          activeColor: const Color(0xFF003F87),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: (_isLoading || !_acceptedTerms) ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF003F87),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isLoading 
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(_isLogin ? 'Iniciar Sesión' : 'Crear Cuenta'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text('O ingresar con', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _socialButton(
                              icon: Icons.g_mobiledata,
                              color: Colors.red,
                              label: 'Google',
                              onPressed: (_isLoading || !_acceptedTerms) ? null : _signInWithGoogle,
                            ),
                            const SizedBox(width: 20),
                            _socialButton(
                              icon: Icons.apple,
                              color: Colors.black,
                              label: 'Apple',
                              onPressed: (_isLoading || !_acceptedTerms) ? null : _signInWithApple,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => setState(() => _isLogin = !_isLogin),
                          child: Text(_isLogin ? '¿No tienes cuenta? Regístrate' : '¿Ya tienes cuenta? Ingresa'),
                        ),
                      ],
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
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_service.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Watercolor Palette
  final Color _paperColor = const Color(0xFFFAFAF5);
  final Color _textCharcoal = const Color(0xFF2C2C2C);
  final Color _watercolorOrange = const Color(0xFFFBE4D5); // Apricot wash

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);

    try {
      await authService.signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      // Main will handle navigation via AuthGate
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Login Error: ${e.toString()}")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paperColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Minimalist Logo
                 Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _watercolorOrange.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.restaurant_menu_rounded, size: 40, color: Colors.brown.shade400),
                ),
                const SizedBox(height: 32),
                
                Text(
                  "Welcome Back",
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: _textCharcoal,
                    height: 1.1
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Sign in to continue your culinary journey",
                  style: GoogleFonts.lato(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                    height: 1.5
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04), // Softer shadow
                        blurRadius: 32,
                        offset: const Offset(0, 16),
                      )
                    ],
                  ),
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildInputLabel("Email"),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _emailController,
                          decoration: _buildInputDecoration(hint: "hello@gmail.com", icon: Icons.email_outlined),
                          validator: (value) => value == null || value.isEmpty ? 'Please enter your email' : null,
                        ),
                        const SizedBox(height: 24),
                        
                        _buildInputLabel("Password"),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          decoration: _buildInputDecoration(hint: "••••••••", icon: Icons.lock_outline),
                          obscureText: true,
                          validator: (value) => value == null || value.isEmpty ? 'Please enter your password' : null,
                        ),
                        const SizedBox(height: 32),
                        
                        // Primary Login Button
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFCCBC), Color(0xFFFFAB91)], // Apricot to Coral
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withValues(alpha: 0.2),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _isLoading
                                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text("Log In", style: GoogleFonts.lato(fontSize: 16, fontWeight: FontWeight.bold, color: _textCharcoal)),
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Google Sign In Button (styled to match)
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _isLoading
                                  ? null
                                  : () async {
                                      final authService = Provider.of<AuthService>(context, listen: false);
                                      try {
                                        await authService.signInWithGoogle();
                                      } catch (e) {
                                        // Silent catch
                                      }
                                    },
                              borderRadius: BorderRadius.circular(16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    'assets/images/google_logo.png',
                                    width: 24,
                                    height: 24,
                                    errorBuilder: (_, __, ___) => const Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    "Sign in with Google",
                                    style: GoogleFonts.lato(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: _textCharcoal,
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
                
                const SizedBox(height: 32),
                
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SignupScreen()),
                    );
                  },
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.lato(color: Colors.grey.shade600, fontSize: 14),
                      children: [
                        const TextSpan(text: "Don't have an account? "),
                        TextSpan(text: "Sign Up", style: TextStyle(color: Colors.brown.shade400, fontWeight: FontWeight.bold)),
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

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.lato(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: _textCharcoal,
      ),
    );
  }

  InputDecoration _buildInputDecoration({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade100),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.orange.shade200, width: 1.5),
      ),
    );
  }
}

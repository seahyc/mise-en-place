import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Watercolor Palette
  final Color _paperColor = const Color(0xFFFAFAF5);
  final Color _textCharcoal = const Color(0xFF2C2C2C);
  final Color _watercolorOrange = const Color(0xFFFBE4D5); // Apricot wash

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Passwords do not match")),
        );
        return;
    }

    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);

    try {
      await authService.signUp(
        _emailController.text.trim(),
        _passwordController.text.trim(),
        displayName: _nameController.text.trim(),
      );
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Account created! Please log in.")),
        );
        Navigator.pop(context); // Go back to login
      }
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
          SnackBar(content: Text("Signup Error: ${e.toString()}")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paperColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        elevation: 0,
        iconTheme: IconThemeData(color: _textCharcoal),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _watercolorOrange.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person_add_alt_1_rounded, size: 40, color: Colors.brown.shade400),
                ),
                const SizedBox(height: 24),

                Text(
                  "Join Mise en Place",
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: _textCharcoal,
                    height: 1.1
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Create an account to save recipes and track your progress",
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
                        color: Colors.black.withValues(alpha: 0.04),
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
                        _buildInputLabel("First Name"),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _nameController,
                          decoration: _buildInputDecoration(hint: "What should the chef call you?", icon: Icons.person_outline),
                          validator: (value) => value == null || value.isEmpty ? 'Please enter your name' : null,
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 24),

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
                          validator: (value) => value == null || value.length < 6 ? 'Password must be at least 6 chars' : null,
                        ),
                        const SizedBox(height: 24),

                        _buildInputLabel("Confirm Password"),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _confirmPasswordController,
                          decoration: _buildInputDecoration(hint: "••••••••", icon: Icons.lock_outline),
                          obscureText: true,
                          validator: (value) => value == null || value.isEmpty ? 'Please confirm your password' : null,
                        ),
                        const SizedBox(height: 32),
                        
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
                            onPressed: _isLoading ? null : _signup,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _isLoading
                                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text("Sign Up", style: GoogleFonts.lato(fontSize: 16, fontWeight: FontWeight.bold, color: _textCharcoal)),
                          ),
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

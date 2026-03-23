import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      await ref.read(authServiceProvider).login(
            _emailController.text.trim(),
            _passwordController.text,
          );
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      // Google Sign-In integration will be completed in a later task.
      // For now, show a placeholder message.
      setState(() => _error = 'Google Sign-In not yet configured');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  RichText(
                    textAlign: TextAlign.center,
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w300,
                        letterSpacing: -0.5,
                      ),
                      children: [
                        TextSpan(text: 'mise '),
                        TextSpan(
                          text: 'en',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.amber,
                          ),
                        ),
                        TextSpan(text: ' place'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Email field
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'Email'),
                  ),
                  const SizedBox(height: 12),

                  // Password field
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _signIn(),
                    decoration: const InputDecoration(hintText: 'Password'),
                  ),
                  const SizedBox(height: 8),

                  // Error text
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ],

                  const SizedBox(height: 16),

                  // Sign In button
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _signIn,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Text('Sign In'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Google sign in
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _loading ? null : _signInWithGoogle,
                      child: const Text('Sign in with Google'),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Create account link
                  TextButton(
                    onPressed: () => context.go('/auth/register'),
                    child: const Text(
                      'Create account',
                      style: TextStyle(
                        color: AppColors.amber,
                        fontSize: 14,
                      ),
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
}

import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import 'admin_reset_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (password.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await AuthService.instance.loginAsAdmin(password);
      if (!ok) {
        setState(() => _error = 'Mot de passe incorrect.');
      } else if (mounted) {
        // AuthGate has already swapped its child to HomeShell underneath —
        // but this screen was reached via Navigator.push, so it's sitting
        // on top of that route hiding it. Pop back to the root to reveal it.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      setState(() => _error = 'Erreur de connexion : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openReset() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminResetScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administrateur')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppLogo(size: 56),
              const SizedBox(height: 24),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                autofocus: true,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Mot de passe administrateur',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black),
                        )
                      : const Text('Se connecter'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loading ? null : _openReset,
                child: const Text('Mot de passe oublié ?'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
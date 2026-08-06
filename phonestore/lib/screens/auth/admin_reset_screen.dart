import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class AdminResetScreen extends StatefulWidget {
  const AdminResetScreen({super.key});

  @override
  State<AdminResetScreen> createState() => _AdminResetScreenState();
}

enum _Step { request, confirm }

class _AdminResetScreenState extends State<AdminResetScreen> {
  _Step _step = _Step.request;
  bool _loading = false;
  String? _error;
  String? _info;

  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await AuthService.instance.requestAdminPasswordReset();
      setState(() {
        _step = _Step.confirm;
        _info = 'Un code a été envoyé sur WhatsApp au numéro enregistré.';
      });
    } catch (e) {
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    final code = _codeController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (code.length != 6) {
      setState(() => _error = 'Le code doit contenir 6 chiffres.');
      return;
    }
    if (newPassword.length < 4) {
      setState(() => _error = 'Le mot de passe doit contenir au moins 4 caractères.');
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await AuthService.instance.confirmAdminPasswordReset(
        code: code,
        newPassword: newPassword,
      );
      if (!ok) {
        setState(() => _error = 'Code invalide ou expiré. Demandez-en un nouveau.');
      } else if (mounted) {
        // Same reasoning as AdminLoginScreen: this screen (and the login
        // screen beneath it) were both reached via Navigator.push, so they
        // sit on top of the route AuthGate actually swapped. Pop both away.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _step == _Step.request ? _buildRequestStep() : _buildConfirmStep(),
        ),
      ),
    );
  }

  Widget _buildRequestStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.chat_outlined, size: 48, color: AppColors.gold),
        const SizedBox(height: 16),
        const Text(
          'Un code à 6 chiffres sera envoyé par WhatsApp au numéro administrateur enregistré.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.grey),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _loading ? null : _requestCode,
          child: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black))
              : const Text('Envoyer le code'),
        ),
      ],
    );
  }

  Widget _buildConfirmStep() {
    return ListView(
      children: [
        const SizedBox(height: 12),
        if (_info != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppColors.success, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_info!, style: const TextStyle(color: AppColors.success, fontSize: 13))),
              ],
            ),
          ),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: 'Code reçu sur WhatsApp', counterText: ''),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newPasswordController,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Nouveau mot de passe',
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscure,
          decoration: const InputDecoration(labelText: 'Confirmer le mot de passe'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _loading ? null : _confirm,
          child: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black))
              : const Text('Confirmer'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _loading ? null : _requestCode,
          child: const Text('Renvoyer le code'),
        ),
      ],
    );
  }
}
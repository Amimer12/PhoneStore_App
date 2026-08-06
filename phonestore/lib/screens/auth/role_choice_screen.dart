import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import 'admin_login_screen.dart';

/// Only ever shown once per device install: after a role is claimed,
/// AuthGate never routes back here unless the person explicitly signs out.
class RoleChoiceScreen extends StatefulWidget {
  const RoleChoiceScreen({super.key});

  @override
  State<RoleChoiceScreen> createState() => _RoleChoiceScreenState();
}

class _RoleChoiceScreenState extends State<RoleChoiceScreen> {
  bool _loadingWorker = false;

  Future<void> _continueAsWorker() async {
    setState(() => _loadingWorker = true);
    try {
      await AuthService.instance.continueAsWorker();
      // AuthGate is listening to roleNotifier — no navigation call needed.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur de connexion : $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingWorker = false);
    }
  }

  void _continueAsAdmin() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminLoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppLogo(size: 72),
              const SizedBox(height: 20),
              Text(
                'Bienvenue',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppColors.white),
              ),
              const SizedBox(height: 6),
              const Text(
                'Comment souhaitez-vous continuer ?',
                style: TextStyle(color: AppColors.grey),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loadingWorker ? null : _continueAsWorker,
                  icon: _loadingWorker
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black),
                        )
                      : const Icon(Icons.badge_outlined),
                  label: const Text('Continuer en tant qu\'employé'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loadingWorker ? null : _continueAsAdmin,
                  icon: const Icon(Icons.admin_panel_settings_outlined, color: AppColors.white),
                  label: const Text('Continuer en tant qu\'administrateur', style: TextStyle(color: AppColors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.gold),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

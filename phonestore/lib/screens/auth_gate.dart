import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import 'auth/role_choice_screen.dart';
import 'home_shell.dart';

/// Sits at the very top of the widget tree (see main.dart). Listens to
/// [AuthService.roleNotifier] so any sign-in, sign-out, or role change from
/// anywhere in the app swaps the visible screen automatically — no manual
/// Navigator calls needed from the auth screens themselves.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    AuthService.instance.bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuthService.instance.bootstrapping,
      builder: (context, bootstrapping, _) {
        if (bootstrapping) {
          return const Scaffold(
            backgroundColor: AppColors.black,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppLogo(size: 64),
                  SizedBox(height: 20),
                  CircularProgressIndicator(color: AppColors.gold),
                ],
              ),
            ),
          );
        }
        return ValueListenableBuilder<AppRole?>(
          valueListenable: AuthService.instance.roleNotifier,
          builder: (context, role, _) {
            if (role == null) return const RoleChoiceScreen();
            return HomeShell(role: role);
          },
        );
      },
    );
  }
}

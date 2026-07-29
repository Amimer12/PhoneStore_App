import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Reserves a spot for the shop's logo everywhere the app shows branding
/// (login screen, app bars). Drop a file at `assets/logo.png` and declare it
/// under `flutter: assets:` in pubspec.yaml to have it picked up automatically
/// — until then this renders a plain storefront icon so nothing looks broken.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo.png',
      height: size,
      width: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(Icons.storefront_outlined, color: AppColors.gold, size: size),
    );
  }
}

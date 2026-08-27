import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/permissions_service.dart';
import '../models/worker_permissions.dart';
import 'products/products_screen.dart';
import 'achats/achats_screen.dart';
import 'depenses/depenses_screen.dart';
import 'analyse/analyse_screen.dart';
import 'permissions/permissions_screen.dart';

class HomeShell extends StatefulWidget {
  final AppRole role;
  const HomeShell({super.key, required this.role});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  bool get _isAdmin => widget.role == AppRole.admin;

  @override
  Widget build(BuildContext context) {
    // Rebuilds whenever PermissionsService's snapshot changes (e.g. right
    // after the admin saves the Permissions screen), so the tab list — not
    // just what's inside each tab — stays in sync with what the current
    // role is actually allowed to see.
    return ValueListenableBuilder<WorkerPermissions>(
      valueListenable: PermissionsService.instance.notifier,
      builder: (context, _, __) {
        final perms = PermissionsService.instance;

        // Produits and Ventes are always present — a worker must always be
        // able to see products and sales, no matter what the admin
        // configures (see WorkerPermissions doc). Dépenses and Analyse are
        // the two sections with a real "view" toggle, so they only show up
        // when that toggle (or admin) allows it. Permissions is admin-only.
        final screens = [
          const ProductsScreen(),
          const AchatsScreen(),
          if (perms.canViewDepense) const DepensesScreen(),
          if (perms.canViewAnalyse) const AnalyseScreen(),
          if (_isAdmin) const PermissionsScreen(),
        ];

        final destinations = [
          const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Produits'),
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Ventes'),
          if (perms.canViewDepense)
            const NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Dépenses'),
          if (perms.canViewAnalyse)
            const NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Analyse'),
          if (_isAdmin)
            const NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), selectedIcon: Icon(Icons.admin_panel_settings), label: 'Permissions'),
        ];

        // If a role/permission change ever shrinks the tab count while a
        // later tab was selected, clamp back to a valid index instead of
        // crashing.
        final safeIndex = _index >= screens.length ? 0 : _index;

        return Scaffold(
          body: IndexedStack(index: safeIndex, children: screens),
          bottomNavigationBar: NavigationBar(
            selectedIndex: safeIndex,
            onDestinationSelected: (i) => setState(() => _index = i),
            backgroundColor: AppColors.black,
            destinations: destinations,
          ),
        );
      },
    );
  }
}

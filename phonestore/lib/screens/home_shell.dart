import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import 'products/products_screen.dart';
import 'achats/achats_screen.dart';
import 'depenses/depenses_screen.dart';
import 'analyse/analyse_screen.dart';

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
    // Workers never get an Analyse tab, and Produits opens in read-only
    // mode for them (see ProductsScreen's isAdmin flag) — everything else
    // (Achats, Dépenses) is identical for both roles.
    final screens = [
      ProductsScreen(isAdmin: _isAdmin),
      const AchatsScreen(),
      const DepensesScreen(),
      if (_isAdmin) const AnalyseScreen(),
    ];

    final destinations = [
      const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Produits'),
      const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Achats'),
      const NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Dépenses'),
      if (_isAdmin) const NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Analyse'),
    ];

    // If a role switch ever shrinks the tab count while a later tab was
    // selected, clamp back to a valid index instead of crashing.
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
  }
}

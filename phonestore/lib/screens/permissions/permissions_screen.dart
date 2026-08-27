import 'package:flutter/material.dart';
import '../../models/worker_permissions.dart';
import '../../services/permissions_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';

/// Admin-only. Lets the admin decide what a worker can view/add/modify/
/// delete in each of the app's 5 sections. Backed by the single
/// `worker_permissions` row — see worker_permissions.sql and
/// WorkerPermissions for the model.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  final _service = PermissionsService.instance;

  // Local editable draft — only written back to the server (and to
  // PermissionsService's own notifier) when "Enregistrer" is tapped, so a
  // half-finished edit never partially takes effect.
  late WorkerPermissions _draft;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _service.load();
    if (!mounted) return;
    setState(() {
      _draft = _service.current;
      _loading = false;
      _dirty = false;
    });
  }

  void _update(WorkerPermissions Function(WorkerPermissions) change) {
    setState(() {
      _draft = change(_draft);
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.save(_draft);
      if (!mounted) return;
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissions enregistrées')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(padding: EdgeInsets.all(10), child: AppLogo(size: 26)),
        title: const Text('Permissions'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                const Text(
                  "Ce que l'employé peut faire dans chaque section. L'accès en "
                  "consultation aux Produits et aux Ventes reste toujours actif, "
                  "quel que soit le réglage ci-dessous.",
                  style: TextStyle(color: AppColors.grey, fontSize: 12.5),
                ),
                const SizedBox(height: 20),
                _SectionCard(
                  title: 'Catalogue',
                  subtitle: 'Catégories, types et marques',
                  icon: Icons.category_outlined,
                  rows: [
                    _PermRow(
                      label: 'Voir',
                      value: _draft.catalogView,
                      onChanged: (v) => _update((p) => p.copyWith(catalogView: v)),
                    ),
                    _PermRow(
                      label: 'Ajouter',
                      value: _draft.catalogAdd,
                      onChanged: (v) => _update((p) => p.copyWith(catalogAdd: v)),
                    ),
                    _PermRow(
                      label: 'Modifier',
                      value: _draft.catalogModify,
                      onChanged: (v) => _update((p) => p.copyWith(catalogModify: v)),
                    ),
                    _PermRow(
                      label: 'Supprimer',
                      value: _draft.catalogDelete,
                      onChanged: (v) => _update((p) => p.copyWith(catalogDelete: v)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Produits',
                  subtitle: 'La consultation reste toujours activée',
                  icon: Icons.inventory_2_outlined,
                  rows: [
                    const _PermRow(label: 'Voir', value: true, onChanged: null, locked: true),
                    _PermRow(
                      label: 'Ajouter',
                      value: _draft.productAdd,
                      onChanged: (v) => _update((p) => p.copyWith(productAdd: v)),
                    ),
                    _PermRow(
                      label: 'Modifier',
                      value: _draft.productModify,
                      onChanged: (v) => _update((p) => p.copyWith(productModify: v)),
                    ),
                    _PermRow(
                      label: 'Supprimer',
                      value: _draft.productDelete,
                      onChanged: (v) => _update((p) => p.copyWith(productDelete: v)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Ventes',
                  subtitle: 'Achats — la consultation reste toujours activée',
                  icon: Icons.receipt_long_outlined,
                  rows: [
                    const _PermRow(label: 'Voir', value: true, onChanged: null, locked: true),
                    _PermRow(
                      label: 'Ajouter',
                      value: _draft.ventesAdd,
                      onChanged: (v) => _update((p) => p.copyWith(ventesAdd: v)),
                    ),
                    _PermRow(
                      label: 'Modifier',
                      value: _draft.ventesModify,
                      onChanged: (v) => _update((p) => p.copyWith(ventesModify: v)),
                    ),
                    _PermRow(
                      label: 'Supprimer',
                      value: _draft.ventesDelete,
                      onChanged: (v) => _update((p) => p.copyWith(ventesDelete: v)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Dépenses',
                  icon: Icons.payments_outlined,
                  rows: [
                    _PermRow(
                      label: 'Voir',
                      value: _draft.depenseView,
                      onChanged: (v) => _update((p) => p.copyWith(depenseView: v)),
                    ),
                    _PermRow(
                      label: 'Ajouter',
                      value: _draft.depenseAdd,
                      onChanged: (v) => _update((p) => p.copyWith(depenseAdd: v)),
                    ),
                    _PermRow(
                      label: 'Modifier',
                      value: _draft.depenseModify,
                      onChanged: (v) => _update((p) => p.copyWith(depenseModify: v)),
                    ),
                    _PermRow(
                      label: 'Supprimer',
                      value: _draft.depenseDelete,
                      onChanged: (v) => _update((p) => p.copyWith(depenseDelete: v)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Analyse',
                  subtitle: 'Une seule permission : consultation',
                  icon: Icons.bar_chart_outlined,
                  rows: [
                    _PermRow(
                      label: 'Voir',
                      value: _draft.analyseView,
                      onChanged: (v) => _update((p) => p.copyWith(analyseView: v)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_dirty && !_saving) ? _save : null,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Enregistrement...' : 'Enregistrer'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<_PermRow> rows;

  const _SectionCard({required this.title, this.subtitle, required this.icon, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEBE5)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.gold),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(subtitle!, style: const TextStyle(color: AppColors.grey, fontSize: 11.5)),
            ),
          ],
          const SizedBox(height: 4),
          ...rows,
        ],
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool locked;

  const _PermRow({required this.label, required this.value, required this.onChanged, this.locked = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 13.5)),
              if (locked) ...[
                const SizedBox(width: 6),
                const Icon(Icons.lock_outline, size: 13, color: AppColors.grey),
              ],
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: locked ? null : onChanged,
          activeColor: AppColors.gold,
        ),
      ],
    );
  }
}

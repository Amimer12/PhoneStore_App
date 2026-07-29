import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../../models/depense.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';

class DepensesScreen extends StatefulWidget {
  const DepensesScreen({super.key});

  @override
  State<DepensesScreen> createState() => _DepensesScreenState();
}

class _DepensesScreenState extends State<DepensesScreen> {
  final _service = SupabaseService.instance;
  List<Depense> _depenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _depenses = await _service.getDepenses();
    setState(() => _loading = false);
  }

  int get _total => _depenses.fold(0, (s, d) => s + d.prix);

  Future<void> _openForm({Depense? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final prixCtrl = TextEditingController(text: existing?.prix.toString() ?? '');
    DateTime date = existing?.date ?? DateTime.now();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(existing == null ? 'Nouvelle dépense' : 'Modifier la dépense'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: prixCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Prix (DA) *'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text(DateFormat('dd/MM/yyyy').format(date))),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setSt(() => date = picked);
                    },
                    child: const Text('Changer'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final prix = int.tryParse(prixCtrl.text.trim());
                if (name.isEmpty || prix == null) return;
                await _service.upsertDepense(
                  id: existing?.id,
                  depense: Depense(id: existing?.id, name: name, prix: prix, date: date),
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _confirmDelete(Depense d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer cette dépense ?'),
        content: Text('${d.name} · ${d.prix} DA'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && d.id != null) {
      await _service.deleteDepense(d.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(padding: EdgeInsets.all(10), child: AppLogo(size: 26)),
        title: const Text('Dépenses'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: AppColors.black, borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total dépenses', style: TextStyle(color: AppColors.grey, fontSize: 12)),
                        Text('$_total DA',
                            style: const TextStyle(color: AppColors.gold, fontSize: 22, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _depenses.isEmpty
                      ? const Center(child: Text('Aucune dépense', style: TextStyle(color: AppColors.grey)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppColors.gold,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: _depenses.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final d = _depenses[i];
                              return Card(
                                child: ListTile(
                                  title: Text(d.name),
                                  subtitle: Text(DateFormat('dd MMM yyyy').format(d.date),
                                      style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('${d.prix} DA', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                                        onPressed: () => _confirmDelete(d),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _openForm(existing: d),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

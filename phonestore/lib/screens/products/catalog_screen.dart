import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/category.dart';
import '../../models/marque.dart';
import '../../models/product_type.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/category_icons.dart';
import 'product_form.dart' show pickCompressedImage;

/// Lets the admin manage the taxonomy that products depend on:
/// Categories (icon-based, no upload) -> Types (type1, optional type2,
/// optional photo) -> Marques (name only, no image).
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catalogue'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.gold,
          labelColor: AppColors.gold,
          unselectedLabelColor: AppColors.grey,
          tabs: const [
            Tab(text: 'Catégories'),
            Tab(text: 'Types'),
            Tab(text: 'Marques'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _CategoriesTab(),
          _TypesTab(),
          _MarquesTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Categories tab — icon-based, no image upload
// ---------------------------------------------------------------------
class _CategoriesTab extends StatefulWidget {
  const _CategoriesTab();
  @override
  State<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<_CategoriesTab> {
  final _service = SupabaseService.instance;
  List<Category> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _items = await _service.getCategories();
    setState(() => _loading = false);
  }

  Future<void> _openDialog({Category? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    String iconKey = existing?.iconKey ?? 'category';
    CategoryMode mode = existing?.mode ?? CategoryMode.hierarchical;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(existing == null ? 'Nouvelle catégorie' : 'Modifier la catégorie'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom')),
                const SizedBox(height: 16),
                const Align(alignment: Alignment.centerLeft, child: Text('Icône', style: TextStyle(color: AppColors.grey, fontSize: 12))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: kCategoryIcons.entries.map((e) {
                    final selected = iconKey == e.key;
                    return GestureDetector(
                      onTap: () => setSt(() => iconKey = e.key),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? AppColors.black : AppColors.offWhite,
                          border: Border.all(color: selected ? AppColors.gold : Colors.transparent, width: 1.6),
                        ),
                        child: Icon(e.value, color: selected ? AppColors.gold : AppColors.black, size: 20),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Align(alignment: Alignment.centerLeft, child: Text('Comportement', style: TextStyle(color: AppColors.grey, fontSize: 12))),
                const SizedBox(height: 8),
                _CategoryModeSelector(current: mode, onChanged: (m) => setSt(() => mode = m)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                await _service.upsertCategory(id: existing?.id, name: nameCtrl.text.trim(), iconKey: iconKey, mode: mode);
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: () => _openDialog(), child: const Icon(Icons.add)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final c = _items[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.offWhite,
                      child: Icon(iconForKey(c.iconKey), color: AppColors.black),
                    ),
                    title: Text(c.name),
                    subtitle: Text(_modeLabel(c.mode), style: const TextStyle(fontSize: 11, color: AppColors.grey)),
                    onTap: () => _openDialog(existing: c),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      onPressed: () async {
                        try {
                          await _service.deleteCategory(c.id);
                          _load();
                        } on PostgrestException catch (e) {
                          if (!context.mounted) return;
                          final message = e.code == '23503'
                              ? 'Cette catégorie contient encore des types ou des produits — supprimez-les d\'abord.'
                              : 'Erreur Supabase (${e.code ?? '?'}): ${e.message}';
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                        }
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------
// Types tab (category -> type1 -> optional type2, browsed level by level)
// Photos stay optional here — this is the one place a picture genuinely
// helps recognition (chargers, cables, telecom logos, etc).
// ---------------------------------------------------------------------
Widget _typeThumb(String? url, Uint8List? bytes) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: SizedBox(
      width: 40,
      height: 40,
      child: bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover)
          : (url != null
              ? Image.network(url, fit: BoxFit.cover)
              : Container(color: AppColors.offWhite, child: const Icon(Icons.image_outlined, color: AppColors.grey, size: 16))),
    ),
  );
}

class _TypesTab extends StatefulWidget {
  const _TypesTab();
  @override
  State<_TypesTab> createState() => _TypesTabState();
}

class _TypesTabState extends State<_TypesTab> {
  final _service = SupabaseService.instance;
  List<Category> _categories = [];
  int? _categoryId;

  // breadcrumb of selected parents, one entry per level already drilled into
  // (hierarchical mode only)
  final List<ProductType> _path = [];
  List<ProductType> _current = [];

  // perfume mode: just the flat list of bottle sizes (with their price).
  // Perfume products themselves are identified by marque (see Marques tab),
  // not by a type1/type2 pair anymore.
  List<ProductType> _tailles = [];

  bool _loading = true;

  Category? get _category {
    final c = _categories.where((c) => c.id == _categoryId);
    return c.isEmpty ? null : c.first;
  }

  CategoryMode? get _mode => _category?.mode;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _categories = await _service.getCategories();
    setState(() => _loading = false);
  }

  Future<void> _selectCategory(int? id) async {
    setState(() {
      _categoryId = id;
      _path.clear();
      _current = [];
      _tailles = [];
    });
    if (id == null) return;
    final c = _categories.firstWhere((c) => c.id == id);
    if (c.mode == CategoryMode.perfume) {
      await _reloadPerfumeLists();
    } else {
      _current = await _service.getTypes(categoryId: id, topLevelOnly: true, level: 1);
      setState(() {});
    }
  }

  Future<void> _reloadPerfumeLists() async {
    if (_categoryId == null) return;
    _tailles = await _service.getTypes(categoryId: _categoryId, topLevelOnly: true, level: 2);
    setState(() {});
  }

  bool get _isFlatMode => _mode == CategoryMode.simple || _mode == CategoryMode.repair;

  Future<void> _drillInto(ProductType t) async {
    if (_isFlatMode) {
      // Simple/repair categories are a single flat level — no sous-types.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ce type ne peut pas avoir de sous-types.'),
      ));
      return;
    }
    if (_path.length >= 1) return; // max depth: type1 -> type2 (two levels only)
    setState(() => _path.add(t));
    _current = await _service.getTypes(parentId: t.id);
    setState(() {});
  }

  void _goBack() {
    setState(() {
      _path.removeLast();
    });
    _reloadCurrent();
  }

  Future<void> _reloadCurrent() async {
    if (_path.isEmpty) {
      _current = _categoryId == null ? [] : await _service.getTypes(categoryId: _categoryId, topLevelOnly: true, level: 1);
    } else {
      _current = await _service.getTypes(parentId: _path.last.id);
    }
    setState(() {});
  }

  Future<void> _deleteType(ProductType t) async {
    try {
      await _service.deleteType(t.id);
      if (_mode == CategoryMode.perfume) {
        await _reloadPerfumeLists();
      } else {
        await _reloadCurrent();
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final message = e.code == '23503'
          ? 'Ce type est encore utilisé par des produits ou des achats — impossible à supprimer.'
          : 'Erreur Supabase (${e.code ?? '?'}): ${e.message}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Generic type dialog used for hierarchical (type1/type2) and simple
  /// (single level) categories — name + optional photo.
  Future<void> _openDialog({ProductType? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    Uint8List? picked;
    final level = _path.length + 1;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(existing == null ? 'Nouveau type (niveau $level)' : 'Modifier le type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final b = await pickCompressedImage();
                  if (b != null) setSt(() => picked = b);
                },
                child: _typeThumb(existing?.imageUrl, picked),
              ),
              const SizedBox(height: 4),
              const Text('Photo optionnelle', style: TextStyle(color: AppColors.grey, fontSize: 11)),
              const SizedBox(height: 12),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || _categoryId == null) return;
                final parentId = _path.isEmpty ? null : _path.last.id;
                final id = await _service.upsertType(
                  id: existing?.id,
                  categoryId: _categoryId!,
                  parentId: parentId,
                  name: nameCtrl.text.trim(),
                  imageUrl: existing?.imageUrl,
                  level: level,
                );
                if (picked != null) {
                  final url = await _service.uploadImage(folder: 'product-types', fileName: '$id.jpg', bytes: picked!);
                  await _service.upsertType(
                    id: id,
                    categoryId: _categoryId!,
                    parentId: parentId,
                    name: nameCtrl.text.trim(),
                    imageUrl: url,
                    level: level,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _reloadCurrent();
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  /// Bottle-size dialog — volume in ml + the bottle's price, bundled
  /// together since a "taille" now fully determines what a bottle sells
  /// for. No name field: the display label is generated from the volume
  /// (e.g. "100ml"). Sizes are level 2 but parent-less: a size applies to
  /// every marque in the category, not one specific parfum.
  Future<void> _openTailleDialog({ProductType? existing}) async {
    final volumeCtrl = TextEditingController(
      text: existing?.volumeLiters != null ? (existing!.volumeLiters! * 1000).round().toString() : '',
    );
    final prixCtrl = TextEditingController(text: existing?.prix?.toString() ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Nouvelle taille' : 'Modifier la taille'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: volumeCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Taille (ml) *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: prixCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Prix (DA) *'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              if (_categoryId == null) return;
              final ml = double.tryParse(volumeCtrl.text.trim().replaceAll(',', '.'));
              final prix = int.tryParse(prixCtrl.text.trim());
              if (ml == null || ml <= 0 || prix == null || prix < 0) return;
              final volume = ml / 1000;
              final name = volume < 1 ? '${ml.round()}ml' : (volume % 1 == 0 ? '${volume.toInt()}L' : '${volume.toStringAsFixed(2)}L');
              await _service.upsertType(
                id: existing?.id,
                categoryId: _categoryId!,
                parentId: null,
                name: name,
                imageUrl: existing?.imageUrl,
                level: 2,
                volumeLiters: volume,
                prix: prix,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _reloadPerfumeLists();
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.gold));
    final mode = _mode;
    return Scaffold(
      floatingActionButton: (_categoryId == null || mode == CategoryMode.perfume)
          ? null
          : FloatingActionButton(
              onPressed: () => _openDialog(),
              child: const Icon(Icons.add),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<int>(
              value: _categoryId,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: _selectCategory,
            ),
          ),
          Expanded(
            child: _categoryId == null
                ? const Center(child: Text('Choisissez une catégorie', style: TextStyle(color: AppColors.grey)))
                : mode == CategoryMode.perfume
                    ? _buildPerfumeBody()
                    : _buildStandardBody(mode),
          ),
        ],
      ),
    );
  }

  Widget _buildStandardBody(CategoryMode? mode) {
    return Column(
      children: [
        if (mode == CategoryMode.simple)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Catégorie simple — un seul niveau de type, pas de sous-types.',
                style: TextStyle(color: AppColors.grey, fontSize: 12),
              ),
            ),
          ),
        if (mode == CategoryMode.repair)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Catégorie réparation — un seul niveau de type, pas de produits à créer. '
                'À la vente, plusieurs types se combinent sur une même ligne avec un prix total libre.',
                style: TextStyle(color: AppColors.grey, fontSize: 12),
              ),
            ),
          ),
        if (_path.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.black), onPressed: _goBack),
                Expanded(
                  child: Text(
                    _path.map((t) => t.name).join(' > '),
                    style: const TextStyle(color: AppColors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _current.length,
            itemBuilder: (_, i) {
              final t = _current[i];
              final canDrill = mode != CategoryMode.simple && mode != CategoryMode.repair && _path.length < 1;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: _typeThumb(t.imageUrl, null),
                  title: Text(t.name),
                  subtitle: Text('niveau ${t.level}', style: const TextStyle(fontSize: 11, color: AppColors.grey)),
                  onTap: canDrill ? () => _drillInto(t) : () => _openDialog(existing: t),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _openDialog(existing: t)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                        onPressed: () => _deleteType(t),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPerfumeBody() {
    Widget sectionHeader(String title, VoidCallback onAdd) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
              IconButton(icon: const Icon(Icons.add_circle, color: AppColors.gold), onPressed: onAdd),
            ],
          ),
        );

    Widget tailleTile(ProductType t) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppColors.offWhite,
              child: Icon(Icons.opacity_outlined, color: AppColors.black, size: 18),
            ),
            title: Text(t.volumeLabel),
            subtitle: Text(t.priceLabel ?? 'Prix non défini', style: const TextStyle(fontSize: 11, color: AppColors.grey)),
            onTap: () => _openTailleDialog(existing: t),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _openTailleDialog(existing: t)),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                  onPressed: () => _deleteType(t),
                ),
              ],
            ),
          ),
        );

    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'Les produits parfum se créent avec une marque (onglet Marques) — ici, gérez seulement les tailles de bouteille et leur prix.',
            style: TextStyle(color: AppColors.grey, fontSize: 12),
          ),
        ),
        sectionHeader('Tailles (bouteilles)', () => _openTailleDialog()),
        if (_tailles.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Aucune taille pour le moment', style: TextStyle(color: AppColors.grey, fontSize: 12)),
          ),
        ..._tailles.map(tailleTile),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Marques tab — name only, no image
// ---------------------------------------------------------------------
class _MarquesTab extends StatefulWidget {
  const _MarquesTab();
  @override
  State<_MarquesTab> createState() => _MarquesTabState();
}

class _MarquesTabState extends State<_MarquesTab> {
  final _service = SupabaseService.instance;
  List<Marque> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _items = await _service.getMarques();
    setState(() => _loading = false);
  }

  Future<void> _openDialog({Marque? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    MarqueType type = existing?.type ?? MarqueType.tech;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(existing == null ? 'Nouvelle marque' : 'Modifier la marque'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              const SizedBox(height: 16),
              const Align(alignment: Alignment.centerLeft, child: Text('Type', style: TextStyle(color: AppColors.grey, fontSize: 12))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _typeChoice('Tech', MarqueType.tech, type, (t) => setSt(() => type = t)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _typeChoice('Parfum', MarqueType.perfum, type, (t) => setSt(() => type = t)),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                await _service.upsertMarque(id: existing?.id, name: nameCtrl.text.trim(), type: type);
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChoice(String label, MarqueType value, MarqueType current, ValueChanged<MarqueType> onChanged) {
    final selected = current == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.black : AppColors.offWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppColors.gold : Colors.transparent, width: 1.4),
        ),
        child: Text(label, style: TextStyle(color: selected ? AppColors.gold : AppColors.black, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: () => _openDialog(), child: const Icon(Icons.add)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final m = _items[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.offWhite,
                      child: Icon(Icons.sell_outlined, color: AppColors.black, size: 18),
                    ),
                    title: Text(m.name),
                    subtitle: Text(
                      m.type == MarqueType.perfum ? 'Marque parfum' : 'Marque tech',
                      style: const TextStyle(fontSize: 11, color: AppColors.grey),
                    ),
                    onTap: () => _openDialog(existing: m),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      onPressed: () async {
                        try {
                          await _service.deleteMarque(m.id);
                          _load();
                        } on PostgrestException catch (e) {
                          if (!context.mounted) return;
                          final message = e.code == '23503'
                              ? 'Cette marque est encore utilisée par des produits — impossible à supprimer.'
                              : 'Erreur Supabase (${e.code ?? '?'}): ${e.message}';
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                        }
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

String _modeLabel(CategoryMode m) {
  switch (m) {
    case CategoryMode.simple:
      return 'Simple — prix libre à la vente';
    case CategoryMode.perfume:
      return 'Parfum — nom + taille';
    case CategoryMode.repair:
      return 'Réparation — combo de types, prix total libre';
    case CategoryMode.hierarchical:
      return 'Hiérarchique — type + sous-type';
  }
}

class _CategoryModeSelector extends StatelessWidget {
  final CategoryMode current;
  final ValueChanged<CategoryMode> onChanged;
  const _CategoryModeSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget option(CategoryMode m, String label, String hint) {
      final selected = current == m;
      return GestureDetector(
        onTap: () => onChanged(m),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? AppColors.black : AppColors.offWhite,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? AppColors.gold : Colors.transparent, width: 1.4),
          ),
          child: Row(
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? AppColors.gold : AppColors.grey, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: selected ? AppColors.gold : AppColors.black, fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(hint, style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        option(CategoryMode.hierarchical, 'Hiérarchique', 'Type + sous-type, prix fixe par produit'),
        option(CategoryMode.simple, 'Simple', 'Un seul type, prix libre saisi à la vente'),
        option(CategoryMode.perfume, 'Parfum', 'Nom du parfum + taille, prix fixe par taille'),
        option(CategoryMode.repair, 'Réparation', 'Combo de types (ex: Afficheur + Flash), pas de produits, prix total libre'),
      ],
    );
  }
}

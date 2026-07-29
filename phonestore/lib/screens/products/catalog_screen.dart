import 'dart:typed_data';
import 'package:flutter/material.dart';
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
                        await _service.deleteCategory(c.id);
                        _load();
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

  // perfume mode: two flat, parallel lists shown on the same page
  List<ProductType> _parfums = [];
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
      _parfums = [];
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
    _parfums = await _service.getTypes(categoryId: _categoryId, topLevelOnly: true, level: 1);
    _tailles = await _service.getTypes(categoryId: _categoryId, topLevelOnly: true, level: 2);
    setState(() {});
  }

  Future<void> _drillInto(ProductType t) async {
    if (_mode == CategoryMode.simple) {
      // Simple categories are a single flat level — no sous-types.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Catégorie simple : ce produit ne peut pas avoir de sous-types.'),
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
    await _service.deleteType(t.id);
    if (_mode == CategoryMode.perfume) {
      await _reloadPerfumeLists();
    } else {
      await _reloadCurrent();
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

  /// Perfume-name (or marque) dialog — name + optional photo, level 1,
  /// always parent-less.
  Future<void> _openParfumDialog({ProductType? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    Uint8List? picked;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(existing == null ? 'Nouveau parfum / marque' : 'Modifier'),
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
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom du parfum / marque')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || _categoryId == null) return;
                final id = await _service.upsertType(
                  id: existing?.id,
                  categoryId: _categoryId!,
                  parentId: null,
                  name: nameCtrl.text.trim(),
                  imageUrl: existing?.imageUrl,
                  level: 1,
                );
                if (picked != null) {
                  final url = await _service.uploadImage(folder: 'product-types', fileName: '$id.jpg', bytes: picked!);
                  await _service.upsertType(
                    id: id,
                    categoryId: _categoryId!,
                    parentId: null,
                    name: nameCtrl.text.trim(),
                    imageUrl: url,
                    level: 1,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _reloadPerfumeLists();
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  /// Bottle-size dialog — name (e.g. "100ml") + a liter volume used for
  /// stock accounting. Sizes are level 2 but parent-less: a size applies to
  /// every parfum in the category, not one specific parfum.
  Future<void> _openTailleDialog({ProductType? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final volumeCtrl = TextEditingController(
      text: existing?.volumeLiters != null ? existing!.volumeLiters.toString() : '',
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Nouvelle taille' : 'Modifier la taille'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom (ex: 100ml)')),
            const SizedBox(height: 12),
            TextField(
              controller: volumeCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Volume en litres (ex: 0.1) *'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty || _categoryId == null) return;
              final volume = double.tryParse(volumeCtrl.text.trim().replaceAll(',', '.'));
              if (volume == null || volume <= 0) return;
              await _service.upsertType(
                id: existing?.id,
                categoryId: _categoryId!,
                parentId: null,
                name: nameCtrl.text.trim(),
                imageUrl: existing?.imageUrl,
                level: 2,
                volumeLiters: volume,
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
              final canDrill = mode != CategoryMode.simple && _path.length < 1;
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

    Widget parfumTile(ProductType t) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: _typeThumb(t.imageUrl, null),
            title: Text(t.name),
            onTap: () => _openParfumDialog(existing: t),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _openParfumDialog(existing: t)),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                  onPressed: () => _deleteType(t),
                ),
              ],
            ),
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
            subtitle: t.name != t.volumeLabel ? Text(t.name, style: const TextStyle(fontSize: 11, color: AppColors.grey)) : null,
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
        sectionHeader('Noms de parfum / marques', () => _openParfumDialog()),
        if (_parfums.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Aucun parfum pour le moment', style: TextStyle(color: AppColors.grey, fontSize: 12)),
          ),
        ..._parfums.map(parfumTile),
        const Divider(height: 32),
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
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Nouvelle marque' : 'Modifier la marque'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await _service.upsertMarque(id: existing?.id, name: nameCtrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            },
            child: const Text('Enregistrer'),
          ),
        ],
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
                    onTap: () => _openDialog(existing: m),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      onPressed: () async {
                        await _service.deleteMarque(m.id);
                        _load();
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
      ],
    );
  }
}

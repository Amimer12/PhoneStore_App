import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/category.dart';
import '../../models/marque.dart';
import '../../models/product.dart';
import '../../models/product_type.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/category_icons.dart';
import '../../widgets/selector_chips.dart';

/// Picks an image and compresses it heavily (low quality, small dimensions)
/// so we never push large files into Supabase storage. Type/product images
/// are only ever shown as small chips or list icons, so there's no benefit
/// to keeping anything bigger than this. Returns null if the user cancels —
/// images are optional everywhere in this app.
Future<Uint8List?> pickCompressedImage() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 50,
    maxWidth: 240,
    maxHeight: 240,
  );
  if (file == null) return null;
  return file.readAsBytes();
}

class ProductForm extends StatefulWidget {
  final Product? product;
  const ProductForm({super.key, this.product});

  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final _service = SupabaseService.instance;
  final _formKey = GlobalKey<FormState>();

  List<Category> _categories = [];
  List<ProductType> _type1Options = [];
  List<ProductType> _type2Options = [];
  List<Marque> _marques = [];

  int? _categoryId;
  int? _type1Id;
  int? _type2Id;
  int? _marqueId;

  final _referenceCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _prixCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();

  Uint8List? _pickedImageBytes;
  String? _existingImageUrl;
  bool _loading = true;
  bool _saving = false;

  bool get _isEdit => widget.product != null;

  CategoryMode get _categoryMode {
    final c = _categories.where((c) => c.id == _categoryId);
    return c.isEmpty ? CategoryMode.hierarchical : c.first.mode;
  }

  // Labels shift depending on the category's behavior mode, while reusing
  // the exact same type1/type2 storage underneath — see categories.mode.
  String get _type1Label {
    switch (_categoryMode) {
      case CategoryMode.perfume:
        return 'Nom du parfum *';
      case CategoryMode.simple:
        return 'Type *';
      case CategoryMode.hierarchical:
        return 'Type *';
    }
  }

  String get _type2Label => _categoryMode == CategoryMode.perfume ? 'Taille (ex: 100ml)' : 'Sous-type (optionnel)';

  // Perfume products only ever pick a parfum name (type1) — bottle size is
  // chosen later, per purchase, in the Achats form. Simple products also
  // have no type2. Only hierarchical categories show a sous-type field.
  bool get _showType2 => _categoryMode == CategoryMode.hierarchical;
  bool get _showStock => _categoryMode != CategoryMode.simple;
  String get _stockLabel => _categoryMode == CategoryMode.perfume ? 'Stock (L)' : 'Stock';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _categories = await _service.getCategories();
    _marques = await _service.getMarques();

    final p = widget.product;
    if (p != null) {
      _referenceCtrl.text = p.reference;
      _nameCtrl.text = p.name ?? '';
      _prixCtrl.text = p.prix.toString();
      _stockCtrl.text = p.stock % 1 == 0 ? p.stock.toInt().toString() : p.stock.toString();
      _existingImageUrl = p.imageUrl;
      _categoryId = p.categoryId;
      _type1Id = p.type1Id;
      _type2Id = p.type2Id;
      _marqueId = p.marqueId;

      _type1Options = await _service.getTypes(categoryId: _categoryId, topLevelOnly: true, level: 1);
      if (_type1Id != null && _showType2) {
        _type2Options = await _service.getTypes(parentId: _type1Id);
      }
    }
    setState(() => _loading = false);
  }

  Future<void> _onCategoryChanged(int? id) async {
    if (id == null) return;
    setState(() {
      _categoryId = id;
      _type1Id = null;
      _type2Id = null;
      _type2Options = [];
    });
    _type1Options = await _service.getTypes(categoryId: id, topLevelOnly: true, level: 1);
    setState(() {});
  }

  Future<void> _onType1Changed(int? id) async {
    setState(() {
      _type1Id = id;
      _type2Id = null;
    });
    _type2Options = (id == null || !_showType2) ? [] : await _service.getTypes(parentId: id);
    _maybeSuggestReference();
    setState(() {});
  }

  /// Fills in a short, human-readable reference when creating a new product
  /// and the field is still empty — the admin can freely overwrite it. Never
  /// touches an existing product's reference.
  void _maybeSuggestReference() {
    if (_isEdit || _referenceCtrl.text.trim().isNotEmpty || _type1Id == null) return;
    final t1 = _type1Options.where((t) => t.id == _type1Id);
    final label = t1.isEmpty ? 'PRD' : t1.first.name;
    _referenceCtrl.text = _generateReference(label);
  }

  String _generateReference(String label) {
    final letters = label.replaceAll(RegExp(r'[^A-Za-z]'), '');
    final prefix = (letters.isEmpty ? 'PRD' : letters).toUpperCase().substring(0, letters.length >= 3 ? 3 : letters.length.clamp(1, 3));
    final suffix = (DateTime.now().millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
    return '$prefix-$suffix';
  }

  // ---------------- inline "create new" dialogs ----------------

  Future<void> _quickAddCategory() async {
    final result = await _showCategoryDialog();
    if (result == null) return;
    final id = await _service.upsertCategory(name: result.name, iconKey: result.iconKey!, mode: result.mode);
    _categories = await _service.getCategories();
    await _onCategoryChanged(id);
  }

  Future<void> _quickAddType1() async {
    if (_categoryId == null) return;
    final result = await _showNameImageDialog(title: 'Nouveau ${_categoryMode == CategoryMode.perfume ? "parfum" : "type"}');
    if (result == null) return;
    final id = await _service.upsertType(
      categoryId: _categoryId!,
      parentId: null,
      name: result.name,
      imageUrl: null,
      level: 1,
    );
    if (result.imageBytes != null) {
      final url = await _service.uploadImage(folder: 'product-types', fileName: '$id.jpg', bytes: result.imageBytes!);
      await _service.upsertType(id: id, categoryId: _categoryId!, parentId: null, name: result.name, imageUrl: url, level: 1);
    }
    _type1Options = await _service.getTypes(categoryId: _categoryId, topLevelOnly: true, level: 1);
    await _onType1Changed(id);
  }

  Future<void> _quickAddType2() async {
    if (_categoryId == null || _type1Id == null) return;
    final result = await _showNameImageDialog(title: 'Nouvelle ${_categoryMode == CategoryMode.perfume ? "taille" : "sous-type"}');
    if (result == null) return;
    final id = await _service.upsertType(
      categoryId: _categoryId!,
      parentId: _type1Id,
      name: result.name,
      imageUrl: null,
      level: 2,
    );
    if (result.imageBytes != null) {
      final url = await _service.uploadImage(folder: 'product-types', fileName: '$id.jpg', bytes: result.imageBytes!);
      await _service.upsertType(id: id, categoryId: _categoryId!, parentId: _type1Id, name: result.name, imageUrl: url, level: 2);
    }
    _type2Options = await _service.getTypes(parentId: _type1Id);
    setState(() => _type2Id = id);
  }

  Future<void> _quickAddMarque() async {
    final name = await _showNameOnlyDialog(title: 'Nouvelle marque');
    if (name == null) return;
    final id = await _service.upsertMarque(name: name);
    _marques = await _service.getMarques();
    setState(() => _marqueId = id);
  }

  Future<_CategoryDialogResult?> _showCategoryDialog() async {
    final nameCtrl = TextEditingController();
    String iconKey = 'category';
    CategoryMode mode = CategoryMode.hierarchical;
    return showDialog<_CategoryDialogResult>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Nouvelle catégorie'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nom *'),
                ),
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
                _modeSelector(mode, (m) => setSt(() => mode = m)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, _CategoryDialogResult(nameCtrl.text.trim(), iconKey, mode));
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeSelector(CategoryMode current, ValueChanged<CategoryMode> onChanged) {
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
                    Text(hint, style: TextStyle(color: selected ? AppColors.grey : AppColors.grey, fontSize: 11)),
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

  Future<_NameImageResult?> _showNameImageDialog({required String title}) async {
    final nameCtrl = TextEditingController();
    Uint8List? picked;
    return showDialog<_NameImageResult>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final b = await pickCompressedImage();
                  if (b != null) setSt(() => picked = b);
                },
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: AppColors.offWhite, borderRadius: BorderRadius.circular(10)),
                  clipBehavior: Clip.antiAlias,
                  child: picked != null
                      ? Image.memory(picked!, fit: BoxFit.cover)
                      : const Icon(Icons.add_a_photo_outlined, color: AppColors.grey, size: 20),
                ),
              ),
              const SizedBox(height: 4),
              const Text('Photo optionnelle', style: TextStyle(color: AppColors.grey, fontSize: 11)),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom *'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, _NameImageResult(nameCtrl.text.trim(), picked));
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showNameOnlyDialog({required String title}) async {
    final nameCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom *'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, nameCtrl.text.trim());
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  // ---------------- save ----------------

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null || _type1Id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catégorie et type sont obligatoires')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final product = Product(
        id: widget.product?.id ?? 0,
        reference: _referenceCtrl.text.trim(),
        name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        categoryId: _categoryId!,
        type1Id: _type1Id!,
        type2Id: _showType2 ? _type2Id : null,
        marqueId: _marqueId,
        prix: int.parse(_prixCtrl.text.trim()),
        stock: double.tryParse(_stockCtrl.text.trim().replaceAll(',', '.')) ?? 0,
        imageUrl: _existingImageUrl,
      );

      // Insert/update first so we always have a product id to name the image after.
      final productId = await _service.upsertProduct(
        id: _isEdit ? widget.product!.id : null,
        product: product,
      );

      if (_pickedImageBytes != null) {
        final url = await _service.uploadImage(
          folder: 'products',
          fileName: '$productId.jpg',
          bytes: _pickedImageBytes!,
        );
        await _service.upsertProduct(
          id: productId,
          product: Product(
            id: productId,
            reference: product.reference,
            name: product.name,
            categoryId: product.categoryId,
            type1Id: product.type1Id,
            type2Id: product.type2Id,
            marqueId: product.marqueId,
            prix: product.prix,
            stock: product.stock,
            imageUrl: url,
          ),
        );
      }

      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) {
        final message = e.code == '23505'
            ? 'Cette référence est déjà utilisée par un autre produit — changez-la.'
            : 'Erreur Supabase (${e.code ?? '?'}): ${e.message}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur inattendue: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _referenceCtrl.dispose();
    _nameCtrl.dispose();
    _prixCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.gold)));
    }
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Modifier le produit' : 'Nouveau produit')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: GestureDetector(
                onTap: () async {
                  final b = await pickCompressedImage();
                  if (b != null) setState(() => _pickedImageBytes = b);
                },
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.offWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.gold, width: 1.2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _pickedImageBytes != null
                      ? Image.memory(_pickedImageBytes!, fit: BoxFit.cover)
                      : (_existingImageUrl != null
                          ? Image.network(_existingImageUrl!, fit: BoxFit.cover)
                          : const Icon(Icons.add_a_photo_outlined, color: AppColors.gold, size: 26)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Center(
              child: Text('Photo produit optionnelle', style: TextStyle(color: AppColors.grey, fontSize: 12)),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _referenceCtrl,
                    decoration: const InputDecoration(labelText: 'Référence *'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: IconButton(
                    icon: const Icon(Icons.refresh, color: AppColors.gold),
                    tooltip: 'Générer une référence',
                    onPressed: () {
                      final t1 = _type1Options.where((t) => t.id == _type1Id);
                      setState(() => _referenceCtrl.text = _generateReference(t1.isEmpty ? 'PRD' : t1.first.name));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nom (optionnel)'),
            ),
            const SizedBox(height: 20),
            const Text('Catégorie *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            CategoryIconPicker(
              categories: _categories,
              selectedId: _categoryId,
              onSelect: _onCategoryChanged,
              onAddNew: _quickAddCategory,
            ),
            const SizedBox(height: 20),
            TypeChipSelector(
              label: _type1Label,
              items: _type1Options,
              selectedId: _type1Id,
              onSelect: _categoryId == null ? (_) {} : _onType1Changed,
              onAddNew: _categoryId == null ? null : _quickAddType1,
            ),
            if (_showType2) ...[
              const SizedBox(height: 20),
              TypeChipSelector(
                label: _type2Label,
                items: _type2Options,
                selectedId: _type2Id,
                onSelect: (v) => setState(() => _type2Id = v),
                onAddNew: _type1Id == null ? null : _quickAddType2,
                allowClear: true,
              ),
            ],
            const SizedBox(height: 20),
            _marqueDropdown(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _prixCtrl,
                    decoration: InputDecoration(
                      labelText: _categoryMode == CategoryMode.simple ? 'Prix par défaut (DA) *' : 'Prix (DA) *',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => (v == null || int.tryParse(v) == null) ? 'Prix invalide' : null,
                  ),
                ),
                if (_showStock) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _stockCtrl,
                      decoration: InputDecoration(labelText: _stockLabel),
                      keyboardType: TextInputType.numberWithOptions(decimal: _categoryMode == CategoryMode.perfume),
                    ),
                  ),
                ],
              ],
            ),
            if (_categoryMode == CategoryMode.simple) ...[
              const SizedBox(height: 8),
              const Text(
                'Le prix sera modifiable à chaque vente dans le formulaire Achats.',
                style: TextStyle(color: AppColors.grey, fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEdit ? 'Enregistrer' : 'Ajouter'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _marqueDropdown() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            value: _marqueId,
            decoration: const InputDecoration(labelText: 'Marque (optionnel)'),
            items: _marques.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))).toList(),
            onChanged: (v) => setState(() => _marqueId = v),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: IconButton(
            icon: const Icon(Icons.add_circle, color: AppColors.gold),
            tooltip: 'Créer une marque',
            onPressed: _quickAddMarque,
          ),
        ),
      ],
    );
  }
}

class _NameImageResult {
  final String name;
  final Uint8List? imageBytes;
  _NameImageResult(this.name, this.imageBytes);
}

class _CategoryDialogResult {
  final String name;
  final String? iconKey;
  final CategoryMode mode;
  _CategoryDialogResult(this.name, this.iconKey, this.mode);
}
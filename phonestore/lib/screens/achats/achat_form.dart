import 'package:flutter/material.dart';
import '../../models/achat.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../models/product_type.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/selector_chips.dart';

class AchatForm extends StatefulWidget {
  final Achat? achat;
  const AchatForm({super.key, this.achat});

  @override
  State<AchatForm> createState() => _AchatFormState();
}

class _CartLine {
  final Product product;
  int quantity;
  int unitPrice;
  final int? type2Id;
  final String? type2Name;
  final double? volumeLiters;
  _CartLine({
    required this.product,
    this.quantity = 1,
    int? unitPrice,
    this.type2Id,
    this.type2Name,
    this.volumeLiters,
  }) : unitPrice = unitPrice ?? product.prix;
  int get subtotal => unitPrice * quantity;
}

class _AchatFormState extends State<AchatForm> {
  final _service = SupabaseService.instance;
  List<Product> _allProducts = [];
  List<Category> _categories = [];
  List<ProductType> _type1Options = [];
  List<ProductType> _type2Options = [];

  int? _filterCategoryId;
  int? _filterType1Id;
  int? _filterType2Id;

  final Map<String, _CartLine> _cart = {}; // "productId" or "productId_type2Id" -> line
  bool _loading = true;
  bool _saving = false;
  String _search = '';

  bool get _isEdit => widget.achat != null;

  String _cartKey(int productId, int? type2Id) => type2Id == null ? '$productId' : '${productId}_$type2Id';

  List<_CartLine> _linesFor(int productId) => _cart.values.where((l) => l.product.id == productId).toList();

  int _totalQtyFor(int productId) => _linesFor(productId).fold(0, (s, l) => s + l.quantity);

  CategoryMode _modeFor(Product p) {
    final c = _categories.where((c) => c.id == p.categoryId);
    return c.isEmpty ? CategoryMode.hierarchical : c.first.mode;
  }

  CategoryMode? get _filterCategoryMode {
    final c = _categories.where((c) => c.id == _filterCategoryId);
    return c.isEmpty ? null : c.first.mode;
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _allProducts = await _service.getProducts();
    _categories = await _service.getCategories();
    if (widget.achat != null) {
      for (final item in widget.achat!.items) {
        final product = _allProducts.firstWhere(
          (p) => p.id == item.productId,
          orElse: () => item.product!,
        );
        final key = _cartKey(item.productId, item.type2Id);
        _cart[key] = _CartLine(
          product: product,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          type2Id: item.type2Id,
          type2Name: item.type2Name,
        );
      }
    }
    setState(() => _loading = false);
  }

  Future<void> _onCategoryFilterChanged(int? id) async {
    setState(() {
      _filterCategoryId = id;
      _filterType1Id = null;
      _filterType2Id = null;
      _type2Options = [];
    });
    if (id == null) {
      _type1Options = [];
      setState(() {});
      return;
    }
    _type1Options = await _service.getTypes(categoryId: id, topLevelOnly: true, level: 1);
    setState(() {});
  }

  Future<void> _onType1FilterChanged(int? id) async {
    setState(() => _filterType1Id = id);
    if (_filterCategoryMode == CategoryMode.perfume) return; // tailles aren't a product attribute here
    setState(() => _filterType2Id = null);
    _type2Options = id == null ? [] : await _service.getTypes(parentId: id);
    setState(() {});
  }

  int get _total => _cart.values.fold(0, (sum, l) => sum + l.subtotal);

  /// For "simple" categories (Flexy, Reparation) there's no fixed catalog
  /// price — the worker types the actual sale price in on the spot.
  Future<int?> _askPrice(Product p, {int? initial}) async {
    final ctrl = TextEditingController(text: (initial ?? p.prix).toString());
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Prix — ${p.displayLabel}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Prix (DA) *'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v == null || v < 0) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _addOrIncrement(Product p) async {
    if (_modeFor(p) == CategoryMode.perfume) {
      await _addPerfumeLine(p);
      return;
    }
    final key = _cartKey(p.id, null);
    if (_cart.containsKey(key)) {
      setState(() => _cart[key]!.quantity++);
      return;
    }
    if (_modeFor(p) == CategoryMode.simple) {
      final price = await _askPrice(p);
      if (price == null) return;
      setState(() => _cart[key] = _CartLine(product: p, unitPrice: price));
    } else {
      setState(() => _cart[key] = _CartLine(product: p));
    }
  }

  /// Perfume purchases: pick which bottle size was sold, then add/increment
  /// that specific product+size line. Price stays the product's fixed
  /// price — only the size (and the liters it represents for stock) varies.
  Future<void> _addPerfumeLine(Product p) async {
    final tailles = await _service.getTypes(categoryId: p.categoryId, topLevelOnly: true, level: 2);
    if (tailles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ajoutez d\'abord une taille dans le Catalogue.')),
        );
      }
      return;
    }
    final chosen = await showDialog<ProductType>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Taille — ${p.displayLabel}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tailles
                .map((t) => ActionChip(label: Text(t.volumeLabel), onPressed: () => Navigator.pop(ctx, t)))
                .toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler'))],
      ),
    );
    if (chosen == null) return;
    final key = _cartKey(p.id, chosen.id);
    setState(() {
      if (_cart.containsKey(key)) {
        _cart[key]!.quantity++;
      } else {
        _cart[key] = _CartLine(
          product: p,
          unitPrice: p.prix,
          type2Id: chosen.id,
          type2Name: chosen.name,
          volumeLiters: chosen.volumeLiters,
        );
      }
    });
  }

  Future<void> _editPrice(Product p) async {
    final key = _cartKey(p.id, null);
    final line = _cart[key];
    if (line == null) return;
    final price = await _askPrice(p, initial: line.unitPrice);
    if (price != null) setState(() => line.unitPrice = price);
  }

  void _decrementLine(String key) {
    setState(() {
      final line = _cart[key];
      if (line == null) return;
      if (line.quantity <= 1) {
        _cart.remove(key);
      } else {
        line.quantity--;
      }
    });
  }

  Future<void> _save() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoutez au moins un produit')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final items = _cart.values
          .map((l) => AchatItem(
                productId: l.product.id,
                quantity: l.quantity,
                unitPrice: l.unitPrice,
                type2Id: l.type2Id,
              ))
          .toList();

      if (_isEdit) {
        await _service.updateAchatItems(achatId: widget.achat!.id!, items: items);
      } else {
        await _service.createAchat(items: items);
      }
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Product> get _filtered {
    var list = _allProducts;
    if (_filterCategoryId != null) list = list.where((p) => p.categoryId == _filterCategoryId).toList();
    if (_filterType1Id != null) list = list.where((p) => p.type1Id == _filterType1Id).toList();
    if (_filterType2Id != null && _filterCategoryMode != CategoryMode.perfume) {
      list = list.where((p) => p.type2Id == _filterType2Id).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((p) => p.searchBlob.contains(q)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.gold)));
    }

    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Modifier l\'achat' : 'Nouvel achat')),
      body: Column(
        children: [
          _buildFilterBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, color: AppColors.grey),
                hintText: 'Chercher par référence, type, marque...',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('Aucun produit trouvé', style: TextStyle(color: AppColors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      final isSimple = _modeFor(p) == CategoryMode.simple;
                      final isPerfume = _modeFor(p) == CategoryMode.perfume;
                      final inCart = isPerfume ? null : _cart[_cartKey(p.id, null)];
                      final perfumeLines = isPerfume ? _linesFor(p.id) : const <_CartLine>[];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              leading: p.displayImageUrl == null
                                  ? null
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: Image.network(p.displayImageUrl!, fit: BoxFit.cover),
                                      ),
                                    ),
                              title: Text(p.displayLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                isSimple
                                    ? '${p.reference} · prix libre'
                                    : isPerfume
                                        ? '${p.reference} · ${p.prix} DA · stock: ${p.stockLabel}'
                                        : '${p.reference} · ${p.prix} DA · stock: ${p.stock.toInt()}',
                                style: const TextStyle(color: AppColors.grey, fontSize: 12),
                              ),
                              trailing: isPerfume
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (perfumeLines.isNotEmpty)
                                          Text('${_totalQtyFor(p.id)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle, color: AppColors.gold),
                                          onPressed: () => _addPerfumeLine(p),
                                        ),
                                      ],
                                    )
                                  : inCart == null
                                      ? IconButton(
                                          icon: const Icon(Icons.add_circle, color: AppColors.gold),
                                          onPressed: () => _addOrIncrement(p),
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isSimple) ...[
                                              Text('${inCart.unitPrice} DA', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.grey),
                                                onPressed: () => _editPrice(p),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                              ),
                                              const SizedBox(width: 4),
                                            ],
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline, color: AppColors.black),
                                              onPressed: () => _decrementLine(_cartKey(p.id, null)),
                                            ),
                                            Text('${inCart.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                            IconButton(
                                              icon: const Icon(Icons.add_circle, color: AppColors.gold),
                                              onPressed: () => _addOrIncrement(p),
                                            ),
                                          ],
                                        ),
                            ),
                            if (perfumeLines.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 12, 10),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: perfumeLines.map((l) {
                                    final key = _cartKey(p.id, l.type2Id);
                                    return Chip(
                                      label: Text('${l.type2Name ?? '?'} × ${l.quantity}', style: const TextStyle(fontSize: 12)),
                                      onDeleted: () => _decrementLine(key),
                                      deleteIcon: const Icon(Icons.remove_circle_outline, size: 16),
                                    );
                                  }).toList(),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          _buildSummaryBar(),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final perfume = _filterCategoryMode == CategoryMode.perfume;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CategoryIconPicker(
            categories: _categories,
            selectedId: _filterCategoryId,
            onSelect: _onCategoryFilterChanged,
            allowClear: true,
          ),
          if (_filterCategoryId != null) ...[
            const SizedBox(height: 12),
            TypeChipSelector(
              label: perfume ? 'Nom du parfum' : 'Type',
              items: _type1Options,
              selectedId: _filterType1Id,
              onSelect: _onType1FilterChanged,
              allowClear: true,
            ),
          ],
          if (_type2Options.isNotEmpty) ...[
            const SizedBox(height: 12),
            TypeChipSelector(
              label: perfume ? 'Taille' : 'Sous-type',
              items: _type2Options,
              selectedId: _filterType2Id,
              onSelect: (v) => setState(() => _filterType2Id = v),
              allowClear: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total', style: TextStyle(color: AppColors.grey, fontSize: 12)),
                Text('$_total DA', style: const TextStyle(color: AppColors.gold, fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isEdit ? 'Enregistrer' : 'Valider l\'achat'),
          ),
        ],
      ),
    );
  }
}
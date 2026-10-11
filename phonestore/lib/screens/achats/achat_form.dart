import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/achat.dart';
import '../../models/category.dart';
import '../../models/marque.dart';
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
  /// Null only for a legacy 'repair' combo line from a sale made before
  /// repair parts became real products — see [categoryId]/[repairTypeIds].
  /// New repair lines always carry a product, exactly like every other
  /// category.
  final Product? product;
  int quantity;
  int unitPrice;
  final int? type2Id;
  final String? type2Name;
  final double? volumeLiters;

  // Repair-combo-only fields — only ever populated when reading back a
  // legacy pre-product repair line (see _CartLine.product doc).
  final int? categoryId;
  final List<int> repairTypeIds;
  final String? repairLabel; // e.g. "Afficheur + Flash + Connecteur"

  _CartLine({
    this.product,
    this.quantity = 1,
    int? unitPrice,
    this.type2Id,
    this.type2Name,
    this.volumeLiters,
    this.categoryId,
    this.repairTypeIds = const [],
    this.repairLabel,
  }) : unitPrice = unitPrice ?? product?.prix ?? 0;

  int get subtotal => unitPrice * quantity;
  bool get isRepair => product == null;
  String get label => isRepair ? (repairLabel ?? '') : product!.displayLabel;
}

class _AchatFormState extends State<AchatForm> {
  final _service = SupabaseService.instance;
  List<Product> _allProducts = [];
  List<Category> _categories = [];
  List<ProductType> _type1Options = [];
  List<ProductType> _type2Options = [];
  List<Marque> _marques = [];

  int? _filterCategoryId;
  int? _filterType1Id;
  int? _filterType2Id;
  int? _filterMarqueId;

  final Map<String, _CartLine> _cart = {}; // "productId" or "productId_type2Id" or "repair_..." -> line
  bool _loading = true;
  bool _saving = false;
  String _search = '';

  bool get _isEdit => widget.achat != null;

  String _cartKey(int productId, int? type2Id) => type2Id == null ? '$productId' : '${productId}_$type2Id';

  /// Deterministic key for a repair combo line — same set of types under the
  /// same category always maps to the same cart line, regardless of the
  /// order they were tapped in, so re-adding the same combo increments
  /// quantity instead of creating a duplicate line.
  String _repairKey(int categoryId, List<int> typeIds) {
    final sorted = [...typeIds]..sort();
    return 'repair_${categoryId}_${sorted.join('-')}';
  }

  List<_CartLine> _linesFor(int productId) => _cart.values.where((l) => l.product?.id == productId).toList();

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
    _marques = await _service.getMarques();
    if (widget.achat != null) {
      for (final item in widget.achat!.items) {
        if (item.isRepair) {
          final key = _repairKey(item.categoryId!, item.typeIds);
          _cart[key] = _CartLine(
            categoryId: item.categoryId,
            repairTypeIds: item.typeIds,
            repairLabel: item.label,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
          );
          continue;
        }
        final product = _allProducts.firstWhere(
          (p) => p.id == item.productId,
          orElse: () => item.product!,
        );
        final key = _cartKey(item.productId!, item.type2Id);
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
      _filterMarqueId = null;
      _type2Options = [];
    });
    if (id == null) {
      _type1Options = [];
      setState(() {});
      return;
    }
    final c = _categories.firstWhere((c) => c.id == id);
    // 'repair' categories browse just like 'hierarchical' ones now — pick a
    // type (Afficheur, Flash...), see its products, add new ones on the fly.
    // Only 'perfume' has no type1 at all (products are identified by marque).
    _type1Options = c.mode != CategoryMode.perfume ? await _service.getTypes(categoryId: id, topLevelOnly: true, level: 1) : [];
    setState(() {});
  }

  Future<void> _onType1FilterChanged(int? id) async {
    setState(() => _filterType1Id = id);
    setState(() => _filterType2Id = null);
    _type2Options = id == null ? [] : await _service.getTypes(parentId: id);
    setState(() {});
  }

  int get _total => _cart.values.fold(0, (sum, l) => sum + l.subtotal);

  /// Asks for the final sale price of one cart line. Used for every
  /// category now (not just "simple"/repair): the worker can always
  /// override the catalog price, e.g. when a client negotiates a discount.
  /// Defaults to [initial] (the line's current price) or [p]'s catalog
  /// price. Shows the product's prix_achat as a reminder and flags — but
  /// never blocks — a final price below it, since a below-cost sale is
  /// sometimes a deliberate call by the seller.
  Future<int?> _askPrice(Product p, {int? initial}) async {
    final ctrl = TextEditingController(text: (initial ?? p.prix ?? 0).toString());
    final prixAchat = p.prixAchat;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final entered = int.tryParse(ctrl.text.trim());
          final belowCost = prixAchat != null && entered != null && entered < prixAchat;
          return AlertDialog(
            title: Text('Prix — ${p.displayLabel}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Prix final (DA) *'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                if (prixAchat != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    "Prix d'achat : $prixAchat DA",
                    style: const TextStyle(color: AppColors.grey, fontSize: 12),
                  ),
                ],
                if (belowCost) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Attention : ce prix est inférieur au prix d\'achat — vous vendez à perte.',
                    style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
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
          );
        },
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
  /// that specific product+size line. The price comes from the taille
  /// itself — bottle size and price are bundled together in the catalogue.
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
                .map((t) => ActionChip(
                      label: Text('${t.volumeLabel} — ${t.priceLabel ?? "prix non défini"}'),
                      onPressed: () => Navigator.pop(ctx, t),
                    ))
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
          unitPrice: chosen.prix ?? 0,
          type2Id: chosen.id,
          type2Name: chosen.name,
          volumeLiters: chosen.volumeLiters,
        );
      }
    });
  }

  /// Same free-price dialog as [_askPrice], but titled after the combo of
  /// selected types (e.g. "Afficheur + Flash + Connecteur") since there's
  /// no product to name it after.
  Future<int?> _askRepairPrice(String label, {int? initial}) async {
    final ctrl = TextEditingController(text: (initial ?? 0).toString());
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Prix — $label'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Prix total (DA) *'),
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

  /// Edits the price of a legacy repair-combo line (see [_CartLine.product]
  /// doc) from an old sale — new repair lines are real products now, priced
  /// via [_askPrice]/[_editLinePrice] like everything else.
  Future<void> _editRepairPrice(String key) async {
    final line = _cart[key];
    if (line == null) return;
    final price = await _askRepairPrice(line.label, initial: line.unitPrice);
    if (price != null) setState(() => line.unitPrice = price);
  }

  /// Lets the worker override the final price of any product-backed cart
  /// line — no matter the product's category — defaulting to that line's
  /// current price (itself defaulted to the catalog prix when added).
  Future<void> _editLinePrice(String key) async {
    final line = _cart[key];
    if (line == null || line.product == null) return;
    final price = await _askPrice(line.product!, initial: line.unitPrice);
    if (price != null) setState(() => line.unitPrice = price);
  }

  /// Deliberately minimal, inline product creation for a repair part (e.g.
  /// a new "Afficheur" for some phone model) that isn't in the catalogue
  /// yet: type, reference (auto-generated, editable — same convention as
  /// the main product form), marque, prix, prix d'achat. No name field —
  /// repair parts are identified by their type + marque + reference, same
  /// as most hierarchical products. Saves it as a normal product (category
  /// = the current repair category, type1 = the chosen part type, type2 =
  /// null — repair categories only ever have one level of types), then
  /// drops it straight into the cart so the worker doesn't have to look it
  /// up again right after creating it.
  Future<void> _quickAddRepairProduct() async {
    if (_filterCategoryId == null || _type1Options.isEmpty) return;
    final referenceCtrl = TextEditingController();
    final prixCtrl = TextEditingController();
    final prixAchatCtrl = TextEditingController(text: '0');
    int? typeId = _filterType1Id ?? (_type1Options.length == 1 ? _type1Options.first.id : null);
    int? marqueId;
    final marques = _marques.where((m) => m.type == MarqueType.tech).toList();
    bool saving = false;
    String? error;

    String generateReference(String label) {
      final letters = label.replaceAll(RegExp(r'[^A-Za-z]'), '');
      final prefix = (letters.isEmpty ? 'REP' : letters).toUpperCase().substring(0, letters.length >= 3 ? 3 : letters.length.clamp(1, 3));
      final suffix = (DateTime.now().millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
      return '$prefix-$suffix';
    }

    if (typeId != null) {
      final t = _type1Options.where((t) => t.id == typeId);
      referenceCtrl.text = generateReference(t.isEmpty ? 'REP' : t.first.name);
    }

    final created = await showDialog<Product>(
      context: context,
      barrierDismissible: !saving,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nouvelle pièce'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<int>(
                  value: typeId,
                  decoration: const InputDecoration(labelText: 'Type *'),
                  items: _type1Options.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                  onChanged: (v) => setDialogState(() {
                    typeId = v;
                    if (referenceCtrl.text.trim().isEmpty && v != null) {
                      final t = _type1Options.where((t) => t.id == v);
                      referenceCtrl.text = generateReference(t.isEmpty ? 'REP' : t.first.name);
                    }
                  }),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: referenceCtrl,
                        decoration: const InputDecoration(labelText: 'Référence *'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: IconButton(
                        icon: const Icon(Icons.refresh, color: AppColors.gold),
                        tooltip: 'Régénérer',
                        onPressed: () {
                          final t = _type1Options.where((t) => t.id == typeId);
                          setDialogState(() => referenceCtrl.text = generateReference(t.isEmpty ? 'REP' : t.first.name));
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: marqueId,
                  decoration: const InputDecoration(labelText: 'Marque (optionnel)'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('—')),
                    ...marques.map((m) => DropdownMenuItem<int?>(value: m.id, child: Text(m.name))),
                  ],
                  onChanged: (v) => setDialogState(() => marqueId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: prixCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Prix (DA) *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: prixAchatCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Prix d'achat (DA) *"),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final reference = referenceCtrl.text.trim();
                      final prix = int.tryParse(prixCtrl.text.trim());
                      final prixAchat = int.tryParse(prixAchatCtrl.text.trim()) ?? 0;
                      if (typeId == null || reference.isEmpty || prix == null || prix < 0) {
                        setDialogState(() => error = 'Type, référence et prix sont obligatoires.');
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        final id = await _service.upsertProduct(
                          id: null,
                          product: Product(
                            id: 0,
                            reference: reference,
                            categoryId: _filterCategoryId!,
                            type1Id: typeId,
                            marqueId: marqueId,
                            prix: prix,
                            prixAchat: prixAchat,
                            stock: 0,
                          ),
                        );
                        if (ctx.mounted) {
                          Navigator.pop(
                            ctx,
                            Product(
                              id: id,
                              reference: reference,
                              categoryId: _filterCategoryId!,
                              type1Id: typeId,
                              marqueId: marqueId,
                              prix: prix,
                              prixAchat: prixAchat,
                              stock: 0,
                            ),
                          );
                        }
                      } on PostgrestException catch (e) {
                        setDialogState(() {
                          saving = false;
                          error = e.code == '23505'
                              ? 'Cette référence existe déjà — changez-la ou régénérez-en une.'
                              : 'Erreur: ${e.message}';
                        });
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          error = 'Erreur inattendue: $e';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );

    if (created == null) return;
    setState(() {
      _allProducts = [created, ..._allProducts];
      _filterType1Id = created.type1Id;
    });
    await _addOrIncrement(created);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${created.displayLabel} ajouté au catalogue et au panier')),
      );
    }
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
      final items = _cart.values.map((l) {
        if (l.isRepair) {
          return AchatItem(
            categoryId: l.categoryId,
            label: l.repairLabel,
            typeIds: l.repairTypeIds,
            quantity: l.quantity,
            unitPrice: l.unitPrice,
          );
        }
        return AchatItem(
          productId: l.product!.id,
          quantity: l.quantity,
          unitPrice: l.unitPrice,
          unitCost: l.product!.prixAchat,
          type2Id: l.type2Id,
        );
      }).toList();

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
    if (_filterCategoryMode == CategoryMode.perfume) {
      if (_filterMarqueId != null) list = list.where((p) => p.marqueId == _filterMarqueId).toList();
    } else {
      if (_filterType1Id != null) list = list.where((p) => p.type1Id == _filterType1Id).toList();
      if (_filterType2Id != null) list = list.where((p) => p.type2Id == _filterType2Id).toList();
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
      appBar: AppBar(title: Text(_isEdit ? 'Modifier la vente' : 'Nouvelle vente')),
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
          _buildLegacyRepairCombos(),
          Expanded(
            child: (_filterCategoryMode == CategoryMode.repair && _filterCategoryId != null && _type1Options.isEmpty)
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'Aucun élément (Afficheur, Flash, Connecteur...) pour cette catégorie — ajoutez-en dans le Catalogue.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.grey),
                      ),
                    ),
                  )
                : filtered.isEmpty
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
                                    ? '${p.reference} · prix libre${p.stock != null ? " · stock: ${p.stockLabel}" : ""}'
                                    : isPerfume
                                        ? '${p.reference} · stock: ${p.stockLabel}'
                                        : '${p.reference} · ${p.prix} DA · stock: ${p.stockLabel}',
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
                                            Text('${inCart.unitPrice} DA', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                            IconButton(
                                              icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.grey),
                                              onPressed: () => _editLinePrice(_cartKey(p.id, null)),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                            ),
                                            const SizedBox(width: 4),
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
                                    return InputChip(
                                      label: Text(
                                        '${l.type2Name ?? '?'} × ${l.quantity} · ${l.unitPrice} DA',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      avatar: const Icon(Icons.edit_outlined, size: 16),
                                      onPressed: () => _editLinePrice(key),
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

  /// Old sales made before repair parts became real products stored a
  /// repair job as a "combo" of selected types with one free-typed total
  /// price and no linked product. New sales never create these anymore —
  /// a repair item is just a normal product now, added like any other —
  /// but editing an old sale still needs to show and let you adjust or
  /// remove them.
  Widget _buildLegacyRepairCombos() {
    if (_filterCategoryMode != CategoryMode.repair || _filterCategoryId == null) return const SizedBox.shrink();
    final comboLines = _cart.values.where((l) => l.isRepair && l.categoryId == _filterCategoryId).toList();
    if (comboLines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Réparations (ancien format)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 6),
          ...comboLines.map((l) {
            final key = _repairKey(l.categoryId!, l.repairTypeIds);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(l.label),
                subtitle: Text('${l.unitPrice} DA × ${l.quantity} = ${l.subtotal} DA',
                    style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.grey),
                      onPressed: () => _editRepairPrice(key),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: AppColors.black),
                      onPressed: () => _decrementLine(key),
                    ),
                    Text('${l.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: AppColors.gold),
                      onPressed: () => setState(() => l.quantity++),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final perfume = _filterCategoryMode == CategoryMode.perfume;
    final repair = _filterCategoryMode == CategoryMode.repair;
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
            if (perfume)
              DropdownButtonFormField<int>(
                value: _filterMarqueId,
                decoration: const InputDecoration(labelText: 'Marque'),
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('Toutes les marques')),
                  ..._marques.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))),
                ],
                onChanged: (v) => setState(() => _filterMarqueId = v),
              )
            else
              // 'repair' categories browse by type1 too now (Afficheur,
              // Flash, Connecteur...) — same picker as hierarchical ones.
              TypeChipSelector(
                label: 'Type',
                items: _type1Options,
                selectedId: _filterType1Id,
                onSelect: _onType1FilterChanged,
                allowClear: true,
              ),
          ],
          if (!perfume && !repair && _type2Options.isNotEmpty) ...[
            const SizedBox(height: 12),
            TypeChipSelector(
              label: 'Sous-type',
              items: _type2Options,
              selectedId: _filterType2Id,
              onSelect: (v) => setState(() => _filterType2Id = v),
              allowClear: true,
            ),
          ],
          if (repair && _type1Options.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _quickAddRepairProduct,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nouvelle pièce'),
              ),
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
                : Text(_isEdit ? 'Enregistrer' : 'Valider la vente'),
          ),
        ],
      ),
    );
  }
}
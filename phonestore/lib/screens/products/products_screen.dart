import 'package:flutter/material.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../models/product_type.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/category_icons.dart';
import 'product_form.dart';
import 'catalog_screen.dart';
import '../../widgets/selector_chips.dart';
import '../../widgets/app_logo.dart';
import '../../services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum _ProductSort { defaultOrder, priceAsc, priceDesc, stockAsc, stockDesc }

extension on _ProductSort {
  String get label {
    switch (this) {
      case _ProductSort.defaultOrder:
        return 'Par défaut';
      case _ProductSort.priceAsc:
        return 'Prix (bas → élevé)';
      case _ProductSort.priceDesc:
        return 'Prix (élevé → bas)';
      case _ProductSort.stockAsc:
        return 'Stock (bas → élevé)';
      case _ProductSort.stockDesc:
        return 'Stock (élevé → bas)';
    }
  }

  IconData get icon {
    switch (this) {
      case _ProductSort.defaultOrder:
        return Icons.sort;
      case _ProductSort.priceAsc:
      case _ProductSort.priceDesc:
        return Icons.sell_outlined;
      case _ProductSort.stockAsc:
      case _ProductSort.stockDesc:
        return Icons.inventory_2_outlined;
    }
  }
}

class ProductsScreen extends StatefulWidget {
  /// Workers get a read-only version of this screen: no "Ajouter" FAB, no
  /// catalog management, no delete, and tapping a product shows details
  /// instead of opening the edit form.
  final bool isAdmin;
  const ProductsScreen({super.key, this.isAdmin = true});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _service = SupabaseService.instance;
  bool get _isAdmin => widget.isAdmin;

  List<Category> _categories = [];
  List<ProductType> _type1Options = [];
  List<Product> _allProducts = [];

  int? _selectedCategoryId;
  int? _selectedType1Id;
  String _search = '';
  _ProductSort _sort = _ProductSort.defaultOrder;
  bool _loading = true;
  String? _error;

  bool get _selectedIsPerfume {
    final c = _categories.where((c) => c.id == _selectedCategoryId);
    return c.isNotEmpty && c.first.mode == CategoryMode.perfume;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _categories = await _service.getCategories();
      if (_selectedCategoryId != null && !_selectedIsPerfume) {
        _type1Options = await _service.getTypes(categoryId: _selectedCategoryId, topLevelOnly: true, level: 1);
      } else {
        _type1Options = [];
      }
      _allProducts = await _service.getProducts(
        categoryId: _selectedCategoryId,
        type1Id: _selectedType1Id,
      );
    } catch (e) {
      // Common cause: RLS requires an authenticated session and none exists yet,
      // or the Supabase URL/anon key in main.dart aren't set correctly.
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Search matches the product's reference OR its type/marque/category
  /// names — done client-side since the catalog is small and this avoids a
  /// more complex joined-column search query against Postgrest.
  List<Product> get _filtered {
    var list = _search.trim().isEmpty
        ? List<Product>.from(_allProducts)
        : _allProducts.where((p) => p.searchBlob.contains(_search.trim().toLowerCase())).toList();

    switch (_sort) {
      case _ProductSort.defaultOrder:
        break;
      case _ProductSort.priceAsc:
        list.sort((a, b) => (a.prix ?? 0).compareTo(b.prix ?? 0));
        break;
      case _ProductSort.priceDesc:
        list.sort((a, b) => (b.prix ?? 0).compareTo(a.prix ?? 0));
        break;
      case _ProductSort.stockAsc:
        list.sort((a, b) => (a.stock ?? 0).compareTo(b.stock ?? 0));
        break;
      case _ProductSort.stockDesc:
        list.sort((a, b) => (b.stock ?? 0).compareTo(a.stock ?? 0));
        break;
    }
    return list;
  }

  Future<void> _onCategoryChanged(int? id) async {
    setState(() {
      _selectedCategoryId = id;
      _selectedType1Id = null;
      _type1Options = [];
    });
    await _load();
  }

  Future<void> _onType1Changed(int? id) async {
    setState(() => _selectedType1Id = id);
    await _load();
  }

  Future<void> _openForm({Product? product}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProductForm(product: product)),
    );
    if (saved == true) _load();
  }

  /// Workers can look up a product's full details, they just can't change
  /// anything — this stays a plain read-only dialog rather than opening the
  /// real edit form (product_form.dart is admin-only).
  void _showReadOnlyDetails(Product p) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(p.displayLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Référence', p.reference),
            _detailRow('Prix', p.hasFixedPrice ? '${p.prix} DA' : 'Selon taille'),
            _detailRow('Stock', p.stockLabel),
            if (p.categoryName != null) _detailRow('Catégorie', p.categoryName!),
            if (p.type1Name != null) _detailRow('Type', p.type1Name!),
            if (p.type2Name != null) _detailRow('Variante', p.type2Name!),
            if (p.marqueName != null) _detailRow('Marque', p.marqueName!),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 90, child: Text(label, style: const TextStyle(color: AppColors.grey, fontSize: 12.5))),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );

  Future<void> _confirmDelete(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ce produit ?'),
        content: Text(p.displayLabel),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _service.deleteProduct(p.id);
        _load();
      } on PostgrestException catch (e) {
        if (!mounted) return;
        final message = e.code == '23503'
            ? 'Ce produit a des achats enregistrés et ne peut pas être supprimé.'
            : 'Erreur Supabase (${e.code ?? '?'}): ${e.message}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur inattendue: $e')),
        );
      }
    }
  }

  Future<void> _openSort() async {
    final chosen = await showModalBottomSheet<_ProductSort>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductSortSheet(current: _sort),
    );
    if (chosen != null) setState(() => _sort = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final products = _filtered;
    final lowStockCount = _allProducts.where((p) => p.isLowStock).length;
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(padding: EdgeInsets.all(10), child: AppLogo(size: 26)),
        title: const Text('Produits'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: 'Trier',
            onPressed: _openSort,
          ),
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.category_outlined),
              tooltip: 'Gérer catégories / types / marques',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CatalogScreen()),
                );
                _load();
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
            onPressed: () => AuthService.instance.signOut(),
          ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, color: AppColors.grey),
                hintText: 'Chercher par référence, type, marque...',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          _buildFilters(),
          if (_sort != _ProductSort.defaultOrder || lowStockCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  if (_sort != _ProductSort.defaultOrder) ...[
                    Icon(_sort.icon, size: 13, color: AppColors.gold),
                    const SizedBox(width: 5),
                    Text(_sort.label, style: const TextStyle(color: AppColors.grey, fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                  const Spacer(),
                  if (lowStockCount > 0)
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.danger),
                        const SizedBox(width: 4),
                        Text(
                          '$lowStockCount stock faible',
                          style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
                              const SizedBox(height: 12),
                              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.grey)),
                              const SizedBox(height: 16),
                              ElevatedButton(onPressed: _load, child: const Text('Réessayer')),
                            ],
                          ),
                        ),
                      )
                    : products.isEmpty
                    ? const Center(child: Text('Aucun produit', style: TextStyle(color: AppColors.grey)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.gold,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: products.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _ProductCard(
                            product: products[i],
                            onTap: () => _isAdmin ? _openForm(product: products[i]) : _showReadOnlyDetails(products[i]),
                            onDelete: _isAdmin ? () => _confirmDelete(products[i]) : null,
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CategoryIconPicker(
            categories: _categories.where((c) => c.mode != CategoryMode.repair).toList(),
            selectedId: _selectedCategoryId,
            onSelect: _onCategoryChanged,
            allowClear: true,
          ),
          if (_selectedCategoryId != null && !_selectedIsPerfume) ...[
            const SizedBox(height: 12),
            TypeChipSelector(
              label: 'Type',
              items: _type1Options,
              selectedId: _selectedType1Id,
              onSelect: _onType1Changed,
              allowClear: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductSortSheet extends StatelessWidget {
  final _ProductSort current;
  const _ProductSortSheet({required this.current});

  @override
  Widget build(BuildContext context) {
    Widget tile(_ProductSort s) {
      final selected = s == current;
      return ListTile(
        leading: Icon(s.icon, color: selected ? AppColors.gold : AppColors.grey),
        title: Text(s.label, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        trailing: selected ? const Icon(Icons.check, color: AppColors.gold) : null,
        onTap: () => Navigator.pop(context, s),
      );
    }

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const Text('Trier par', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            tile(_ProductSort.defaultOrder),
            tile(_ProductSort.priceAsc),
            tile(_ProductSort.priceDesc),
            tile(_ProductSort.stockAsc),
            tile(_ProductSort.stockDesc),
          ],
        ),
      ),
    );
  }
}

/// Card layout: marque + niveau2 name large & bold on their own line,
/// niveau1 type + category smaller underneath, and the reference code in
/// tiny muted text at the very bottom — matches how a worker actually scans
/// for a product (brand/variant first, broad category second, code last to
/// confirm). Products under the low-stock threshold get a subtle red tint
/// and a warning badge so they stand out while scrolling.
class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _ProductCard({required this.product, required this.onTap, required this.onDelete});

  bool get _lowStock => product.isLowStock;

  @override
  Widget build(BuildContext context) {
    final primaryParts = [product.marqueName, product.type2Name].where((e) => e != null && e.isNotEmpty).toList();
    final primaryLine = primaryParts.isNotEmpty ? primaryParts.join(' - ') : (product.name ?? product.type1Name ?? '');

    final secondaryParts = [product.type1Name, product.categoryName].where((e) => e != null && e.isNotEmpty).toList();
    final secondaryLine = secondaryParts.join(' - ');

    return Material(
      color: _lowStock ? AppColors.danger.withValues(alpha: 0.05) : AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _lowStock ? AppColors.danger.withValues(alpha: 0.35) : const Color(0xFFEDEBE5),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (product.displayImageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Image.network(product.displayImageUrl!, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primaryLine,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(iconForKey(product.categoryIconKey), size: 12, color: AppColors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            secondaryLine,
                            style: const TextStyle(color: AppColors.grey, fontSize: 12.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          product.reference,
                          style: const TextStyle(color: AppColors.grey, fontSize: 10.5, letterSpacing: 0.3),
                        ),
                        const SizedBox(width: 8),
                        if (_lowStock)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_amber_rounded, size: 11, color: AppColors.danger),
                                const SizedBox(width: 3),
                                Text(
                                  'Stock faible · ${product.stockLabel}',
                                  style: const TextStyle(
                                    color: AppColors.danger,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Text(
                            product.stockLabel,
                            style: const TextStyle(color: AppColors.grey, fontSize: 10.5),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    product.hasFixedPrice ? '${product.prix} DA' : 'Prix / taille',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.black),
                  ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                      onPressed: onDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
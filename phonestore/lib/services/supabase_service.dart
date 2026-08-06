import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category.dart';
import '../models/product_type.dart';
import '../models/marque.dart';
import '../models/product.dart';
import '../models/achat.dart';
import '../models/depense.dart';

/// Which ranking to use for "top products" / "top repairs": by units sold
/// or by revenue generated. Both are precomputed in the matview via RANK().
enum TopProductsMetric { quantity, revenue }

/// Single access point to Supabase: tables, storage, and analytics views.
/// Keeping every query in one place makes the screens thin and easy to read.
///
/// Categories, product types, and marques change rarely, so this service
/// caches them in memory for the lifetime of the app session and only
/// re-fetches after a write. That keeps read traffic (and your Supabase
/// usage) low without adding a real caching layer.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get _c => Supabase.instance.client;

  List<Category>? _categoriesCache;
  List<Marque>? _marquesCache;
  final Map<String, List<ProductType>> _typesCache = {};

  void _invalidateTypesCache() => _typesCache.clear();

  // ---------------- CATEGORIES ----------------
  Future<List<Category>> getCategories() async {
    if (_categoriesCache != null) return _categoriesCache!;
    final data = await _c.from('categories').select().order('name');
    _categoriesCache = (data as List).map((e) => Category.fromMap(e)).toList();
    return _categoriesCache!;
  }

  /// Returns the category id (existing id on update, new id on insert).
  Future<int> upsertCategory({
    int? id,
    required String name,
    required String iconKey,
    CategoryMode mode = CategoryMode.hierarchical,
  }) async {
    final map = {'name': name, 'icon_key': iconKey, 'mode': categoryModeToString(mode)};
    int resultId;
    if (id == null) {
      final row = await _c.from('categories').insert(map).select('id').single();
      resultId = row['id'] as int;
    } else {
      await _c.from('categories').update(map).eq('id', id);
      resultId = id;
    }
    _categoriesCache = null;
    return resultId;
  }

  Future<void> deleteCategory(int id) async {
    await _c.from('categories').delete().eq('id', id);
    _categoriesCache = null;
  }

  // ---------------- PRODUCT TYPES (2 levels: type1 -> optional type2) ----------------
  // For 'perfume' categories, both the parfum-name list (level 1) and the
  // taille/bottle-size list (level 2) are stored as flat, parent-less rows
  // (parent_id null) — they're a parallel pair of lists, not a hierarchy.
  // `level` disambiguates the two when parentId isn't given.
  Future<List<ProductType>> getTypes({int? categoryId, int? parentId, bool topLevelOnly = false, int? level}) async {
    final cacheKey = topLevelOnly ? 'top:$categoryId:lvl$level' : 'child:$parentId';
    final cached = _typesCache[cacheKey];
    if (cached != null) return cached;

    var query = _c.from('product_types').select();
    if (categoryId != null) query = query.eq('category_id', categoryId);
    if (topLevelOnly) {
      query = query.isFilter('parent_id', null);
      if (level != null) query = query.eq('level', level);
    } else if (parentId != null) {
      query = query.eq('parent_id', parentId);
    }
    final data = await query.order('name');
    final result = (data as List).map((e) => ProductType.fromMap(e)).toList();
    _typesCache[cacheKey] = result;
    return result;
  }

  /// Returns the type id (existing id on update, new id on insert).
  Future<int> upsertType({
    int? id,
    required int categoryId,
    int? parentId,
    required String name,
    String? imageUrl,
    required int level,
    double? volumeLiters,
    int? prix,
  }) async {
    final map = {
      'category_id': categoryId,
      'parent_id': parentId,
      'name': name,
      'image_url': imageUrl,
      'level': level,
      'volume_liters': volumeLiters,
      'prix': prix,
    };
    int resultId;
    if (id == null) {
      final row = await _c.from('product_types').insert(map).select('id').single();
      resultId = row['id'] as int;
    } else {
      await _c.from('product_types').update(map).eq('id', id);
      resultId = id;
    }
    _invalidateTypesCache();
    return resultId;
  }

  Future<void> deleteType(int id) async {
    await _c.from('product_types').delete().eq('id', id);
    _invalidateTypesCache();
  }

  // ---------------- MARQUES ----------------
  Future<List<Marque>> getMarques({MarqueType? type}) async {
    if (_marquesCache == null) {
      final data = await _c.from('marques').select().order('name');
      _marquesCache = (data as List).map((e) => Marque.fromMap(e)).toList();
    }
    if (type == null) return _marquesCache!;
    return _marquesCache!.where((m) => m.type == type).toList();
  }

  /// Returns the marque id (existing id on update, new id on insert).
  Future<int> upsertMarque({int? id, required String name, MarqueType type = MarqueType.tech}) async {
    final map = {'name': name, 'type': marqueTypeToString(type)};
    int resultId;
    if (id == null) {
      final row = await _c.from('marques').insert(map).select('id').single();
      resultId = row['id'] as int;
    } else {
      await _c.from('marques').update(map).eq('id', id);
      resultId = id;
    }
    _marquesCache = null;
    return resultId;
  }

  Future<void> deleteMarque(int id) async {
    await _c.from('marques').delete().eq('id', id);
    _marquesCache = null;
  }

  // ---------------- PRODUCTS ----------------
  static const _productSelect = '''
    *,
    categories:category_id ( name, icon_key, mode ),
    type1:type1_id ( name, image_url ),
    type2:type2_id ( name, image_url ),
    marques:marque_id ( name )
  ''';

  Future<List<Product>> getProducts({int? categoryId, int? type1Id, int? type2Id}) async {
    var query = _c.from('products').select(_productSelect);
    if (categoryId != null) query = query.eq('category_id', categoryId);
    if (type1Id != null) query = query.eq('type1_id', type1Id);
    if (type2Id != null) query = query.eq('type2_id', type2Id);
    final data = await query.order('id', ascending: false);
    return (data as List).map((e) => Product.fromMap(e)).toList();
  }

  /// Returns the product id (existing id on update, new id on insert).
  Future<int> upsertProduct({int? id, required Product product}) async {
    final map = product.toMap();
    if (id == null) {
      final row = await _c.from('products').insert(map).select('id').single();
      return row['id'] as int;
    } else {
      await _c.from('products').update(map).eq('id', id);
      return id;
    }
  }

  Future<void> deleteProduct(int id) => _c.from('products').delete().eq('id', id);

  // ---------------- ACHATS ----------------
  static const _achatItemSelect = '''
    *,
    products:product_id ($_productSelect),
    taille:type2_id ( name, volume_liters, prix ),
    categories:category_id ( name, icon_key ),
    achat_item_types ( type_id )
  ''';

  Future<List<Achat>> getAchats() async {
    final data = await _c
        .from('achats')
        .select('*, achat_items ( $_achatItemSelect )')
        .order('achat_date', ascending: false)
        .order('achat_time', ascending: false);
    return (data as List).map((e) => Achat.fromMap(e)).toList();
  }

  /// Creates an achat with its items in one call. Total price and stock are
  /// kept in sync by Postgres triggers, so we only insert the raw rows here.
  ///
  /// achat_date/achat_time are stamped from the device's local clock rather
  /// than left to the database defaults: Postgres' `current_date`/
  /// `current_time` run in the server's timezone (Supabase servers default
  /// to UTC), so a sale made in the evening in a UTC+1 shop could otherwise
  /// get silently filed under the wrong calendar day in the daily revenue
  /// chart.
  Future<int> createAchat({required List<AchatItem> items}) async {
    final now = DateTime.now();
    final datePart =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final timePart =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    final achatRow = await _c
        .from('achats')
        .insert({'achat_date': datePart, 'achat_time': timePart})
        .select('id')
        .single();
    final achatId = achatRow['id'] as int;
    await _insertAchatItems(achatId: achatId, items: items);
    return achatId;
  }

  Future<void> deleteAchat(int id) => _c.from('achats').delete().eq('id', id);

  Future<void> updateAchatItems({required int achatId, required List<AchatItem> items}) async {
    // simplest safe approach: replace all items for this achat. Deleting
    // achat_items cascades into achat_item_types automatically.
    await _c.from('achat_items').delete().eq('achat_id', achatId);
    await _insertAchatItems(achatId: achatId, items: items);
  }

  /// Inserts achat_items rows for [items], then — for any repair combo line
  /// carrying bundled type ids — inserts the matching achat_item_types rows
  /// once the real achat_item ids come back from Postgres.
  Future<void> _insertAchatItems({required int achatId, required List<AchatItem> items}) async {
    if (items.isEmpty) return;
    final itemRows = items
        .map((i) => {
              'achat_id': achatId,
              'product_id': i.productId,
              'quantity': i.quantity,
              'unit_price': i.unitPrice,
              'type2_id': i.type2Id,
              'category_id': i.categoryId,
              'label': i.label,
            })
        .toList();
    final inserted = await _c.from('achat_items').insert(itemRows).select('id');
    final insertedIds = (inserted as List).map((r) => r['id'] as int).toList();

    final comboRows = <Map<String, dynamic>>[];
    for (var i = 0; i < items.length; i++) {
      for (final typeId in items[i].typeIds) {
        comboRows.add({'achat_item_id': insertedIds[i], 'type_id': typeId});
      }
    }
    if (comboRows.isNotEmpty) await _c.from('achat_item_types').insert(comboRows);
  }

  // ---------------- DEPENSES (store expenses) ----------------
  Future<List<Depense>> getDepenses() async {
    final data = await _c.from('depenses').select().order('depense_date', ascending: false);
    return (data as List).map((e) => Depense.fromMap(e)).toList();
  }

  Future<int> upsertDepense({int? id, required Depense depense}) async {
    final map = depense.toMap();
    if (id == null) {
      final row = await _c.from('depenses').insert(map).select('id').single();
      return row['id'] as int;
    } else {
      await _c.from('depenses').update(map).eq('id', id);
      return id;
    }
  }

  Future<void> deleteDepense(int id) => _c.from('depenses').delete().eq('id', id);

  Future<List<Map<String, dynamic>>> getDailyDepenses() async {
    final data = await _c.from('v_daily_depenses').select().order('depense_date');
    return (data as List).cast<Map<String, dynamic>>();
  }

  // ---------------- ANALYTICS ----------------
  // achat_date is stamped from the device's local clock (see createAchat),
  // so every analytics query that means "today" or "this month" reuses
  // that same local date rather than the DB server's UTC clock — otherwise
  // a late-evening sale in a UTC+1 shop could fall on the wrong side of
  // the KPI's day/month boundary.
  String _localDateString(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Single round trip for the KPI row at the top of the Analyse page:
  /// achats today (sum + count), achats this month (sum + count),
  /// depenses this month, net profit, and month-over-month growth %.
  Future<Map<String, dynamic>> getAnalyticsKpis() async {
    final today = _localDateString(DateTime.now());
    final data = await _c.rpc('get_analytics_kpis', params: {'p_today': today});
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.isNotEmpty ? rows.first : const {};
  }

  /// Achats count + revenue per hour (0-23) for today — zero-filled by the
  /// SQL function, so the bar chart never has to guess at missing hours.
  Future<List<Map<String, dynamic>>> getHourlyAchatsToday() async {
    final today = _localDateString(DateTime.now());
    final data = await _c.rpc('get_hourly_achats', params: {'p_date': today});
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Daily revenue history for the line chart. Values are per-day, not
  /// cumulative — the screen itself decides whether to plot raw or a
  /// running total.
  Future<List<Map<String, dynamic>>> getDailyRevenue() async {
    final data = await _c.from('mv_daily_revenue').select().order('achat_date');
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Top products, ranked either by units sold or by revenue (the two
  /// metrics the user can toggle between) — both ranks live on the same
  /// matview row, computed with RANK() in Postgres.
  Future<List<Map<String, dynamic>>> getTopProducts({
    int limit = 10,
    TopProductsMetric metric = TopProductsMetric.quantity,
  }) async {
    final rankColumn = metric == TopProductsMetric.quantity ? 'rank_by_qty' : 'rank_by_revenue';
    final data = await _c.from('mv_top_products').select().order(rankColumn).limit(limit);
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Top repair/service combos (achat_items with no product_id), ranked
  /// the same way as products. Previously invisible to analytics.
  Future<List<Map<String, dynamic>>> getTopRepairs({
    int limit = 10,
    TopProductsMetric metric = TopProductsMetric.quantity,
  }) async {
    final rankColumn = metric == TopProductsMetric.quantity ? 'rank_by_qty' : 'rank_by_revenue';
    final data = await _c.from('mv_top_repairs').select().order(rankColumn).limit(limit);
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Revenue by category, including repair-line revenue (fixed — the old
  /// view only joined through products and silently dropped repairs).
  /// Excludes the ROLLUP grand-total row; use [getRevenueTotal] for that.
  Future<List<Map<String, dynamic>>> getRevenueByCategory() async {
    final data = await _c.from('mv_revenue_by_category').select().eq('is_total', false).order('revenue', ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// The ROLLUP grand-total row from the same matview — one extra filter,
  /// no extra query.
  Future<int> getRevenueTotal() async {
    final data = await _c.from('mv_revenue_by_category').select('revenue').eq('is_total', true).maybeSingle();
    return (data?['revenue'] as num?)?.toInt() ?? 0;
  }

  /// Recomputes every analytics matview. Bound to the refresh button on
  /// the Analyse page instead of firing on every achat/achat_item write —
  /// a sale shouldn't pay the cost of recomputing all of sales history
  /// just to add one row.
  Future<void> refreshAnalytics() => _c.rpc('refresh_analytics');

  // ---------------- STORAGE ----------------
  static const _bucket = 'shop-images';

  /// Images are entirely optional for product types and products (categories
  /// use a built-in icon, and marques are text-only — see their models).
  /// When one is provided, the caller (image_picker) is configured to
  /// compress it down (low quality, capped dimensions) before it ever
  /// reaches this method, to keep Supabase storage usage small.
  Future<String> uploadImage({
    required String folder, // product-types | products
    required String fileName, // e.g. '12.jpg'
    required Uint8List bytes,
  }) async {
    final path = '$folder/$fileName';
    await _c.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return _c.storage.from(_bucket).getPublicUrl(path);
  }
}
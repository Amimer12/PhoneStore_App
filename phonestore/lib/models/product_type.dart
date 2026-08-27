class ProductType {
  final int id;
  final int categoryId;
  final int? parentId;
  final String name;
  final String? imageUrl;
  final int level;

  /// Bottle size in liters. Only meaningful for a level-2 row under a
  /// 'perfume' category (the "Taille" list) — null for everything else.
  /// Tailles are stored as flat, parent-less rows (parentId == null) so
  /// they apply to every parfum in the category rather than one specific
  /// parfum: a parallel list, not a hierarchical sous-type.
  final double? volumeLiters;

  /// Bottle price in DA. Only meaningful for a level-2 "taille" row under a
  /// 'perfume' category — this is now where the perfume price actually
  /// lives (the product itself no longer carries a fixed price). Null for
  /// every non-perfume type row.
  final int? prix;

  /// Whether products under this type participate in the low-stock alert
  /// at all. Defaults to true. Meant to be switched off for a type the
  /// store deliberately stocks one unit of at a time (e.g. a specific rare
  /// phone model) — otherwise that type would sit permanently flagged as
  /// "stock faible" even though that's just how it's normally stocked.
  final bool stockAlertActivated;

  ProductType({
    required this.id,
    required this.categoryId,
    this.parentId,
    required this.name,
    this.imageUrl,
    required this.level,
    this.volumeLiters,
    this.prix,
    this.stockAlertActivated = true,
  });

  factory ProductType.fromMap(Map<String, dynamic> map) => ProductType(
        id: map['id'] as int,
        categoryId: map['category_id'] as int,
        parentId: map['parent_id'] as int?,
        name: map['name'] as String,
        imageUrl: map['image_url'] as String?,
        level: map['level'] as int? ?? 1,
        volumeLiters: (map['volume_liters'] as num?)?.toDouble(),
        prix: map['prix'] as int?,
        stockAlertActivated: map['stock_alert_activated'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'category_id': categoryId,
        'parent_id': parentId,
        'name': name,
        'image_url': imageUrl,
        'level': level,
        'volume_liters': volumeLiters,
        'prix': prix,
        'stock_alert_activated': stockAlertActivated,
      };

  /// e.g. "100ml" for 0.1L, "1.5L" for 1.5 — used to label taille chips.
  String get volumeLabel {
    final v = volumeLiters;
    if (v == null) return name;
    if (v < 1) return '${(v * 1000).round()}ml';
    return v % 1 == 0 ? '${v.toInt()}L' : '${v.toStringAsFixed(2)}L';
  }

  /// e.g. "1200 DA" — null when no price was set on this taille yet.
  String? get priceLabel => prix == null ? null : '$prix DA';
}

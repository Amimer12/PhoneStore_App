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

  ProductType({
    required this.id,
    required this.categoryId,
    this.parentId,
    required this.name,
    this.imageUrl,
    required this.level,
    this.volumeLiters,
  });

  factory ProductType.fromMap(Map<String, dynamic> map) => ProductType(
        id: map['id'] as int,
        categoryId: map['category_id'] as int,
        parentId: map['parent_id'] as int?,
        name: map['name'] as String,
        imageUrl: map['image_url'] as String?,
        level: map['level'] as int? ?? 1,
        volumeLiters: (map['volume_liters'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'category_id': categoryId,
        'parent_id': parentId,
        'name': name,
        'image_url': imageUrl,
        'level': level,
        'volume_liters': volumeLiters,
      };

  /// e.g. "100ml" for 0.1L, "1.5L" for 1.5 — used to label taille chips.
  String get volumeLabel {
    final v = volumeLiters;
    if (v == null) return name;
    if (v < 1) return '${(v * 1000).round()}ml';
    return v % 1 == 0 ? '${v.toInt()}L' : '${v.toStringAsFixed(2)}L';
  }
}

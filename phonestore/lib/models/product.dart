class Product {
  final int id;
  final String reference;
  final String? name;
  final int categoryId;

  /// Null for perfume-category products — perfume products are identified
  /// by their marque alone, not a type1 ("nom du parfum") row anymore.
  final int? type1Id;
  final int? type2Id;
  final int? marqueId;

  /// Null for perfume-category products — the price now lives on the
  /// taille (bottle size) chosen at purchase time, not on the product.
  final int? prix;
  /// Null means "not tracked" — only meaningful for 'simple' category
  /// products, where stock is optional. Hierarchical/perfume products
  /// always get a numeric value (defaulting to 0) from the form.
  final double? stock;
  final String? imageUrl;

  // Convenience fields populated when the query joins related tables.
  final String? categoryName;
  final String? categoryIconKey;
  final String? categoryMode;
  final String? type1Name;
  final String? type1ImageUrl;
  final String? type2Name;
  final String? type2ImageUrl;
  final String? marqueName;

  Product({
    required this.id,
    required this.reference,
    this.name,
    required this.categoryId,
    this.type1Id,
    this.type2Id,
    this.marqueId,
    this.prix,
    this.stock,
    this.imageUrl,
    this.categoryName,
    this.categoryIconKey,
    this.categoryMode,
    this.type1Name,
    this.type1ImageUrl,
    this.type2Name,
    this.type2ImageUrl,
    this.marqueName,
  });

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as int,
        reference: map['reference'] as String? ?? '',
        name: map['name'] as String?,
        categoryId: map['category_id'] as int,
        type1Id: map['type1_id'] as int?,
        type2Id: map['type2_id'] as int?,
        marqueId: map['marque_id'] as int?,
        prix: map['prix'] as int?,
        stock: (map['stock'] as num?)?.toDouble(),
        imageUrl: map['image_url'] as String?,
        categoryName: (map['categories'] as Map?)?['name'] as String?,
        categoryIconKey: (map['categories'] as Map?)?['icon_key'] as String?,
        categoryMode: (map['categories'] as Map?)?['mode'] as String?,
        type1Name: (map['type1'] as Map?)?['name'] as String?,
        type1ImageUrl: (map['type1'] as Map?)?['image_url'] as String?,
        type2Name: (map['type2'] as Map?)?['name'] as String?,
        type2ImageUrl: (map['type2'] as Map?)?['image_url'] as String?,
        marqueName: (map['marques'] as Map?)?['name'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'reference': reference,
        'name': name,
        'category_id': categoryId,
        'type1_id': type1Id,
        'type2_id': type2Id,
        'marque_id': marqueId,
        'prix': prix,
        'stock': stock,
        'image_url': imageUrl,
      };

  String get displayLabel {
    final parts = [type1Name, type2Name, marqueName]
        .where((e) => e != null && e.isNotEmpty)
        .join(' • ');
    return name?.isNotEmpty == true ? name! : parts;
  }

  /// Falls back to the type2 photo, then the type1 photo, when the product
  /// itself has no image — so a product doesn't have to be photographed
  /// individually just to look recognizable in a list.
  String? get displayImageUrl => imageUrl ?? type2ImageUrl ?? type1ImageUrl;

  /// Text blob used for client-side search across reference, name, and types
  /// — avoids adding a dedicated search endpoint for what's a small dataset.
  String get searchBlob => [reference, name, type1Name, type2Name, marqueName, categoryName]
      .where((e) => e != null)
      .join(' ')
      .toLowerCase();

  bool get isPerfume => categoryMode == 'perfume';

  /// False for perfume products — their price is chosen per taille (bottle
  /// size) at purchase time rather than fixed on the product.
  bool get hasFixedPrice => prix != null;

  /// Perfume low-stock threshold: 200ml. Non-perfume threshold: 2 units.
  static const double lowStockPerfumeLiters = 0.2;
  static const double lowStockUnits = 2;

  /// Perfume stock is a liter volume ("2.5 L"); everything else is a plain
  /// unit count with no decimals. "—" when stock isn't tracked at all
  /// (only possible for 'simple' category products).
  String get stockLabel {
    final s = stock;
    if (s == null) return '—';
    return isPerfume ? '${s % 1 == 0 ? s.toInt() : s.toStringAsFixed(2)} L' : s.toInt().toString();
  }

  /// False when stock isn't tracked (null) — a 'simple' product left
  /// without a stock value is never flagged as low stock. Otherwise
  /// perfume uses the 200ml threshold, everything else uses 2 units.
  bool get isLowStock {
    final s = stock;
    if (s == null) return false;
    return s < (isPerfume ? lowStockPerfumeLiters : lowStockUnits);
  }
}
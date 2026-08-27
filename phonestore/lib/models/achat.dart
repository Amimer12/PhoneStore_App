import 'product.dart';

class AchatItem {
  final int? id;
  final int? achatId;

  /// Null for a 'repair' combo line — those have no product at all, only a
  /// category + a bundle of types (see [categoryId]/[label]/[typeIds]).
  final int? productId;
  final int quantity;
  final int unitPrice;

  /// Snapshot of the product's prix_achat at the moment of sale. Null for
  /// repair/service lines, and for sales made before cost tracking existed.
  final int? unitCost;

  /// The bottle size (product_types row) chosen for this line — only set
  /// for products whose category is in 'perfume' mode. Null for everything
  /// else.
  final int? type2Id;
  final String? type2Name; // populated on read for display

  /// The category this line belongs to — only set for 'repair' combo lines
  /// (products already carry their own category via [product]).
  final int? categoryId;
  final String? categoryName; // populated on read for display

  /// Human readable snapshot of the combo, e.g. "Afficheur + Flash +
  /// Connecteur" — stored as-is on the row so history stays readable even
  /// if a type gets renamed or removed later. Only set for repair lines.
  final String? label;

  /// The product_types ids bundled into this repair combo line. Empty for
  /// normal product lines. Written on save and populated on read via the
  /// achat_item_types join table.
  final List<int> typeIds;

  final Product? product; // populated on read for display

  AchatItem({
    this.id,
    this.achatId,
    this.productId,
    required this.quantity,
    required this.unitPrice,
    this.unitCost,
    this.type2Id,
    this.type2Name,
    this.categoryId,
    this.categoryName,
    this.label,
    this.typeIds = const [],
    this.product,
  });

  int get subtotal => quantity * unitPrice;

  /// Null when unitCost isn't known (repair line, or sold before cost
  /// tracking existed) — distinct from 0, which would wrongly imply "free".
  int? get costSubtotal => unitCost != null ? quantity * unitCost! : null;
  int? get profitSubtotal => unitCost != null ? subtotal - costSubtotal! : null;

  /// True for a 'repair' combo line — no product backs this line.
  bool get isRepair => productId == null;

  factory AchatItem.fromMap(Map<String, dynamic> map) => AchatItem(
        id: map['id'] as int?,
        achatId: map['achat_id'] as int?,
        productId: map['product_id'] as int?,
        quantity: map['quantity'] as int,
        unitPrice: map['unit_price'] as int,
        unitCost: map['unit_cost'] as int?,
        type2Id: map['type2_id'] as int?,
        type2Name: (map['taille'] as Map?)?['name'] as String?,
        categoryId: map['category_id'] as int?,
        categoryName: (map['categories'] as Map?)?['name'] as String?,
        label: map['label'] as String?,
        typeIds: (map['achat_item_types'] as List<dynamic>?)
                ?.map((e) => (e as Map<String, dynamic>)['type_id'] as int)
                .toList() ??
            const [],
        product: map['products'] != null
            ? Product.fromMap(map['products'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toMap() => {
        'product_id': productId,
        'quantity': quantity,
        'unit_price': unitPrice,
        'unit_cost': unitCost,
        'type2_id': type2Id,
        'category_id': categoryId,
        'label': label,
      };
}

class Achat {
  final int? id;
  final DateTime date;
  final int totalPrice;
  final int totalCost;
  final int totalProfit;
  final List<AchatItem> items;

  Achat({
    this.id,
    required this.date,
    this.totalPrice = 0,
    this.totalCost = 0,
    this.totalProfit = 0,
    this.items = const [],
  });

  factory Achat.fromMap(Map<String, dynamic> map) => Achat(
        id: map['id'] as int?,
        date: DateTime.parse(map['achat_date'] as String),
        totalPrice: map['total_price'] as int? ?? 0,
        totalCost: map['total_cost'] as int? ?? 0,
        totalProfit: map['total_profit'] as int? ?? map['total_price'] as int? ?? 0,
        items: (map['achat_items'] as List<dynamic>?)
                ?.map((e) => AchatItem.fromMap(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
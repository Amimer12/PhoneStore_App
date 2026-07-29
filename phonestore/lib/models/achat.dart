import 'product.dart';

class AchatItem {
  final int? id;
  final int? achatId;
  final int productId;
  final int quantity;
  final int unitPrice;

  /// The bottle size (product_types row) chosen for this line — only set
  /// for products whose category is in 'perfume' mode. Null for everything
  /// else.
  final int? type2Id;
  final String? type2Name; // populated on read for display

  final Product? product; // populated on read for display

  AchatItem({
    this.id,
    this.achatId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.type2Id,
    this.type2Name,
    this.product,
  });

  int get subtotal => quantity * unitPrice;

  factory AchatItem.fromMap(Map<String, dynamic> map) => AchatItem(
        id: map['id'] as int?,
        achatId: map['achat_id'] as int?,
        productId: map['product_id'] as int,
        quantity: map['quantity'] as int,
        unitPrice: map['unit_price'] as int,
        type2Id: map['type2_id'] as int?,
        type2Name: (map['taille'] as Map?)?['name'] as String?,
        product: map['products'] != null
            ? Product.fromMap(map['products'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toMap() => {
        'product_id': productId,
        'quantity': quantity,
        'unit_price': unitPrice,
        'type2_id': type2Id,
      };
}

class Achat {
  final int? id;
  final DateTime date;
  final int totalPrice;
  final List<AchatItem> items;

  Achat({this.id, required this.date, this.totalPrice = 0, this.items = const []});

  factory Achat.fromMap(Map<String, dynamic> map) => Achat(
        id: map['id'] as int?,
        date: DateTime.parse(map['achat_date'] as String),
        totalPrice: map['total_price'] as int? ?? 0,
        items: (map['achat_items'] as List<dynamic>?)
                ?.map((e) => AchatItem.fromMap(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

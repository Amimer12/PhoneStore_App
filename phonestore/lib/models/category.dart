/// How the app should treat products/achats for this category.
/// - hierarchical: normal type1 + optional type2, fixed price per product (Electronics)
/// - simple: type1 only, no fixed price — typed in manually at sale time (Flexy)
/// - perfume: type1/type2 reused as "Nom du parfum" / "Taille", fixed price per combo (Perfum)
/// - repair: single level of types, NO products at all — at sale time the
///   worker picks one or more types (e.g. Afficheur + Flash + Connecteur)
///   and types in a single total price for the whole combo (Reparation).
enum CategoryMode { hierarchical, simple, perfume, repair }

CategoryMode categoryModeFromString(String s) {
  switch (s) {
    case 'simple':
      return CategoryMode.simple;
    case 'perfume':
      return CategoryMode.perfume;
    case 'repair':
      return CategoryMode.repair;
    default:
      return CategoryMode.hierarchical;
  }
}

String categoryModeToString(CategoryMode m) => m.name;

class Category {
  final int id;
  final String name;
  final String iconKey;
  final CategoryMode mode;

  Category({
    required this.id,
    required this.name,
    this.iconKey = 'category',
    this.mode = CategoryMode.hierarchical,
  });

  factory Category.fromMap(Map<String, dynamic> map) => Category(
        id: map['id'] as int,
        name: map['name'] as String,
        iconKey: map['icon_key'] as String? ?? 'category',
        mode: categoryModeFromString(map['mode'] as String? ?? 'hierarchical'),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'icon_key': iconKey,
        'mode': categoryModeToString(mode),
      };
}

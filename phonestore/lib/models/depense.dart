class Depense {
  final int? id;
  final String name;
  final int prix;
  final DateTime date;

  Depense({this.id, required this.name, required this.prix, required this.date});

  factory Depense.fromMap(Map<String, dynamic> map) => Depense(
        id: map['id'] as int?,
        name: map['name'] as String,
        prix: map['prix'] as int,
        date: DateTime.parse(map['depense_date'] as String),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'prix': prix,
        'depense_date': date.toIso8601String().split('T').first,
      };
}

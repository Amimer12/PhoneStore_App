/// Which side of the catalog a marque belongs to. Products in a 'perfume'
/// category may only pick a perfum marque, everything else may only pick a
/// tech marque — the two lists never mix in the picker.
enum MarqueType { tech, perfum }

MarqueType marqueTypeFromString(String s) {
  switch (s) {
    case 'perfum':
      return MarqueType.perfum;
    default:
      return MarqueType.tech;
  }
}

String marqueTypeToString(MarqueType t) => t.name;

class Marque {
  final int id;
  final String name;
  final MarqueType type;

  Marque({required this.id, required this.name, this.type = MarqueType.tech});

  factory Marque.fromMap(Map<String, dynamic> map) => Marque(
        id: map['id'] as int,
        name: map['name'] as String,
        type: marqueTypeFromString(map['type'] as String? ?? 'tech'),
      );

  Map<String, dynamic> toMap() => {'name': name, 'type': marqueTypeToString(type)};
}

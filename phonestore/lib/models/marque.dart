class Marque {
  final int id;
  final String name;

  Marque({required this.id, required this.name});

  factory Marque.fromMap(Map<String, dynamic> map) => Marque(
        id: map['id'] as int,
        name: map['name'] as String,
      );

  Map<String, dynamic> toMap() => {'name': name};
}

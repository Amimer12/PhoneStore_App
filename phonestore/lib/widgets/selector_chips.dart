import 'package:flutter/material.dart';
import '../models/category.dart';
import '../models/product_type.dart';
import '../theme/app_theme.dart';
import '../theme/category_icons.dart';

/// A small set of muted colors used to generate a consistent letter-avatar
/// per name when a type has no photo — cheap, on-device, no storage.
const _avatarColors = [
  Color(0xFFB08B2E),
  Color(0xFF6B7280),
  Color(0xFF8D6E63),
  Color(0xFF546E7A),
  Color(0xFF7B5E57),
  Color(0xFF5C6BC0),
];

Color _colorForName(String s) {
  final sum = s.codeUnits.fold<int>(0, (a, b) => a + b);
  return _avatarColors[sum % _avatarColors.length];
}

Widget _letterAvatar(String name) {
  final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
  return Container(
    color: _colorForName(name),
    alignment: Alignment.center,
    child: Text(letter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
  );
}

Widget _addCircle() => Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.offWhite,
        border: Border.all(color: AppColors.gold, width: 1.4),
      ),
      child: const Icon(Icons.add, color: AppColors.gold),
    );

/// Horizontal row of tappable chips (photo, or a letter avatar as fallback)
/// for picking a product type. Recognize-then-tap is faster here than
/// reading through a dropdown, especially once photos are set.
class TypeChipSelector extends StatelessWidget {
  final String label;
  final List<ProductType> items;
  final int? selectedId;
  final ValueChanged<int?> onSelect;
  final VoidCallback? onAddNew;
  final bool allowClear;

  const TypeChipSelector({
    super.key,
    required this.label,
    required this.items,
    required this.selectedId,
    required this.onSelect,
    this.onAddNew,
    this.allowClear = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        SizedBox(
          height: 82,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (allowClear) _chip(id: null, name: 'Aucun', imageUrl: null, selected: selectedId == null),
              ...items.map((t) => _chip(id: t.id, name: t.name, imageUrl: t.imageUrl, selected: selectedId == t.id)),
              if (onAddNew != null) _addChip(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip({required int? id, required String name, String? imageUrl, required bool selected}) {
    return GestureDetector(
      onTap: () => onSelect(id),
      child: Container(
        width: 68,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? AppColors.gold : Colors.transparent, width: 2.5),
              ),
              child: ClipOval(
                child: imageUrl != null ? Image.network(imageUrl, fit: BoxFit.cover) : _letterAvatar(name),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _addChip() {
    return GestureDetector(
      onTap: onAddNew,
      child: Container(
        width: 68,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          children: [
            SizedBox(width: 52, height: 52, child: _addCircle()),
            const SizedBox(height: 4),
            const Text('Créer', style: TextStyle(fontSize: 11, color: AppColors.grey)),
          ],
        ),
      ),
    );
  }
}

/// Horizontal row of tappable category chips — fixed height no matter how
/// many categories exist. Previously this used a Wrap, which grew taller
/// and taller (eating the page) once there were more than a handful of
/// categories; scrolling sideways instead keeps it to one compact row,
/// matching the same pattern as TypeChipSelector.
class CategoryIconPicker extends StatelessWidget {
  final List<Category> categories;
  final int? selectedId;
  final ValueChanged<int?> onSelect;
  final VoidCallback? onAddNew;
  final bool allowClear;
  final String clearLabel;

  const CategoryIconPicker({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    this.onAddNew,
    this.allowClear = false,
    this.clearLabel = 'Toutes',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (allowClear) _chip(id: null, name: clearLabel, icon: Icons.apps, selected: selectedId == null),
          ...categories.map((c) => _chip(id: c.id, name: c.name, icon: iconForKey(c.iconKey), selected: selectedId == c.id)),
          if (onAddNew != null) _addChip(),
        ],
      ),
    );
  }

  Widget _chip({required int? id, required String name, required IconData icon, required bool selected}) {
    return GestureDetector(
      onTap: () => onSelect(id),
      child: Container(
        width: 66,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.black : AppColors.offWhite,
                border: Border.all(color: selected ? AppColors.gold : Colors.transparent, width: 2),
              ),
              child: Icon(icon, color: selected ? AppColors.gold : AppColors.black, size: 22),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: TextStyle(
                fontSize: 11,
                color: selected ? AppColors.gold : AppColors.black,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _addChip() {
    return GestureDetector(
      onTap: onAddNew,
      child: Container(
        width: 66,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          children: [
            SizedBox(width: 50, height: 50, child: _addCircle()),
            const SizedBox(height: 4),
            const Text('Créer', style: TextStyle(fontSize: 11, color: AppColors.grey)),
          ],
        ),
      ),
    );
  }
}
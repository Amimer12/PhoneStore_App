import 'package:flutter/material.dart';

/// A small, fixed set of icons categories can pick from. No upload, no
/// storage — the key is just a string saved in categories.icon_key and
/// mapped back to a Material icon on-device.
const Map<String, IconData> kCategoryIcons = {
  'perfume': Icons.local_florist_outlined,
  'electronics': Icons.devices_other_outlined,
  'phone': Icons.smartphone_outlined,
  'bag': Icons.shopping_bag_outlined,
  'tools': Icons.build_outlined,
  'category': Icons.category_outlined,
};

IconData iconForKey(String? key) => kCategoryIcons[key] ?? kCategoryIcons['category']!;

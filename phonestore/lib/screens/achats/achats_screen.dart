import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../../models/achat.dart';
import '../../models/category.dart';
import '../../models/product_type.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/category_icons.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/selector_chips.dart';
import 'achat_form.dart';

enum _AchatSort { dateDesc, dateAsc, priceDesc, priceAsc }

class AchatsScreen extends StatefulWidget {
  const AchatsScreen({super.key});

  @override
  State<AchatsScreen> createState() => _AchatsScreenState();
}

class _AchatsScreenState extends State<AchatsScreen> {
  final _service = SupabaseService.instance;
  List<Achat> _achats = [];
  List<Category> _categories = [];
  List<ProductType> _type1Options = [];
  bool _loading = true;

  // Filters
  DateTimeRange? _dateRange;
  double? _minPrice;
  double? _maxPrice;
  int? _categoryId;
  int? _type1Id;
  _AchatSort _sort = _AchatSort.dateDesc;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _achats = await _service.getAchats();
    _categories = await _service.getCategories();
    setState(() => _loading = false);
  }

  Future<void> _onCategoryChanged(int? id) async {
    setState(() {
      _categoryId = id;
      _type1Id = null;
      _type1Options = [];
    });
    if (id != null) {
      _type1Options = await _service.getTypes(categoryId: id, topLevelOnly: true, level: 1);
      if (mounted) setState(() {});
    }
  }

  bool get _hasActiveFilters =>
      _dateRange != null || _minPrice != null || _maxPrice != null || _categoryId != null || _type1Id != null;

  int get _activeFilterCount => [
        _dateRange != null,
        _minPrice != null || _maxPrice != null,
        _categoryId != null,
        _type1Id != null,
      ].where((e) => e).length;

  void _clearFilters() {
    setState(() {
      _dateRange = null;
      _minPrice = null;
      _maxPrice = null;
      _categoryId = null;
      _type1Id = null;
      _type1Options = [];
    });
  }

  List<Achat> get _filtered {
    var list = _achats.where((a) {
      if (_dateRange != null) {
        final d = DateTime(a.date.year, a.date.month, a.date.day);
        final from = DateTime(_dateRange!.start.year, _dateRange!.start.month, _dateRange!.start.day);
        final to = DateTime(_dateRange!.end.year, _dateRange!.end.month, _dateRange!.end.day);
        if (d.isBefore(from) || d.isAfter(to)) return false;
      }
      if (_minPrice != null && a.totalPrice < _minPrice!) return false;
      if (_maxPrice != null && a.totalPrice > _maxPrice!) return false;
      if (_categoryId != null) {
        final matches = a.items.any((it) => (it.product?.categoryId ?? it.categoryId) == _categoryId);
        if (!matches) return false;
      }
      if (_type1Id != null) {
        final matches = a.items.any((it) => it.product?.type1Id == _type1Id || it.typeIds.contains(_type1Id));
        if (!matches) return false;
      }
      return true;
    }).toList();

    switch (_sort) {
      case _AchatSort.dateDesc:
        list.sort((a, b) => b.date.compareTo(a.date));
        break;
      case _AchatSort.dateAsc:
        list.sort((a, b) => a.date.compareTo(b.date));
        break;
      case _AchatSort.priceDesc:
        list.sort((a, b) => b.totalPrice.compareTo(a.totalPrice));
        break;
      case _AchatSort.priceAsc:
        list.sort((a, b) => a.totalPrice.compareTo(b.totalPrice));
        break;
    }
    return list;
  }

  bool get _isDateGrouped => _sort == _AchatSort.dateDesc || _sort == _AchatSort.dateAsc;

  Future<void> _openForm({Achat? achat}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AchatForm(achat: achat)),
    );
    if (saved == true) _load();
  }

  Future<void> _confirmDelete(Achat a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer cet achat ?'),
        content: Text('${DateFormat('dd/MM/yyyy').format(a.date)} · ${a.totalPrice} DA'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && a.id != null) {
      await _service.deleteAchat(a.id!);
      _load();
    }
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AchatFilterSheet(
        categories: _categories,
        type1Options: _type1Options,
        categoryId: _categoryId,
        type1Id: _type1Id,
        dateRange: _dateRange,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
        onCategoryChanged: _onCategoryChanged,
        onType1Changed: (id) => setState(() => _type1Id = id),
        onDateRangeChanged: (r) => setState(() => _dateRange = r),
        onPriceChanged: (min, max) => setState(() {
          _minPrice = min;
          _maxPrice = max;
        }),
        onClear: _clearFilters,
      ),
    );
    setState(() {});
  }

  Future<void> _openSort() async {
    final chosen = await showModalBottomSheet<_AchatSort>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SortSheet(current: _sort),
    );
    if (chosen != null) setState(() => _sort = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final achats = _filtered;

    // Build a flat list of row descriptors: either a date-header or a card.
    final rows = <_Row>[];
    if (_isDateGrouped) {
      String? lastKey;
      for (final a in achats) {
        final key = DateFormat('yyyy-MM-dd').format(a.date);
        if (key != lastKey) {
          rows.add(_Row.header(a.date));
          lastKey = key;
        }
        rows.add(_Row.item(a));
      }
    } else {
      for (final a in achats) {
        rows.add(_Row.item(a));
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: const Padding(padding: EdgeInsets.all(10), child: AppLogo(size: 26)),
        title: const Text('Achats'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _activeFilterCount > 0,
              label: Text('$_activeFilterCount'),
              backgroundColor: AppColors.gold,
              textColor: AppColors.black,
              child: const Icon(Icons.tune),
            ),
            tooltip: 'Filtrer',
            onPressed: _openFilters,
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: 'Trier',
            onPressed: _openSort,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Nouvel achat'),
      ),
      body: Column(
        children: [
          if (_hasActiveFilters) _ActiveFiltersBar(count: _activeFilterCount, onClear: _clearFilters),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                : achats.isEmpty
                    ? Center(
                        child: Text(
                          _hasActiveFilters ? 'Aucun achat pour ces filtres' : 'Aucun achat',
                          style: const TextStyle(color: AppColors.grey),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.gold,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: rows.length,
                          itemBuilder: (_, i) {
                            final row = rows[i];
                            if (row.isHeader) {
                              return _DateHeader(date: row.date!, topPadded: i != 0);
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _AchatCard(
                                achat: row.achat!,
                                showDate: !_isDateGrouped,
                                onTap: () => _openForm(achat: row.achat!),
                                onDelete: () => _confirmDelete(row.achat!),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _Row {
  final DateTime? date;
  final Achat? achat;
  _Row.header(this.date) : achat = null;
  _Row.item(this.achat) : date = null;
  bool get isHeader => date != null;
}

/// A small grey date label, like the section headers in a phone call log:
/// "29 Jul 2026" in muted grey, with the achats for that day underneath.
class _DateHeader extends StatelessWidget {
  final DateTime date;
  final bool topPadded;
  const _DateHeader({required this.date, required this.topPadded});

  String _label() {
    final now = DateTime.now();
    final d = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (d == today) return "Aujourd'hui";
    if (d == yesterday) return 'Hier';
    return DateFormat('d MMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, topPadded ? 18 : 6, 4, 8),
      child: Text(
        _label(),
        style: const TextStyle(
          color: AppColors.grey,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Compact, sophisticated card: no big icon block, thin left accent, tight
/// spacing — reads as a single row in a list rather than a bulky tile.
class _AchatCard extends StatelessWidget {
  final Achat achat;
  final bool showDate;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _AchatCard({required this.achat, required this.showDate, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final itemCount = achat.items.length;
    final firstNames = achat.items
        .map((it) => it.isRepair ? it.label : it.product?.displayLabel)
        .where((e) => e != null && e.isNotEmpty)
        .take(2)
        .join(', ');

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onDelete,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEDEBE5), width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showDate)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          DateFormat('d MMM yyyy').format(achat.date),
                          style: const TextStyle(color: AppColors.grey, fontSize: 11.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                    Text(
                      firstNames.isNotEmpty ? firstNames : 'Achat',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$itemCount article${itemCount > 1 ? 's' : ''}',
                      style: const TextStyle(color: AppColors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('${achat.totalPrice} DA', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(width: 4),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onDelete,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveFiltersBar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  const _ActiveFiltersBar({required this.count, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Icon(Icons.filter_alt, size: 14, color: AppColors.gold),
          const SizedBox(width: 6),
          Text('$count filtre${count > 1 ? 's' : ''} actif${count > 1 ? 's' : ''}',
              style: const TextStyle(color: AppColors.grey, fontSize: 12.5, fontWeight: FontWeight.w500)),
          const Spacer(),
          GestureDetector(
            onTap: onClear,
            child: const Text('Réinitialiser',
                style: TextStyle(color: AppColors.gold, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _SortSheet extends StatelessWidget {
  final _AchatSort current;
  const _SortSheet({required this.current});

  @override
  Widget build(BuildContext context) {
    Widget tile(_AchatSort s, String label, IconData icon) {
      final selected = s == current;
      return ListTile(
        leading: Icon(icon, color: selected ? AppColors.gold : AppColors.grey),
        title: Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        trailing: selected ? const Icon(Icons.check, color: AppColors.gold) : null,
        onTap: () => Navigator.pop(context, s),
      );
    }

    return _SheetShell(
      title: 'Trier par',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tile(_AchatSort.dateDesc, 'Date (récent → ancien)', Icons.calendar_today_outlined),
          tile(_AchatSort.dateAsc, 'Date (ancien → récent)', Icons.calendar_today_outlined),
          tile(_AchatSort.priceDesc, 'Prix (élevé → bas)', Icons.trending_down),
          tile(_AchatSort.priceAsc, 'Prix (bas → élevé)', Icons.trending_up),
        ],
      ),
    );
  }
}

class _AchatFilterSheet extends StatefulWidget {
  final List<Category> categories;
  final List<ProductType> type1Options;
  final int? categoryId;
  final int? type1Id;
  final DateTimeRange? dateRange;
  final double? minPrice;
  final double? maxPrice;
  final ValueChanged<int?> onCategoryChanged;
  final ValueChanged<int?> onType1Changed;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final void Function(double? min, double? max) onPriceChanged;
  final VoidCallback onClear;

  const _AchatFilterSheet({
    required this.categories,
    required this.type1Options,
    required this.categoryId,
    required this.type1Id,
    required this.dateRange,
    required this.minPrice,
    required this.maxPrice,
    required this.onCategoryChanged,
    required this.onType1Changed,
    required this.onDateRangeChanged,
    required this.onPriceChanged,
    required this.onClear,
  });

  @override
  State<_AchatFilterSheet> createState() => _AchatFilterSheetState();
}

class _AchatFilterSheetState extends State<_AchatFilterSheet> {
  late final TextEditingController _minCtrl =
      TextEditingController(text: widget.minPrice?.toStringAsFixed(0) ?? '');
  late final TextEditingController _maxCtrl =
      TextEditingController(text: widget.maxPrice?.toStringAsFixed(0) ?? '');

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: widget.dateRange,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppColors.gold)),
        child: child!,
      ),
    );
    if (picked != null) widget.onDateRangeChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    return StatefulBuilder(
      builder: (context, setSheetState) => _SheetShell(
        title: 'Filtrer les achats',
        trailing: TextButton(
          onPressed: () {
            widget.onClear();
            _minCtrl.clear();
            _maxCtrl.clear();
            Navigator.pop(context);
          },
          child: const Text('Réinitialiser', style: TextStyle(color: AppColors.danger)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Période', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickDateRange,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range, size: 18, color: AppColors.grey),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.dateRange == null
                              ? 'Toutes les dates'
                              : '${df.format(widget.dateRange!.start)} → ${df.format(widget.dateRange!.end)}',
                          style: const TextStyle(fontSize: 13.5),
                        ),
                      ),
                      if (widget.dateRange != null)
                        GestureDetector(
                          onTap: () => setSheetState(() => widget.onDateRangeChanged(null)),
                          child: const Icon(Icons.close, size: 16, color: AppColors.grey),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Prix (DA)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Min', isDense: true),
                      onChanged: (v) => widget.onPriceChanged(double.tryParse(v), widget.maxPrice),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('—', style: TextStyle(color: AppColors.grey)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _maxCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Max', isDense: true),
                      onChanged: (v) => widget.onPriceChanged(widget.minPrice, double.tryParse(v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Catégorie', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              CategoryIconPicker(
                categories: widget.categories,
                selectedId: widget.categoryId,
                allowClear: true,
                onSelect: (id) {
                  widget.onCategoryChanged(id);
                  setSheetState(() {});
                },
              ),
              if (widget.categoryId != null) ...[
                const SizedBox(height: 16),
                TypeChipSelector(
                  label: 'Type',
                  items: widget.type1Options,
                  selectedId: widget.type1Id,
                  allowClear: true,
                  onSelect: widget.onType1Changed,
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Appliquer'),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared rounded-top bottom-sheet shell used by the filter and sort sheets.
class _SheetShell extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const _SheetShell({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(4)),
              ),
            ),
            Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}
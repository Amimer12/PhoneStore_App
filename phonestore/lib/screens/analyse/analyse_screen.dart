import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';

class AnalyseScreen extends StatefulWidget {
  const AnalyseScreen({super.key});

  @override
  State<AnalyseScreen> createState() => _AnalyseScreenState();
}

class _AnalyseScreenState extends State<AnalyseScreen> {
  final _service = SupabaseService.instance;

  Map<String, dynamic> _kpis = const {};
  List<Map<String, dynamic>> _hourly = [];
  List<Map<String, dynamic>> _daily = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _topRepairs = [];
  List<Map<String, dynamic>> _byCategory = [];

  bool _loading = true;
  bool _refreshingMatviews = false;
  bool _cumulative = false;
  TopProductsMetric _topMetric = TopProductsMetric.quantity;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([_loadKpisAndHourly(), _loadDaily(), _loadTopLists(), _loadCategory()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadKpisAndHourly() async {
    _kpis = await _service.getAnalyticsKpis();
    _hourly = await _service.getHourlyAchatsToday();
  }

  Future<void> _loadDaily() async {
    _daily = await _service.getDailyRevenue();
  }

  Future<void> _loadTopLists() async {
    _topProducts = await _service.getTopProducts(limit: 5, metric: _topMetric);
    _topRepairs = await _service.getTopRepairs(limit: 5, metric: _topMetric);
  }

  Future<void> _loadCategory() async {
    _byCategory = await _service.getRevenueByCategory();
  }

  /// Recomputes the matviews on the server, then re-pulls everything.
  /// This is the ONLY place matviews get refreshed — not on every write —
  /// so hitting this button is what makes top-products/category/history
  /// catch up with the latest sales.
  Future<void> _refresh() async {
    setState(() => _refreshingMatviews = true);
    try {
      await _service.refreshAnalytics();
    } finally {
      if (mounted) setState(() => _refreshingMatviews = false);
    }
    await _loadAll();
  }

  int _asInt(dynamic v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(padding: EdgeInsets.all(10), child: AppLogo(size: 26)),
        title: const Text('Analyse'),
        actions: [
          IconButton(
            icon: _refreshingMatviews
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: (_loading || _refreshingMatviews) ? null : _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : RefreshIndicator(
              onRefresh: _refresh,
              color: AppColors.gold,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  _buildKpiGrid(),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionTitle('Revenu par jour'),
                      _SegmentedToggle(
                        options: const ['Quotidien', 'Cumulé'],
                        selectedIndex: _cumulative ? 1 : 0,
                        onSelect: (i) => setState(() => _cumulative = i == 1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildRevenueChart(),
                  const SizedBox(height: 28),
                  _sectionTitle("Ventes par heure — aujourd'hui"),
                  const SizedBox(height: 12),
                  _buildHourlyChart(),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionTitle('Top produits'),
                      _SegmentedToggle(
                        options: const ['Qté vendue', "Chiffre d'affaires"],
                        selectedIndex: _topMetric == TopProductsMetric.quantity ? 0 : 1,
                        onSelect: (i) {
                          setState(() => _topMetric = i == 0 ? TopProductsMetric.quantity : TopProductsMetric.revenue);
                          _loadTopLists().then((_) => setState(() {}));
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTopList(_topProducts, isProduct: true),
                  if (_topRepairs.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionTitle('Top réparations & services'),
                    const SizedBox(height: 12),
                    _buildTopList(_topRepairs, isProduct: false),
                  ],
                  const SizedBox(height: 28),
                  _sectionTitle('Revenu par catégorie'),
                  const SizedBox(height: 12),
                  _buildCategoryPie(),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String t) => Text(
        t,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.black),
      );

  // ---------------- KPI GRID ----------------
  Widget _buildKpiGrid() {
    final achatsToday = _asInt(_kpis['achats_today_total']);
    final achatsTodayCount = _asInt(_kpis['achats_today_count']);
    final achatsMonth = _asInt(_kpis['achats_month_total']);
    final achatsMonthCount = _asInt(_kpis['achats_month_count']);
    final depensesMonth = _asInt(_kpis['depenses_month_total']);
    final netProfit = _asInt(_kpis['net_profit_month']);
    final growth = (_kpis['month_growth_pct'] as num?)?.toDouble();

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _kpiCard("Achats aujourd'hui", '$achatsToday DA')),
            const SizedBox(width: 12),
            Expanded(child: _kpiCard("Ventes aujourd'hui", '$achatsTodayCount')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _kpiCard('Achats ce mois', '$achatsMonth DA', trend: growth)),
            const SizedBox(width: 12),
            Expanded(child: _kpiCard('Ventes ce mois', '$achatsMonthCount')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _kpiCard('Dépenses ce mois', '$depensesMonth DA')),
            const SizedBox(width: 12),
            Expanded(child: _kpiCard('Bénéfice net (mois)', '$netProfit DA')),
          ],
        ),
      ],
    );
  }

  Widget _kpiCard(String label, String value, {double? trend}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.black, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.grey, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(value, style: const TextStyle(color: AppColors.gold, fontSize: 20, fontWeight: FontWeight.bold)),
              if (trend != null) ...[
                const SizedBox(width: 8),
                Icon(trend >= 0 ? Icons.trending_up : Icons.trending_down, size: 14, color: trend >= 0 ? Colors.greenAccent : AppColors.danger),
                Text('${trend.abs().toStringAsFixed(1)}%',
                    style: TextStyle(color: trend >= 0 ? Colors.greenAccent : AppColors.danger, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- DAILY REVENUE CHART ----------------
  Widget _buildRevenueChart() {
    if (_daily.isEmpty) {
      return const _EmptyChartBox(text: 'Pas encore de données de vente');
    }

    final spots = <FlSpot>[];
    double running = 0;
    double maxRevenue = 0;
    for (var i = 0; i < _daily.length; i++) {
      final raw = (_daily[i]['revenue'] as num?)?.toDouble() ?? 0;
      running += raw;
      final y = _cumulative ? running : raw;
      spots.add(FlSpot(i.toDouble(), y));
      if (y > maxRevenue) maxRevenue = y;
    }
    final topY = maxRevenue <= 0 ? 10.0 : maxRevenue * 1.15;

    String dayLabel(int index) {
      if (index < 0 || index >= _daily.length) return '';
      final raw = _daily[index]['achat_date'] as String?;
      if (raw == null) return '';
      final d = DateTime.tryParse(raw);
      if (d == null) return raw;
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    }

    final labelStep = (_daily.length / 5).ceil().clamp(1, _daily.length);

    return Container(
      height: 240,
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(18)),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: topY,
          minX: 0,
          maxX: (_daily.length - 1).toDouble().clamp(0, double.infinity),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (value, meta) => Text(
                  value >= 1000 ? '${(value / 1000).toStringAsFixed(0)}k' : value.toStringAsFixed(0),
                  style: const TextStyle(color: AppColors.grey, fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: labelStep.toDouble(),
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i % labelStep != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(dayLabel(i), style: const TextStyle(color: AppColors.grey, fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                final i = s.x.round();
                return LineTooltipItem(
                  '${dayLabel(i)}\n${s.y.toInt()} DA',
                  const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 12),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: !_cumulative,
              color: AppColors.gold,
              barWidth: 3,
              dotData: FlDotData(show: _daily.length <= 14),
              belowBarData: BarAreaData(show: true, color: AppColors.gold.withValues(alpha: 0.15)),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- HOURLY BAR CHART (today) ----------------
  Widget _buildHourlyChart() {
    final hasSales = _hourly.any((h) => _asInt(h['nb_achats']) > 0);
    if (!hasSales) {
      return const _EmptyChartBox(text: "Aucune vente aujourd'hui pour l'instant");
    }

    final maxCount = _hourly.map((h) => _asInt(h['nb_achats'])).fold<int>(0, (a, b) => a > b ? a : b);
    final topY = (maxCount <= 0 ? 1 : maxCount) * 1.3;

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(18)),
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: topY.toDouble(),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final row = _hourly[group.x.toInt()];
                final hour = _asInt(row['hour']);
                final count = _asInt(row['nb_achats']);
                final revenue = _asInt(row['revenue']);
                return BarTooltipItem(
                  '${hour.toString().padLeft(2, '0')}h\n$count vente${count == 1 ? '' : 's'}\n$revenue DA',
                  const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 12),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, meta) =>
                    value == value.roundToDouble() ? Text(value.toInt().toString(), style: const TextStyle(color: AppColors.grey, fontSize: 10)) : const SizedBox.shrink(),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 3,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i % 3 != 0 || i < 0 || i >= _hourly.length) return const SizedBox.shrink();
                  final hour = _asInt(_hourly[i]['hour']);
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${hour.toString().padLeft(2, '0')}h', style: const TextStyle(color: AppColors.grey, fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          barGroups: List.generate(_hourly.length, (i) {
            final count = _asInt(_hourly[i]['nb_achats']);
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: count.toDouble(),
                  color: AppColors.gold,
                  width: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  // ---------------- TOP PRODUCTS / TOP REPAIRS ----------------
  /// Builds the exact same primary/secondary label a product would show
  /// on its card in the Products list: "marque - taille" (falling back to
  /// the product's own name, then just the type1 name) on top, and
  /// "type1 - catégorie" underneath. This keeps a product with no `name`
  /// from ever showing as an opaque "Produit #12" here.
  (String primary, String secondary) _productLabel(Map<String, dynamic> row) {
    final name = row['name'] as String?;
    final marque = row['marque_name'] as String?;
    final type1 = row['type1_name'] as String?;
    final type2 = row['type2_name'] as String?;
    final category = row['category_name'] as String?;

    final primaryParts = [marque, type2].where((e) => e != null && e.isNotEmpty).toList();
    final primary = primaryParts.isNotEmpty
        ? primaryParts.join(' - ')
        : (name?.isNotEmpty == true ? name! : (type1 ?? ''));

    final secondaryParts = [type1, category].where((e) => e != null && e.isNotEmpty).toList();
    return (primary, secondaryParts.join(' - '));
  }

  Widget _buildTopList(List<Map<String, dynamic>> rows, {required bool isProduct}) {
    if (rows.isEmpty) {
      return _EmptyChartBox(text: isProduct ? 'Aucune vente enregistrée' : 'Aucune réparation enregistrée');
    }

    final valueKey = _topMetric == TopProductsMetric.quantity ? 'total_qty' : 'total_revenue';
    final maxValue = rows.map((p) => (p[valueKey] as num?)?.toDouble() ?? 0).fold<double>(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: rows.map((row) {
          final value = (row[valueKey] as num?)?.toDouble() ?? 0;
          final ratio = maxValue == 0 ? 0.0 : value / maxValue;

          String primary;
          String secondary;
          if (isProduct) {
            final label = _productLabel(row);
            primary = label.$1;
            secondary = label.$2;
          } else {
            primary = row['label'] as String? ?? 'Réparation';
            secondary = row['category_name'] as String? ?? '';
          }

          final valueText = _topMetric == TopProductsMetric.quantity ? '${value.toInt()} vendu(s)' : '${value.toInt()} DA';

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(primary.isNotEmpty ? primary : 'Sans nom', maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (secondary.isNotEmpty)
                            Text(secondary, style: const TextStyle(color: AppColors.grey, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Text(valueText, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: AppColors.offWhite,
                    valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---------------- CATEGORY PIE ----------------
  Widget _buildCategoryPie() {
    if (_byCategory.isEmpty) {
      return const _EmptyChartBox(text: 'Aucune donnée par catégorie');
    }
    final colors = [AppColors.gold, AppColors.black, AppColors.goldLight, AppColors.grey];
    final total = _byCategory.fold<double>(0, (s, c) => s + ((c['revenue'] as num?)?.toDouble() ?? 0));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          SizedBox(
            height: 160,
            width: 160,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 36,
                sections: List.generate(_byCategory.length, (i) {
                  final rev = (_byCategory[i]['revenue'] as num?)?.toDouble() ?? 0;
                  final pct = total == 0 ? 0 : (rev / total * 100);
                  return PieChartSectionData(
                    value: rev,
                    color: colors[i % colors.length],
                    title: '${pct.toStringAsFixed(0)}%',
                    radius: 40,
                    titleStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colors[i % colors.length] == AppColors.black ? AppColors.white : AppColors.black,
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(_byCategory.length, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_byCategory[i]['category'] as String? ?? '', overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pill-style segmented control, matching the app's gold/black
/// palette, used for the "daily vs cumulative" and "qty vs revenue" toggles.
class _SegmentedToggle extends StatelessWidget {
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _SegmentedToggle({required this.options, required this.selectedIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.offWhite, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(options.length, (i) {
          final selected = i == selectedIndex;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? AppColors.black : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                options[i],
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.gold : AppColors.grey,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _EmptyChartBox extends StatelessWidget {
  final String text;
  const _EmptyChartBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(18)),
      child: Text(text, style: const TextStyle(color: AppColors.grey)),
    );
  }
}

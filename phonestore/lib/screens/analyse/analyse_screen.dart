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
  List<Map<String, dynamic>> _daily = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _byCategory = [];
  List<Map<String, dynamic>> _dailyDepenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _daily = await _service.getDailyRevenue();
    _topProducts = await _service.getTopProducts(limit: 5);
    _byCategory = await _service.getRevenueByCategory();
    _dailyDepenses = await _service.getDailyDepenses();
    setState(() => _loading = false);
  }

  int get _totalRevenue => _daily.fold(0, (s, d) => s + ((d['revenue'] as num?)?.toInt() ?? 0));
  int get _totalAchats => _daily.fold(0, (s, d) => s + ((d['nb_achats'] as num?)?.toInt() ?? 0));
  int get _totalDepenses => _dailyDepenses.fold(0, (s, d) => s + ((d['total'] as num?)?.toInt() ?? 0));
  int get _netProfit => _totalRevenue - _totalDepenses;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(padding: EdgeInsets.all(10), child: AppLogo(size: 26)),
        title: const Text('Analyse'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.gold,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  _buildKpiRow(),
                  const SizedBox(height: 24),
                  _sectionTitle('Revenu par jour'),
                  const SizedBox(height: 12),
                  _buildRevenueChart(),
                  const SizedBox(height: 28),
                  _sectionTitle('Top produits'),
                  const SizedBox(height: 12),
                  _buildTopProductsChart(),
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

  Widget _buildKpiRow() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _kpiCard('Revenu total', '$_totalRevenue DA')),
            const SizedBox(width: 12),
            Expanded(child: _kpiCard('Achats', '$_totalAchats')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _kpiCard('Dépenses', '$_totalDepenses DA')),
            const SizedBox(width: 12),
            Expanded(child: _kpiCard('Bénéfice net', '$_netProfit DA')),
          ],
        ),
      ],
    );
  }

  Widget _kpiCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.black, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.grey, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: AppColors.gold, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRevenueChart() {
    if (_daily.isEmpty) {
      return const _EmptyChartBox(text: 'Pas encore de données de vente');
    }
    final spots = <FlSpot>[];
    double maxRevenue = 0;
    for (var i = 0; i < _daily.length; i++) {
      final revenue = (_daily[i]['revenue'] as num?)?.toDouble() ?? 0;
      spots.add(FlSpot(i.toDouble(), revenue));
      if (revenue > maxRevenue) maxRevenue = revenue;
    }
    // A little headroom above the highest point so the line doesn't touch the top edge.
    final topY = maxRevenue <= 0 ? 10.0 : maxRevenue * 1.15;

    String dayLabel(int index) {
      if (index < 0 || index >= _daily.length) return '';
      final raw = _daily[index]['achat_date'] as String?;
      if (raw == null) return '';
      final d = DateTime.tryParse(raw);
      if (d == null) return raw;
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    }

    // Thin out bottom labels so they don't overlap when there are many days.
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
              isCurved: true,
              color: AppColors.gold,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: AppColors.gold.withValues(alpha: 0.15)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProductsChart() {
    if (_topProducts.isEmpty) {
      return const _EmptyChartBox(text: 'Aucune vente enregistrée');
    }
    final maxRevenue = _topProducts
        .map((p) => (p['total_revenue'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: _topProducts.map((p) {
          final revenue = (p['total_revenue'] as num?)?.toDouble() ?? 0;
          final ratio = maxRevenue == 0 ? 0.0 : revenue / maxRevenue;
          final name = (p['name'] as String?)?.isNotEmpty == true ? p['name'] as String : 'Produit #${p['id']}';
          final reference = p['reference'] as String? ?? '';
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
                          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (reference.isNotEmpty)
                            Text(reference, style: const TextStyle(color: AppColors.grey, fontSize: 10.5)),
                        ],
                      ),
                    ),
                    Text('${revenue.toInt()} DA', style: const TextStyle(fontWeight: FontWeight.bold)),
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
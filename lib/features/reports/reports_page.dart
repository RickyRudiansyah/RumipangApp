import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/report.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'report_provider.dart';

/// Menu terlaris dan kurang laku, plus ringkasan laba kotor.
///
/// Angka laba memakai HPP **saat penjualan terjadi**, bukan HPP hari ini -
/// makanya laporan bulan lalu tidak berubah saat harga modal diperbarui.
class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    final async = ref.watch(menuSalesProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Laporan Penjualan',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              SegmentedButton<ReportRange>(
                segments: [
                  for (final r in ReportRange.values)
                    ButtonSegment(value: r, label: Text(r.label)),
                ],
                selected: {range},
                showSelectedIcon: false,
                onSelectionChanged: (s) =>
                    ref.read(reportRangeProvider.notifier).select(s.first),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorView(
              message: error.toString().replaceFirst('Exception: ', ''),
              onRetry: () => ref.invalidate(menuSalesProvider),
            ),
            data: (report) => report.items.isEmpty
                ? const EmptyState(
                    icon: Icons.bar_chart,
                    title: 'Belum ada penjualan',
                    subtitle: 'Laporan hanya menghitung order yang sudah lunas.',
                  )
                : _Body(report: report),
          ),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.report});

  final MenuSalesReport report;

  @override
  Widget build(BuildContext context) {
    final best = report.bestSellers.where((e) => e.qtySold > 0).take(8).toList();
    final worst = report.worstSellers.take(8).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            _Summary(
              label: 'Omzet',
              value: Fmt.rupiah(report.totalRevenue),
              icon: Icons.payments,
              color: AppTheme.queued,
            ),
            const SizedBox(width: 12),
            _Summary(
              label: 'Total HPP',
              value: Fmt.rupiah(report.totalCost),
              icon: Icons.shopping_basket,
              color: AppTheme.warn,
            ),
            const SizedBox(width: 12),
            _Summary(
              label: 'Laba kotor',
              value: Fmt.rupiah(report.totalProfit),
              icon: Icons.trending_up,
              color: report.totalProfit < 0 ? AppTheme.unpaid : AppTheme.paid,
            ),
            const SizedBox(width: 12),
            _Summary(
              label: 'Porsi terjual',
              value: '${report.totalQty}',
              icon: Icons.restaurant,
              color: Colors.black54,
            ),
          ],
        ),
        if (report.totalCost == 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: AppTheme.panel(
              background: AppTheme.warn.withValues(alpha: 0.10),
              outline: AppTheme.warn.withValues(alpha: 0.35),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: AppTheme.warn),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'HPP belum terisi, jadi laba kotor sama dengan omzet. '
                    'Isi HPP tiap menu di layar "Menu & HPP" supaya angka ini berarti.',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _RankCard(
                title: 'Paling laku',
                subtitle: 'Urut dari porsi terbanyak',
                icon: Icons.local_fire_department,
                color: AppTheme.paid,
                items: best,
                emptyText: 'Belum ada yang terjual.',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _RankCard(
                title: 'Kurang laku',
                subtitle: 'Termasuk yang belum pernah terjual',
                icon: Icons.trending_down,
                color: AppTheme.unpaid,
                items: worst,
                emptyText: 'Semua menu laku.',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.panel(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.items,
    required this.emptyText,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<MenuSalesStat> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.panel(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.black45)),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(emptyText, style: const TextStyle(color: Colors.black54)),
            )
          else
            for (final stat in items) _StatRow(stat: stat, accent: color),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.stat, required this.accent});

  final MenuSalesStat stat;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.menuItemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: stat.neverSold ? Colors.black45 : Colors.black87,
                  ),
                ),
                if (!stat.neverSold)
                  Text(
                    'omzet ${Fmt.rupiah(stat.revenue)}'
                    '${stat.cost > 0 ? ' · laba ${Fmt.rupiah(stat.grossProfit)}' : ''}',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (stat.neverSold)
            const StatusChip(label: 'belum pernah laku', color: Colors.grey)
          else
            Text(
              '${stat.qtySold} porsi',
              style: TextStyle(fontWeight: FontWeight.w800, color: accent),
            ),
        ],
      ),
    );
  }
}

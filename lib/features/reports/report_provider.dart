import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/report.dart';

/// Rentang laporan. Sengaja preset, bukan pemilih tanggal bebas - owner
/// hampir selalu ingin salah satu dari tiga ini, dan date picker di tablet
/// sambil melayani pembeli itu merepotkan.
enum ReportRange {
  today('Hari ini'),
  week('7 hari'),
  month('30 hari');

  const ReportRange(this.label);

  final String label;

  /// Batas bawah dan atas dalam waktu lokal (WIB).
  (DateTime, DateTime) bounds() {
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final startOfToday = DateTime(now.year, now.month, now.day);

    return switch (this) {
      ReportRange.today => (startOfToday, endOfToday),
      ReportRange.week => (startOfToday.subtract(const Duration(days: 6)), endOfToday),
      ReportRange.month => (startOfToday.subtract(const Duration(days: 29)), endOfToday),
    };
  }
}

class ReportRangeNotifier extends Notifier<ReportRange> {
  @override
  ReportRange build() => ReportRange.week;

  void select(ReportRange range) => state = range;
}

final reportRangeProvider =
    NotifierProvider<ReportRangeNotifier, ReportRange>(ReportRangeNotifier.new);

final menuSalesProvider = FutureProvider<MenuSalesReport>((ref) {
  final (from, to) = ref.watch(reportRangeProvider).bounds();
  return ref.watch(reportRepositoryProvider).menuSales(from: from, to: to);
});

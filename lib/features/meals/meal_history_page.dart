import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/staff_meal.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';

/// Berapa hari ke belakang yang sedang dilihat.
class MealHistoryDaysNotifier extends Notifier<int> {
  @override
  int build() => 30;

  void select(int days) => state = days;
}

final mealHistoryDaysProvider =
    NotifierProvider<MealHistoryDaysNotifier, int>(MealHistoryDaysNotifier.new);

/// Riwayat jatah makan seluruh karyawan.
///
/// Layar Jatah hanya menampilkan **hari ini** - cukup untuk melayani, tapi
/// tidak menjawab "Muis selama ini ambil apa saja". Itu pertanyaan pemilik, dan
/// jawabannya butuh rentang.
class MealHistoryNotifier extends AsyncNotifier<List<StaffMeal>> {
  @override
  Future<List<StaffMeal>> build() {
    final days = ref.watch(mealHistoryDaysProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return ref.read(staffMealRepositoryProvider).range(
          today.subtract(Duration(days: days - 1)),
          // `to` inklusif di endpoint (`meal_date <= to`), jadi hari ini ikut.
          today,
        );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => build());
  }
}

final mealHistoryProvider =
    AsyncNotifierProvider<MealHistoryNotifier, List<StaffMeal>>(MealHistoryNotifier.new);

/// Rekap per karyawan: berapa kali ambil, dan menu apa saja.
class MealTally {
  const MealTally({required this.name, required this.count, required this.menus});

  final String name;
  final int count;

  /// Menu -> berapa kali. Diurutkan dari yang paling sering.
  final List<MapEntry<String, int>> menus;
}

final mealTallyProvider = Provider<List<MealTally>>((ref) {
  final meals = ref.watch(mealHistoryProvider).value ?? const <StaffMeal>[];

  final byStaff = <String, List<StaffMeal>>{};
  for (final m in meals) {
    byStaff.putIfAbsent(m.staffName ?? 'Tanpa nama', () => []).add(m);
  }

  final result = byStaff.entries.map((e) {
    final counts = <String, int>{};
    for (final m in e.value) {
      counts[m.menuLabel] = (counts[m.menuLabel] ?? 0) + 1;
    }
    final menus = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return MealTally(name: e.key, count: e.value.length, menus: menus);
  }).toList()
    ..sort((a, b) => b.count.compareTo(a.count));

  return result;
});

/// Riwayat jatah makan — **khusus owner** (dibuka dari layar Jatah).
class MealHistoryPage extends ConsumerWidget {
  const MealHistoryPage({super.key});

  static const _options = {7: '7 Hari', 30: '30 Hari', 90: '90 Hari'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mealHistoryProvider);
    final tally = ref.watch(mealTallyProvider);
    final days = ref.watch(mealHistoryDaysProvider);
    final total = tally.fold<int>(0, (sum, t) => sum + t.count);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Jatah Makan'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () => ref.read(mealHistoryProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                for (final e in _options.entries) ...[
                  OptionChip(
                    label: e.value,
                    selected: days == e.key,
                    onTap: () =>
                        ref.read(mealHistoryDaysProvider.notifier).select(e.key),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                Text(
                  '$total porsi',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                message: e.toString().replaceFirst('Exception: ', ''),
                onRetry: () => ref.read(mealHistoryProvider.notifier).refresh(),
              ),
              data: (_) => tally.isEmpty
                  ? const EmptyState(
                      icon: Icons.lunch_dining,
                      title: 'Belum ada jatah makan tercatat',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: tally.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TallyCard(tally: tally[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TallyCard extends StatelessWidget {
  const _TallyCard({required this.tally});

  final MealTally tally;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.panel(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.brand.withValues(alpha: 0.12),
                child: Text(
                  tally.name.isEmpty ? '?' : tally.name[0].toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.brand,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tally.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              StatusChip(label: '${tally.count} porsi', color: AppTheme.brand),
            ],
          ),
          const SizedBox(height: 10),
          // Menu apa saja yang ia ambil, dari yang paling sering - itu
          // pertanyaan yang sebenarnya: "Muis ambil makanan apa?"
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in tally.menus)
                StatusChip(
                  label: m.value == 1 ? m.key : '${m.key} x${m.value}',
                  color: Colors.black54,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

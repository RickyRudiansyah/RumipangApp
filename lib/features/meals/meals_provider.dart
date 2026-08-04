import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/staff_meal.dart';

final staffListProvider = FutureProvider<List<StaffMember>>(
  (ref) => ref.watch(staffMealRepositoryProvider).staff(),
);

final todayMealsProvider = FutureProvider<List<StaffMeal>>(
  (ref) => ref.watch(staffMealRepositoryProvider).onDate(DateTime.now()),
);

/// `staff_id` yang jatahnya sudah diambil hari ini.
///
/// Ini hanya untuk menonaktifkan tombol lebih awal. Penegakan aturan
/// "1x sehari" yang sebenarnya ada di constraint unik database - dua tablet
/// bisa menekan tombol bersamaan dan pemeriksaan di sini akan lolos keduanya
/// (BACKEND-ADDITIONS.md §5).
final claimedTodayProvider = Provider<Set<String>>((ref) {
  final meals = ref.watch(todayMealsProvider).value ?? const <StaffMeal>[];
  return meals.map((e) => e.staffId).toSet();
});

/// Total biaya jatah makan hari ini, dari snapshot HPP tiap pencatatan.
final todayMealCostProvider = Provider<int>((ref) {
  final meals = ref.watch(todayMealsProvider).value ?? const <StaffMeal>[];
  return meals.fold(0, (sum, e) => sum + e.costSnapshot);
});

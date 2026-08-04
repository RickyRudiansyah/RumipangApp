import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/catalog.dart';
import '../../models/staff_meal.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../new_order/catalog_provider.dart';
import 'meals_provider.dart';

/// Jatah makan karyawan: satu kali per orang per hari.
class StaffMealsPage extends ConsumerWidget {
  const StaffMealsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(staffListProvider);
    final meals = ref.watch(todayMealsProvider);
    final claimed = ref.watch(claimedTodayProvider);
    final cost = ref.watch(todayMealCostProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Jatah Makan Karyawan',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Fmt.full(DateTime.now()).split(' ').take(4).join(' ')} · '
                      'satu kali per orang per hari',
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (cost > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: AppTheme.panel(
                    background: AppTheme.warn.withValues(alpha: 0.08),
                    outline: AppTheme.warn.withValues(alpha: 0.35),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Biaya hari ini',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                      Text(
                        Fmt.rupiah(cost),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.warn,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: staff.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorView(
              message: error.toString().replaceFirst('Exception: ', ''),
              onRetry: () => ref.invalidate(staffListProvider),
            ),
            data: (people) => people.isEmpty
                ? const EmptyState(
                    icon: Icons.badge,
                    title: 'Belum ada data karyawan',
                    subtitle: 'Endpoint /api/staff belum mengembalikan siapa pun.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 1.35,
                        children: [
                          for (final person in people)
                            _StaffCard(
                              person: person,
                              meal: _mealFor(meals.value, person.id),
                              claimed: claimed.contains(person.id),
                              onTake: () => _take(context, ref, person),
                              onUndo: () => _undo(context, ref, person, meals.value),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Catatan',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Biaya dihitung dari HPP menu saat dicatat, bukan HPP hari ini. '
                        'Kalau menu tidak dipilih, biaya tercatat Rp 0.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  static StaffMeal? _mealFor(List<StaffMeal>? meals, String staffId) {
    if (meals == null) return null;
    for (final m in meals) {
      if (m.staffId == staffId) return m;
    }
    return null;
  }

  Future<void> _take(BuildContext context, WidgetRef ref, StaffMember person) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _TakeMealDialog(person: person),
    );
    if (ok == true) ref.invalidate(todayMealsProvider);
  }

  Future<void> _undo(
    BuildContext context,
    WidgetRef ref,
    StaffMember person,
    List<StaffMeal>? meals,
  ) async {
    final meal = _mealFor(meals, person.id);
    if (meal == null) return;

    final confirmed = await confirmDialog(
      context,
      title: 'Batalkan jatah makan?',
      message: '${person.name} akan bisa mengambil jatahnya lagi hari ini.',
      confirmLabel: 'Batalkan',
      destructive: true,
    );
    if (!confirmed) return;

    try {
      await ref.read(staffMealRepositoryProvider).remove(meal.id);
      ref.invalidate(todayMealsProvider);
    } catch (error) {
      if (context.mounted) {
        showSnack(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          error: true,
        );
      }
    }
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.person,
    required this.meal,
    required this.claimed,
    required this.onTake,
    required this.onUndo,
  });

  final StaffMember person;
  final StaffMeal? meal;
  final bool claimed;
  final VoidCallback onTake;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.panel(
        outline: claimed ? AppTheme.paid.withValues(alpha: 0.45) : null,
        background: claimed ? AppTheme.paid.withValues(alpha: 0.05) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor:
                    claimed ? AppTheme.paid : Colors.black.withValues(alpha: 0.08),
                child: Icon(
                  claimed ? Icons.check : Icons.person,
                  size: 18,
                  color: claimed ? Colors.white : Colors.black54,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    Text(
                      person.role,
                      style: const TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          if (claimed) ...[
            Text(
              meal?.menuLabel ?? 'Sudah diambil',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            if ((meal?.costSnapshot ?? 0) > 0)
              Text(
                'HPP ${Fmt.rupiah(meal!.costSnapshot)}',
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onUndo,
                child: const Text('Batalkan'),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onTake,
                child: const Text('Ambil Jatah'),
              ),
            ),
        ],
      ),
    );
  }
}

class _TakeMealDialog extends ConsumerStatefulWidget {
  const _TakeMealDialog({required this.person});

  final StaffMember person;

  @override
  ConsumerState<_TakeMealDialog> createState() => _TakeMealDialogState();
}

class _TakeMealDialogState extends ConsumerState<_TakeMealDialog> {
  final _note = TextEditingController();
  MenuItemModel? _menu;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(menuProvider).value ?? const <MenuItemModel>[];

    return AlertDialog(
      title: Text('Jatah makan ${widget.person.name}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: menu.isEmpty ? null : () => _pickMenu(menu),
              icon: const Icon(Icons.restaurant_menu),
              label: Text(_menu?.name ?? 'Pilih menu (opsional)'),
            ),
            if (_menu != null) ...[
              const SizedBox(height: 8),
              Text(
                _menu!.hasCost
                    ? 'HPP tercatat ${Fmt.rupiah(_menu!.costPrice)}'
                    : 'Menu ini belum punya HPP - biaya tercatat Rp 0',
                style: TextStyle(
                  fontSize: 12,
                  color: _menu!.hasCost ? Colors.black54 : AppTheme.warn,
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppTheme.unpaid, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Catat'),
        ),
      ],
    );
  }

  /// Dialog daftar, bukan dropdown - alasan yang sama dengan pemilih meja di
  /// POS: lebih ramah sentuhan dan tidak terikat versi Flutter.
  Future<void> _pickMenu(List<MenuItemModel> menu) async {
    final picked = await showDialog<MenuItemModel>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pilih menu'),
        children: [
          SizedBox(
            width: 380,
            height: 420,
            child: ListView.builder(
              itemCount: menu.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(menu[i].name),
                subtitle: Text(
                  menu[i].hasCost ? 'HPP ${Fmt.rupiah(menu[i].costPrice)}' : 'HPP belum diisi',
                ),
                onTap: () => Navigator.pop(ctx, menu[i]),
              ),
            ),
          ),
        ],
      ),
    );
    if (picked != null) setState(() => _menu = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(staffMealRepositoryProvider).record(
            staffId: widget.person.id,
            menuItemId: _menu?.id,
            note: _note.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          // Pesan 409 dari server ("sudah mengambil jatah hari ini") tampil
          // apa adanya - itu sudah kalimat yang benar untuk kasir.
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }
}

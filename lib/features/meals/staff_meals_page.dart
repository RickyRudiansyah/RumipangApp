import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/catalog.dart';
import '../../models/staff_meal.dart';
import '../../shared/format.dart';
import '../../shared/layout.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../auth/staff_provider.dart';
import '../new_order/catalog_provider.dart';
import 'meal_history_page.dart';
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
              // Menambah karyawan mengubah siapa yang berhak jatah makan -
              // itu keputusan pemilik, bukan kasir.
              if (ref.watch(staffProvider).value?.isOwner ?? false) ...[
                // Layar ini hanya menampilkan hari ini. Pertanyaan "selama ini
                // Muis ambil apa saja" butuh rentang, dan itu urusan pemilik.
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const MealHistoryPage()),
                  ),
                  icon: const Icon(Icons.history, size: 18),
                  label: Text(context.isCompact ? 'Riwayat' : 'Riwayat Jatah'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _openStaffEditor(context, ref, null),
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: Text(context.isCompact ? 'Karyawan' : 'Tambah Karyawan'),
                ),
                const SizedBox(width: 10),
              ],
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
                        crossAxisCount: context.gridColumns(),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        // Satu kolom di HP jadi terlalu tinggi kalau rasionya
                        // tetap 1.35.
                        childAspectRatio: context.isCompact ? 2.4 : 1.35,
                        children: [
                          for (final person in people)
                            _StaffCard(
                              person: person,
                              meal: _mealFor(meals.value, person.id),
                              claimed: claimed.contains(person.id),
                              onTake: () => _take(context, ref, person),
                              onUndo: () => _undo(context, ref, person, meals.value),
                              onEdit: (ref.watch(staffProvider).value?.isOwner ?? false)
                                  ? () => _openStaffEditor(context, ref, person)
                                  : null,
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
                        'Setiap karyawan berhak satu menu per hari - bebas menu apa pun, '
                        'tanpa batas harga.',
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

  Future<void> _openStaffEditor(
    BuildContext context,
    WidgetRef ref,
    StaffMember? existing,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _StaffEditorDialog(existing: existing),
    );
    if (saved == true) ref.invalidate(staffListProvider);
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
    this.onEdit,
  });

  final StaffMember person;
  final StaffMeal? meal;
  final bool claimed;
  final VoidCallback onTake;
  final VoidCallback onUndo;

  /// Null untuk kasir - hanya owner yang boleh mengubah data karyawan.
  final VoidCallback? onEdit;

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
              if (onEdit != null)
                IconButton(
                  tooltip: 'Ubah karyawan',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 16),
                  visualDensity: VisualDensity.compact,
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

/// Tambah / ubah karyawan. Hanya dibuka owner.
class _StaffEditorDialog extends ConsumerStatefulWidget {
  const _StaffEditorDialog({this.existing});

  final StaffMember? existing;

  @override
  ConsumerState<_StaffEditorDialog> createState() => _StaffEditorDialogState();
}

class _StaffEditorDialogState extends ConsumerState<_StaffEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late String _role;

  bool _saving = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  /// Peran bawaan yang selalu ditawarkan. Owner boleh menambah sendiri lewat
  /// tombol "Peran baru", dan peran yang sudah dipakai karyawan lain ikut
  /// muncul otomatis - lihat [_roleOptions].
  ///
  /// Yang penting dipahami: **hanya `owner` yang punya arti keamanan.** Peran
  /// lain apa pun (cashier, koki, barista) mendapat akses staff yang sama.
  /// Menambah peran = menambah label, bukan tingkat akses baru.
  static const _baseRoles = ['cashier', 'owner'];

  /// Peran bawaan + peran yang sudah dipakai karyawan lain + peran yang baru
  /// diketik owner di sesi ini.
  List<String> _roleOptions(List<StaffMember> staff) {
    final all = <String>{..._baseRoles, ...staff.map((e) => e.role)};
    if (_role.isNotEmpty) all.add(_role);
    final list = all.where((e) => e.isNotEmpty).toList()..sort();
    return list;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _role = (e?.role.isNotEmpty ?? false) ? e!.role : 'cashier';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Tambah Karyawan' : 'Ubah Karyawan'),
      content: SizedBox(
        width: context.dialogWidth(420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nama karyawan'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email (opsional)',
                helperText: 'Hanya perlu kalau karyawan ini ikut memakai aplikasi',
              ),
            ),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Peran', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _roleOptions(
                  ref.watch(staffListProvider).value ?? const <StaffMember>[],
                ))
                  OptionChip(
                    label: _roleLabel(r),
                    selected: _role == r,
                    onTap: () => setState(() => _role = r),
                  ),
                OutlinedButton.icon(
                  onPressed: _addRole,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Peran baru'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (_role != 'owner') ...[
              const SizedBox(height: 8),
              const Text(
                'Semua peran selain Owner punya akses yang sama. Hanya Owner '
                'yang bisa melihat HPP dan mengelola karyawan.',
                style: TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Menambah karyawan di sini membuatnya bisa menerima jatah makan. '
              'Akun login dibuat terpisah di Supabase.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppTheme.unpaid, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        // Hanya untuk karyawan yang sudah ada. Ditaruh paling kiri, jauh dari
        // tombol Simpan.
        if (!_isNew)
          TextButton(
            onPressed: _saving ? null : _deactivate,
            style: TextButton.styleFrom(foregroundColor: AppTheme.unpaid),
            child: const Text('Keluarkan'),
          ),
        const Spacer(),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isNew ? 'Tambah' : 'Simpan'),
        ),
      ],
      actionsAlignment: MainAxisAlignment.spaceBetween,
    );
  }

  static String _roleLabel(String r) =>
      r.isEmpty ? r : r[0].toUpperCase() + r.substring(1);

  Future<void> _addRole() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Peran Baru'),
        content: SizedBox(
          width: ctx.dialogWidth(360),
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 30,
            decoration: const InputDecoration(
              labelText: 'Nama peran',
              hintText: 'mis. koki, barista, pramusaji',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Pakai'),
          ),
        ],
      ),
    );
    controller.dispose();

    final clean = (name ?? '').trim().toLowerCase();
    if (clean.isEmpty || !mounted) return;
    // Disaring sama dengan server, supaya penolakannya terjadi di sini -
    // bukan setelah owner menekan Simpan.
    if (!RegExp(r'^[a-z0-9 _-]+$').hasMatch(clean)) {
      showSnack(context, 'Peran hanya boleh huruf, angka, spasi, - dan _', error: true);
      return;
    }
    setState(() => _role = clean);
  }

  Future<void> _deactivate() async {
    final person = widget.existing!;
    final ok = await confirmDialog(
      context,
      title: 'Keluarkan ${person.name}?',
      message: 'Namanya hilang dari daftar karyawan dan dari jatah makan. '
          'Riwayat jatah makannya tetap tersimpan, jadi biaya bulan-bulan lalu '
          'tidak berubah.',
      confirmLabel: 'Keluarkan',
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(staffMealRepositoryProvider).deactivateStaff(person.id);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nama karyawan wajib diisi');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(staffMealRepositoryProvider);
    try {
      if (_isNew) {
        await repo.createStaff(
          name: name,
          role: _role,
          email: _email.text.trim(),
        );
      } else {
        await repo.updateStaff(
          widget.existing!.id,
          name: name,
          role: _role,
          email: _email.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }
}

/// Pemilih menu jatah makan.
///
/// Karyawan bebas memilih menu apa pun, jadi daftarnya sepanjang seluruh menu
/// warung - tanpa kolom cari, mencarinya lebih lama daripada memasaknya.
/// HPP sengaja tidak ditampilkan di sini: itu angka untuk pemilik, dan
/// menuliskan "HPP belum diisi" di sebelah menu membuatnya terlihat seperti
/// menu yang bermasalah dan tidak boleh dipilih.
class _MealMenuPicker extends StatefulWidget {
  const _MealMenuPicker({required this.menu});

  final List<MenuItemModel> menu;

  @override
  State<_MealMenuPicker> createState() => _MealMenuPickerState();
}

class _MealMenuPickerState extends State<_MealMenuPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final items = query.isEmpty
        ? widget.menu
        : widget.menu
            .where((m) => m.name.toLowerCase().contains(query))
            .toList();

    return AlertDialog(
      title: const Text('Pilih menu'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: context.dialogWidth(420),
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Cari menu',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off,
                      title: 'Menu tidak ditemukan',
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(items[i].name),
                        subtitle: Text(items[i].categoryName),
                        onTap: () => Navigator.pop(context, items[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
      ],
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
        width: context.dialogWidth(420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Satu menu per hari - bebas pilih yang mana pun.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: menu.isEmpty ? null : () => _pickMenu(menu),
              icon: const Icon(Icons.restaurant_menu),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _menu?.name ?? 'Pilih menu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
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
          // Jatahnya satu menu, jadi menunya wajib dipilih - mencatat jatah
          // tanpa menu menghabiskan kuota harian karyawan tanpa menyebut apa
          // yang ia ambil.
          onPressed: _saving || _menu == null ? null : _save,
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
      builder: (_) => _MealMenuPicker(menu: menu),
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

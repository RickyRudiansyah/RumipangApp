import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../models/catalog.dart';
import '../../shared/format.dart';
import '../../shared/layout.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../auth/staff_provider.dart';
import '../new_order/catalog_provider.dart';

/// Menu & HPP: tambah menu, ubah harga, isi HPP, lihat margin.
///
/// HPP diisi manual per menu (bukan dari resep bahan baku) - keputusan pemilik,
/// lihat BACKEND-ADDITIONS.md §1.
class MenuAdminPage extends ConsumerWidget {
  const MenuAdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(menuProvider);

    return Column(
      children: [
        _Header(
          onAdd: () => _openEditor(context, ref, null),
          onAddCategory: () => _openCategoryEditor(context, ref),
        ),
        const Divider(height: 1),
        Expanded(
          child: menu.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorView(
              message: _readable(error),
              onRetry: () => ref.invalidate(menuProvider),
            ),
            data: (items) => items.isEmpty
                ? const EmptyState(
                    icon: Icons.restaurant_menu,
                    title: 'Belum ada menu',
                    subtitle: 'Tekan "Tambah Menu" untuk mulai mengisi katalog.',
                  )
                : _MenuTable(
                    items: items,
                    groups: ref.watch(menuByCategoryProvider),
                    onEdit: (item) => _openEditor(context, ref, item),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    MenuItemModel? existing,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _MenuEditorDialog(existing: existing),
    );
    if (saved == true) ref.invalidate(menuProvider);
  }

  Future<void> _openCategoryEditor(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _CategoryEditorDialog(),
    );
    if (saved == true) {
      // Menu ikut dimuat ulang: kategori baru harus langsung bisa dipilih,
      // dan nama kategori menempel di objek menu dari server.
      ref.invalidate(menuCategoriesProvider);
      ref.invalidate(menuProvider);
    }
  }

  static String _readable(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}

class _Header extends ConsumerWidget {
  const _Header({required this.onAdd, required this.onAddCategory});

  final VoidCallback onAdd;
  final VoidCallback onAddCategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = context.isCompact;
    final showCost = ref.watch(canSeeCostProvider);

    // Judul pun tidak menyebut HPP untuk kasir - percuma menyembunyikan
    // kolomnya kalau namanya masih terpampang di kepala layar.
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          showCost ? 'Menu & HPP' : 'Menu',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          compact || !showCost
              ? 'Dikelompokkan per kategori.'
              : 'Dikelompokkan per kategori. HPP diisi manual, margin dihitung otomatis.',
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ),
      ],
    );

    final buttons = [
      OutlinedButton.icon(
        onPressed: onAddCategory,
        icon: const Icon(Icons.new_label_outlined),
        label: Text(compact ? 'Kategori' : 'Tambah Kategori'),
      ),
      FilledButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: Text(compact ? 'Menu' : 'Tambah Menu'),
      ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 14 : 20, 16, compact ? 14 : 20, 12),
      child: compact
          // Di HP tombol turun ke baris sendiri - memaksanya sebaris dengan
          // judul membuat keduanya terpotong.
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: buttons[0]),
                    const SizedBox(width: 10),
                    Expanded(child: buttons[1]),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: title),
                buttons[0],
                const SizedBox(width: 10),
                buttons[1],
              ],
            ),
    );
  }
}

class _MenuTable extends ConsumerWidget {
  const _MenuTable({
    required this.items,
    required this.groups,
    required this.onEdit,
  });

  final List<MenuItemModel> items;

  /// Sudah dikelompokkan dan diurutkan mengikuti `sort_order` kategori.
  final List<MapEntry<String, List<MenuItemModel>>> groups;

  final void Function(MenuItemModel) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Peringatan "HPP belum diisi" ikut disembunyikan dari kasir - itu tugas
    // owner, dan menyebutnya membocorkan bahwa ada angka modal di balik layar.
    final showCost = ref.watch(canSeeCostProvider);
    final withoutCost = items.where((e) => !e.hasCost).length;

    return Column(
      children: [
        if (showCost && withoutCost > 0)
          Material(
            color: AppTheme.warn.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: AppTheme.warn),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$withoutCost menu belum diisi HPP-nya. Laporan laba untuk '
                      'menu itu tidak akan akurat.',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Kepala tabel hanya berguna kalau kolomnya memang sejajar.
        if (!context.isCompact) ...[
          const _TableHead(),
          const Divider(height: 1),
        ],
        Expanded(
          child: ListView.builder(
            itemCount: groups.length,
            itemBuilder: (_, i) => _CategorySection(
              title: groups[i].key,
              items: groups[i].value,
              onEdit: onEdit,
            ),
          ),
        ),
      ],
    );
  }
}

/// Satu kategori beserta menunya. Judulnya menempel di atas saat digulir
/// supaya owner tidak kehilangan konteks di katalog yang panjang.
class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.title,
    required this.items,
    required this.onEdit,
  });

  final String title;
  final List<MenuItemModel> items;
  final void Function(MenuItemModel) onEdit;

  @override
  Widget build(BuildContext context) {
    final total = items.fold(0, (sum, e) => sum + e.price);
    final avg = items.isEmpty ? 0 : total ~/ items.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Colors.black.withValues(alpha: 0.035),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.label_outline, size: 15, color: Colors.black.withValues(alpha: 0.5)),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${items.length} menu · rata-rata ${Fmt.rupiah(avg)}',
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        for (final item in items) ...[
          _MenuRow(item: item, onEdit: onEdit),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

class _TableHead extends ConsumerWidget {
  const _TableHead();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showCost = ref.watch(canSeeCostProvider);
    const style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: Colors.black54,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          const SizedBox(width: 56),
          Expanded(flex: 4, child: Text('MENU', style: style)),
          Expanded(flex: 2, child: Text('HARGA JUAL', style: style, textAlign: TextAlign.right)),
          // HPP & margin hanya untuk owner (auth/staff_provider.dart).
          if (showCost) ...[
            Expanded(flex: 2, child: Text('HPP', style: style, textAlign: TextAlign.right)),
            Expanded(flex: 2, child: Text('MARGIN', style: style, textAlign: TextAlign.right)),
          ],
          SizedBox(width: 90, child: Text('STATUS', style: style, textAlign: TextAlign.center)),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _MenuRow extends ConsumerWidget {
  const _MenuRow({required this.item, required this.onEdit});

  final MenuItemModel item;
  final void Function(MenuItemModel) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final percent = item.marginPercent;
    // HPP & margin hanya untuk owner (auth/staff_provider.dart).
    final showCost = ref.watch(canSeeCostProvider);

    if (context.isCompact) return _compact(context, percent, showCost);

    return InkWell(
      onTap: () => onEdit(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              clipBehavior: Clip.antiAlias,
              decoration: AppTheme.panel(
                background: Colors.black.withValues(alpha: 0.03),
              ),
              child: item.imageUrl == null
                  ? const Icon(Icons.image_outlined, size: 18, color: Colors.black26)
                  : Image.network(
                      item.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        size: 18,
                        color: Colors.black26,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  Text(
                    item.categoryName,
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                Fmt.rupiah(item.price),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (showCost) ...[
            Expanded(
              flex: 2,
              child: Text(
                item.hasCost ? Fmt.rupiah(item.costPrice) : 'belum diisi',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: item.hasCost ? Colors.black87 : AppTheme.warn,
                  fontStyle: item.hasCost ? FontStyle.normal : FontStyle.italic,
                  fontSize: item.hasCost ? 14 : 12,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    item.hasCost ? Fmt.rupiah(item.margin) : '-',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: item.isLossMaking ? AppTheme.unpaid : AppTheme.paid,
                    ),
                  ),
                  if (percent != null)
                    Text(
                      '${percent.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11,
                        color: item.isLossMaking ? AppTheme.unpaid : Colors.black45,
                      ),
                    ),
                ],
              ),
            ),
            ],
            SizedBox(
              width: 90,
              child: Center(child: _statusChip()),
            ),
            const SizedBox(
              width: 48,
              child: Icon(Icons.edit, size: 18, color: Colors.black38),
            ),
          ],
        ),
      ),
    );
  }

  /// Versi HP: dua baris, bukan enam kolom. Harga dan margin tetap terlihat
  /// karena itu yang dicari owner; sisanya turun ke baris kedua.
  Widget _compact(BuildContext context, double? percent, bool showCost) {
    return InkWell(
      onTap: () => onEdit(item),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              clipBehavior: Clip.antiAlias,
              decoration: AppTheme.panel(
                background: Colors.black.withValues(alpha: 0.03),
              ),
              child: item.imageUrl == null
                  ? const Icon(Icons.image_outlined, size: 20, color: Colors.black26)
                  : Image.network(
                      item.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        size: 20,
                        color: Colors.black26,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        Fmt.rupiah(item.price),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _statusChip(),
                      // HPP & margin hanya untuk owner.
                      if (showCost) ...[
                        if (item.hasCost)
                          StatusChip(
                            label: 'HPP ${Fmt.rupiah(item.costPrice)}',
                            color: Colors.black54,
                          )
                        else
                          const StatusChip(
                            label: 'HPP belum diisi',
                            color: AppTheme.warn,
                          ),
                        if (item.hasCost)
                          StatusChip(
                            label: percent == null
                                ? Fmt.rupiah(item.margin)
                                : '${Fmt.rupiah(item.margin)} · ${percent.toStringAsFixed(0)}%',
                            color: item.isLossMaking ? AppTheme.unpaid : AppTheme.paid,
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 20, color: Colors.black26),
          ],
        ),
      ),
    );
  }

  Widget _statusChip() {
    if (!item.isAvailable) {
      return const StatusChip(label: 'Nonaktif', color: Colors.grey);
    }
    if (item.isSoldOut) {
      return const StatusChip(label: 'Habis', color: AppTheme.warn);
    }
    return const StatusChip(label: 'Dijual', color: AppTheme.paid);
  }
}

// ---------------------------------------------------- topping & variasi ----

/// Daftar topping/variasi satu menu, dikelompokkan per jenis.
///
/// Hanya muncul untuk menu yang sudah tersimpan — variasi butuh
/// `menu_item_id`, dan menu baru belum punya ID sampai disimpan.
class _VariationsSection extends ConsumerWidget {
  const _VariationsSection({required this.menuItemId});

  final String menuItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(menuVariationsProvider);
    final all = async.value ?? const <MenuVariation>[];
    final mine = all.where((v) => v.menuItemId == menuItemId).toList();

    // Dikelompokkan per jenis, urutannya mengikuti kemunculan pertama.
    final groups = <String, List<MenuVariation>>{};
    for (final v in mine) {
      groups.putIfAbsent(v.variationType, () => []).add(v);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Topping & Variasi',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: () => _openEditor(context, ref, null, groups.keys.toList()),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Tambah'),
            ),
          ],
        ),
        if (async.isLoading && all.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'Belum ada. Tambahkan mis. "Extra Topping" → Keju +Rp 5.000.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          )
        else
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                entry.key.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: Colors.black45,
                ),
              ),
            ),
            for (final v in entry.value)
              _VariationRow(
                variation: v,
                onEdit: () => _openEditor(context, ref, v, groups.keys.toList()),
                onDelete: () => _delete(context, ref, v),
              ),
          ],
      ],
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    MenuVariation? existing,
    List<String> knownTypes,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _VariationEditorDialog(
        menuItemId: menuItemId,
        existing: existing,
        knownTypes: knownTypes,
      ),
    );
    if (saved == true) ref.invalidate(menuVariationsProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, MenuVariation v) async {
    final ok = await confirmDialog(
      context,
      title: 'Hapus "${v.label}"?',
      message: 'Opsi ini tidak akan muncul lagi saat membuat order.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok) return;

    try {
      await ref.read(menuAdminRepositoryProvider).deleteVariation(v.id);
      ref.invalidate(menuVariationsProvider);
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

class _VariationRow extends StatelessWidget {
  const _VariationRow({
    required this.variation,
    required this.onEdit,
    required this.onDelete,
  });

  final MenuVariation variation;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.circle, size: 7, color: Colors.black38),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                variation.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              variation.extraPrice == 0
                  ? 'gratis'
                  : '+${Fmt.rupiah(variation.extraPrice)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: variation.extraPrice == 0 ? Colors.black45 : AppTheme.warn,
              ),
            ),
            IconButton(
              tooltip: 'Hapus',
              onPressed: onDelete,
              icon: const Icon(Icons.close, size: 16),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _VariationEditorDialog extends ConsumerStatefulWidget {
  const _VariationEditorDialog({
    required this.menuItemId,
    required this.existing,
    required this.knownTypes,
  });

  final String menuItemId;
  final MenuVariation? existing;

  /// Jenis yang sudah dipakai menu ini, ditawarkan sebagai pintasan supaya
  /// tidak lahir "Extra Topping" dan "extra topping" yang terpisah.
  final List<String> knownTypes;

  @override
  ConsumerState<_VariationEditorDialog> createState() =>
      _VariationEditorDialogState();
}

class _VariationEditorDialogState extends ConsumerState<_VariationEditorDialog> {
  late final TextEditingController _type;
  late final TextEditingController _label;
  late final TextEditingController _price;

  bool _saving = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = TextEditingController(text: e?.variationType ?? '');
    _label = TextEditingController(text: e?.label ?? '');
    _price = TextEditingController(
      text: e == null || e.extraPrice == 0 ? '' : e.extraPrice.toString(),
    );
  }

  @override
  void dispose() {
    _type.dispose();
    _label.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Tambah Opsi' : 'Ubah Opsi'),
      content: SizedBox(
        width: context.dialogWidth(420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _type,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Jenis / grup',
                hintText: 'mis. Extra Topping, Ukuran, Level Pedas',
              ),
            ),
            if (widget.knownTypes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in widget.knownTypes)
                    ActionChip(
                      label: Text(t, style: const TextStyle(fontSize: 12)),
                      onPressed: () => setState(() => _type.text = t),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _label,
              autofocus: _isNew,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama opsi',
                hintText: 'mis. Keju, Telur Ceplok, Large',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Tambahan harga',
                prefixText: '+Rp ',
                helperText: 'kosongkan kalau tidak menambah harga',
              ),
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
              : Text(_isNew ? 'Tambah' : 'Simpan'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final type = _type.text.trim();
    final label = _label.text.trim();
    if (type.isEmpty) {
      setState(() => _error = 'Jenis wajib diisi');
      return;
    }
    if (label.isEmpty) {
      setState(() => _error = 'Nama opsi wajib diisi');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(menuAdminRepositoryProvider);
    final price = int.tryParse(_price.text.trim()) ?? 0;

    try {
      if (_isNew) {
        await repo.createVariation(
          menuItemId: widget.menuItemId,
          variationType: type,
          label: label,
          extraPrice: price,
        );
      } else {
        await repo.updateVariation(
          widget.existing!.id,
          menuItemId: widget.menuItemId,
          variationType: type,
          label: label,
          extraPrice: price,
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

// ------------------------------------------------------------ kategori ----

class _CategoryEditorDialog extends ConsumerStatefulWidget {
  const _CategoryEditorDialog();

  @override
  ConsumerState<_CategoryEditorDialog> createState() =>
      _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends ConsumerState<_CategoryEditorDialog> {
  final _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = ref.watch(menuCategoriesProvider).value ?? const <MenuCategory>[];

    return AlertDialog(
      title: const Text('Tambah Kategori'),
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
              decoration: const InputDecoration(
                labelText: 'Nama kategori',
                hintText: 'mis. Minuman, Nasi, Camilan',
              ),
              onSubmitted: (_) => _save(existing),
            ),
            if (existing.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Kategori yang sudah ada',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in existing)
                    StatusChip(label: c.name, color: Colors.black54),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
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
          onPressed: _saving ? null : () => _save(existing),
          child: _saving
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Tambah'),
        ),
      ],
    );
  }

  Future<void> _save(List<MenuCategory> existing) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nama kategori wajib diisi');
      return;
    }
    if (existing.any((c) => c.name.toLowerCase() == name.toLowerCase())) {
      setState(() => _error = 'Kategori "$name" sudah ada');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    // Kategori baru ditaruh di urutan paling belakang. Owner bisa mengatur
    // ulang urutannya dari web; aplikasi sengaja tidak menyediakan itu karena
    // drag-and-drop di tablet sambil melayani pembeli lebih menyusahkan
    // daripada membantu.
    final nextSort = existing.isEmpty
        ? 1
        : existing.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

    try {
      await ref.read(menuAdminRepositoryProvider).createCategory(
            name: name,
            sortOrder: nextSort,
          );
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

// ---------------------------------------------------------------- foto ----

/// Pratinjau + tombol ambil/hapus foto menu.
class _PhotoField extends StatelessWidget {
  const _PhotoField({
    required this.imageUrl,
    required this.busy,
    required this.onPick,
    required this.onClear,
  });

  final String? imageUrl;
  final bool busy;
  final void Function(ImageSource) onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 132,
          height: 132,
          clipBehavior: Clip.antiAlias,
          decoration: AppTheme.panel(background: Colors.black.withValues(alpha: 0.03)),
          child: busy
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : (imageUrl == null
                  ? const Center(
                      child: Icon(Icons.image_outlined, size: 34, color: Colors.black26),
                    )
                  : Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      // Foto lama bisa saja sudah terhapus dari Storage;
                      // jangan sampai seluruh dialog ikut gagal render.
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_outlined,
                            size: 30, color: Colors.black26),
                      ),
                      loadingBuilder: (context, child, progress) => progress == null
                          ? child
                          : const Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                    )),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Foto menu',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              const Text(
                'Bisa dipotong dan diputar sebelum diunggah.',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => onPick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library, size: 18),
                    label: Text(imageUrl == null ? 'Pilih Foto' : 'Ganti Foto'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => onPick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera, size: 18),
                    label: const Text('Kamera'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  ),
                  if (imageUrl != null)
                    TextButton.icon(
                      onPressed: busy ? null : onClear,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Hapus'),
                      style: TextButton.styleFrom(foregroundColor: AppTheme.unpaid),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pemilih kategori. Dialog daftar, bukan dropdown - alasan yang sama dengan
/// pemilih meja di POS.
class _CategoryField extends ConsumerWidget {
  const _CategoryField({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(menuCategoriesProvider);
    final categories = async.value ?? const <MenuCategory>[];
    final matches = categories.where((c) => c.id == value);
    final selected = matches.isEmpty ? null : matches.first;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Kategori',
        // Kategori gagal dimuat bukan alasan membatalkan penyuntingan harga.
        errorText: async.hasError ? 'Daftar kategori gagal dimuat' : null,
      ),
      child: InkWell(
        onTap: categories.isEmpty ? null : () => _pick(context, categories),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected?.name ?? (value == null ? 'Tanpa kategori' : 'Kategori lain'),
                style: TextStyle(
                  color: selected == null ? Colors.black54 : Colors.black87,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.black45),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, List<MenuCategory> categories) async {
    final picked = await showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pilih kategori'),
        children: [
          SizedBox(
            width: context.dialogWidth(360),
            height: 360,
            child: ListView(
              children: [
                ListTile(
                  title: const Text('Tanpa kategori'),
                  onTap: () => Navigator.pop(ctx, null),
                ),
                const Divider(height: 1),
                for (final c in categories)
                  ListTile(
                    title: Text(c.name),
                    selected: c.id == value,
                    onTap: () => Navigator.pop(ctx, c.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    // `null` sah sebagai pilihan ("tanpa kategori"), jadi dibedakan dari
    // dialog yang ditutup tanpa memilih lewat `context.mounted`.
    if (context.mounted) onChanged(picked);
  }
}

// --------------------------------------------------------------- editor ----

class _MenuEditorDialog extends ConsumerStatefulWidget {
  const _MenuEditorDialog({this.existing});

  final MenuItemModel? existing;

  @override
  ConsumerState<_MenuEditorDialog> createState() => _MenuEditorDialogState();
}

class _MenuEditorDialogState extends ConsumerState<_MenuEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final TextEditingController _description;

  late bool _available;
  late bool _soldOut;
  late String? _categoryId;

  /// URL foto yang akan disimpan. Diisi dari menu yang disunting, lalu diganti
  /// kalau owner mengunggah foto baru.
  late String? _imageUrl;

  bool _saving = false;
  bool _uploading = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _price = TextEditingController(text: e == null ? '' : e.price.toString());
    _cost = TextEditingController(
      text: e == null || e.costPrice == 0 ? '' : e.costPrice.toString(),
    );
    _description = TextEditingController(text: e?.description ?? '');
    _available = e?.isAvailable ?? true;
    _soldOut = e?.isSoldOut ?? false;
    _categoryId = e?.categoryId;
    _imageUrl = e?.imageUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _cost.dispose();
    _description.dispose();
    super.dispose();
  }

  int get _priceValue => int.tryParse(_price.text.trim()) ?? 0;
  int get _costValue => int.tryParse(_cost.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final margin = _priceValue - _costValue;
    final showMargin = _costValue > 0 && _priceValue > 0;
    final showCost = ref.watch(canSeeCostProvider);

    return AlertDialog(
      title: Text(_isNew ? 'Tambah Menu' : 'Ubah Menu'),
      content: SizedBox(
        width: context.dialogWidth(480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PhotoField(
                imageUrl: _imageUrl,
                busy: _uploading,
                onPick: _pickPhoto,
                onClear: () => setState(() => _imageUrl = null),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: _isNew,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nama menu'),
              ),
              const SizedBox(height: 14),
              _CategoryField(
                value: _categoryId,
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _price,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Harga jual',
                        prefixText: 'Rp ',
                      ),
                    ),
                  ),
                  // Kolom modal hanya untuk owner. Nilainya tetap dikirim apa
                  // adanya saat kasir menyimpan (controller-nya diisi dari data
                  // yang ada), jadi HPP yang sudah diisi owner tidak terhapus
                  // hanya karena menu disunting kasir.
                  if (showCost) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _cost,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'HPP (modal)',
                          prefixText: 'Rp ',
                          helperText: 'boleh dikosongkan',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              if (showCost && showMargin)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: AppTheme.panel(
                    background: (margin < 0 ? AppTheme.unpaid : AppTheme.paid)
                        .withValues(alpha: 0.08),
                    outline: (margin < 0 ? AppTheme.unpaid : AppTheme.paid)
                        .withValues(alpha: 0.35),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        margin < 0 ? Icons.trending_down : Icons.trending_up,
                        size: 18,
                        color: margin < 0 ? AppTheme.unpaid : AppTheme.paid,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          margin < 0
                              ? 'Rugi ${Fmt.rupiah(-margin)} per porsi'
                              : 'Untung ${Fmt.rupiah(margin)} per porsi '
                                  '(${(margin / _priceValue * 100).toStringAsFixed(0)}%)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: margin < 0 ? AppTheme.unpaid : AppTheme.paid,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Keterangan (opsional)',
                ),
              ),
              if (_isNew)
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Text(
                    'Topping & variasi bisa ditambahkan setelah menu ini '
                    'disimpan.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              if (!_isNew) ...[
                const Divider(height: 28),
                _VariationsSection(menuItemId: widget.existing!.id),
                const Divider(height: 28),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _available,
                  onChanged: (v) => setState(() => _available = v),
                  title: const Text('Dijual'),
                  subtitle: const Text('Matikan untuk menyembunyikan dari kasir'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _soldOut,
                  onChanged: (v) => setState(() => _soldOut = v),
                  title: const Text('Habis hari ini'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.unpaid, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          // Jangan biarkan disimpan sementara foto masih diunggah - URL-nya
          // belum ada, dan hasilnya menu tersimpan tanpa foto.
          onPressed: (_saving || _uploading) ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isNew ? 'Tambah' : 'Simpan'),
        ),
      ],
    );
  }

  /// Ambil foto → potong/putar → unggah.
  ///
  /// Pemotongan terjadi **sebelum** unggah supaya yang dikirim ke server sudah
  /// berukuran wajar; endpoint web membatasi 5 MB, dan foto mentah dari kamera
  /// tablet gampang melewatinya.
  Future<void> _pickPhoto(ImageSource source) async {
    setState(() {
      _error = null;
      _uploading = true;
    });

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        // Batas awal supaya uCrop tidak memuat bitmap raksasa ke memori
        // tablet Unisoc T618.
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 92,
      );
      if (picked == null) {
        if (mounted) setState(() => _uploading = false);
        return;
      }

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Sesuaikan Foto',
            toolbarColor: AppTheme.brand,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: false,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.original,
            ],
          ),
        ],
      );
      if (cropped == null) {
        if (mounted) setState(() => _uploading = false);
        return;
      }

      final bytes = await File(cropped.path).readAsBytes();
      final url = await ref.read(menuAdminRepositoryProvider).uploadImage(
            bytes: bytes,
            filename: 'menu-${DateTime.now().millisecondsSinceEpoch}.jpg',
          );

      if (mounted) {
        setState(() {
          _imageUrl = url;
          _uploading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = 'Gagal mengunggah foto: '
              '${error.toString().replaceFirst('Exception: ', '')}';
        });
      }
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nama menu wajib diisi');
      return;
    }
    if (_priceValue <= 0) {
      setState(() => _error = 'Harga jual harus lebih dari 0');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(menuAdminRepositoryProvider);
    try {
      if (_isNew) {
        await repo.create(
          name: name,
          price: _priceValue,
          costPrice: _costValue,
          categoryId: _categoryId,
          description: _description.text.trim(),
          imageUrl: _imageUrl,
        );
      } else {
        // Semua field dikirim, termasuk yang tidak diubah - PUT mengganti
        // seluruh baris, jadi field yang dihilangkan akan jadi null di server.
        await repo.update(
          widget.existing!.id,
          name: name,
          price: _priceValue,
          costPrice: _costValue,
          isAvailable: _available,
          categoryId: _categoryId,
          description: _description.text.trim(),
          imageUrl: _imageUrl,
        );
        // Endpoint terpisah di web - hanya dipanggil kalau memang berubah,
        // supaya tidak menulis ulang tanpa alasan.
        if (_soldOut != widget.existing!.isSoldOut) {
          await repo.toggleSoldOut(widget.existing!.id, _soldOut);
        }
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/catalog.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
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
        _Header(onAdd: () => _openEditor(context, ref, null)),
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

  static String _readable(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}

class _Header extends StatelessWidget {
  const _Header({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Menu & HPP',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 2),
                Text(
                  'HPP diisi manual per menu. Margin dihitung otomatis dari harga jual.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Tambah Menu'),
          ),
        ],
      ),
    );
  }
}

class _MenuTable extends StatelessWidget {
  const _MenuTable({required this.items, required this.onEdit});

  final List<MenuItemModel> items;
  final void Function(MenuItemModel) onEdit;

  @override
  Widget build(BuildContext context) {
    final withoutCost = items.where((e) => !e.hasCost).length;

    return Column(
      children: [
        if (withoutCost > 0)
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
        const _TableHead(),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _MenuRow(item: items[i], onEdit: onEdit),
          ),
        ),
      ],
    );
  }
}

class _TableHead extends StatelessWidget {
  const _TableHead();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: Colors.black54,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: const [
          Expanded(flex: 4, child: Text('MENU', style: style)),
          Expanded(flex: 2, child: Text('HARGA JUAL', style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text('HPP', style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text('MARGIN', style: style, textAlign: TextAlign.right)),
          SizedBox(width: 90, child: Text('STATUS', style: style, textAlign: TextAlign.center)),
          SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item, required this.onEdit});

  final MenuItemModel item;
  final void Function(MenuItemModel) onEdit;

  @override
  Widget build(BuildContext context) {
    final percent = item.marginPercent;

    return InkWell(
      onTap: () => onEdit(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
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

  bool _saving = false;
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

    return AlertDialog(
      title: Text(_isNew ? 'Tambah Menu' : 'Ubah Menu'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: _isNew,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nama menu'),
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
              ),
              const SizedBox(height: 12),
              if (showMargin)
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
              if (!_isNew) ...[
                const SizedBox(height: 8),
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
          onPressed: _saving ? null : _save,
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
          description: _description.text.trim(),
        );
      } else {
        await repo.update(
          widget.existing!.id,
          name: name,
          price: _priceValue,
          costPrice: _costValue,
          isAvailable: _available,
          isSoldOut: _soldOut,
          description: _description.text.trim(),
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

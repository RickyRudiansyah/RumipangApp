import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/inventory.dart';
import '../../shared/layout.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'inventory_provider.dart';

/// Stok bahan baku + alert saat menipis.
///
/// **Stok tidak berkurang otomatis saat ada penjualan.** HPP di aplikasi ini
/// diisi manual tanpa resep, jadi sistem tidak tahu satu porsi menghabiskan
/// berapa banyak bahan. Semua perubahan dicatat manual lewat tombol
/// "Sesuaikan" (BACKEND-ADDITIONS.md §4).
class InventoryPage extends ConsumerWidget {
  const InventoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ingredientsProvider);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            context.isCompact ? 14 : 20,
            16,
            context.isCompact ? 14 : 20,
            12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Stok Bahan Baku',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.isCompact
                          ? 'Dicatat manual.'
                          : 'Dicatat manual - stok tidak berkurang sendiri saat ada penjualan.',
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () => _openCreate(context, ref),
                icon: const Icon(Icons.add),
                label: Text(context.isCompact ? 'Bahan' : 'Tambah Bahan'),
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
              onRetry: () => ref.invalidate(ingredientsProvider),
            ),
            data: (items) => items.isEmpty
                ? const EmptyState(
                    icon: Icons.inventory_2,
                    title: 'Belum ada bahan baku',
                    subtitle: 'Tambahkan bahan supaya stoknya bisa dipantau.',
                  )
                : _List(items: items),
          ),
        ),
      ],
    );
  }

  Future<void> _openCreate(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _IngredientEditorDialog(),
    );
    if (ok == true) ref.invalidate(ingredientsProvider);
  }
}

class _List extends ConsumerWidget {
  const _List({required this.items});

  final List<Ingredient> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final low = items.where((e) => e.isLow).toList();

    return Column(
      children: [
        if (low.isNotEmpty)
          Material(
            color: AppTheme.unpaid.withValues(alpha: 0.10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 20, color: AppTheme.unpaid),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${low.length} bahan sudah menipis: '
                      '${low.take(4).map((e) => e.name).join(', ')}'
                      '${low.length > 4 ? ', dan ${low.length - 4} lainnya' : ''}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.unpaid,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _Row(item: items[i]),
          ),
        ),
      ],
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.item});

  final Ingredient item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (color, label) = switch (item) {
      _ when item.isEmpty => (AppTheme.unpaid, 'Habis'),
      _ when item.isLow => (AppTheme.warn, 'Menipis'),
      _ => (AppTheme.paid, 'Aman'),
    };

    if (context.isCompact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  item.stockLabel,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: item.isLow ? color : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                StatusChip(label: label, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'alert ${item.thresholdLabel}',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => _adjust(context, ref),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                  child: const Text('Sesuaikan'),
                ),
                IconButton(
                  tooltip: 'Ubah ambang alert',
                  onPressed: () => _editThreshold(context, ref),
                  icon: const Icon(Icons.tune, size: 18),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
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
                  'alert saat sisa ${item.thresholdLabel}',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              item.stockLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: item.isLow ? color : Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(width: 90, child: Center(child: StatusChip(label: label, color: color))),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () => _adjust(context, ref),
            child: const Text('Sesuaikan'),
          ),
          IconButton(
            tooltip: 'Ubah ambang alert',
            onPressed: () => _editThreshold(context, ref),
            icon: const Icon(Icons.tune, size: 18),
          ),
        ],
      ),
    );
  }

  Future<void> _adjust(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _AdjustDialog(item: item),
    );
    if (ok == true) ref.invalidate(ingredientsProvider);
  }

  Future<void> _editThreshold(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _IngredientEditorDialog(existing: item),
    );
    if (ok == true) ref.invalidate(ingredientsProvider);
  }
}

// ------------------------------------------------------------- dialogs ----

/// Penyesuaian stok. Kasir memasukkan **jumlah positif** lalu memilih alasan;
/// tanda `delta` ditentukan dari alasannya, supaya tidak ada yang perlu
/// mengetik angka negatif dan salah tanda.
class _AdjustDialog extends ConsumerStatefulWidget {
  const _AdjustDialog({required this.item});

  final Ingredient item;

  @override
  ConsumerState<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends ConsumerState<_AdjustDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  StockReason _reason = StockReason.purchase;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _value => double.tryParse(_amount.text.trim().replaceAll(',', '.')) ?? 0;

  double get _resulting {
    final delta = _reason.isIncoming ? _value : -_value;
    return widget.item.stockQty + delta;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Sesuaikan ${widget.item.name}'),
      content: SizedBox(
        width: context.dialogWidth(420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stok sekarang ${widget.item.stockLabel}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<StockReason>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Alasan'),
              items: [
                for (final r in StockReason.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (v) => setState(() => _reason = v ?? _reason),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _reason.isIncoming ? 'Jumlah masuk' : 'Jumlah keluar',
                suffixText: widget.item.unit,
              ),
            ),
            const SizedBox(height: 12),
            if (_value > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: AppTheme.panel(
                  background: Colors.black.withValues(alpha: 0.03),
                ),
                child: Text(
                  'Stok menjadi ${_fmt(_resulting)} ${widget.item.unit}'
                  '${_resulting < 0 ? '  ·  tidak mungkin negatif' : ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _resulting < 0 ? AppTheme.unpaid : Colors.black87,
                  ),
                ),
              ),
            const SizedBox(height: 12),
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
              : const Text('Simpan'),
        ),
      ],
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  Future<void> _save() async {
    if (_value <= 0) {
      setState(() => _error = 'Jumlah harus lebih dari 0');
      return;
    }
    if (_resulting < 0) {
      setState(() => _error = 'Stok tidak bisa jadi negatif');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(inventoryRepositoryProvider).adjust(
            widget.item.id,
            delta: _reason.isIncoming ? _value : -_value,
            reason: _reason,
            note: _note.text.trim(),
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

class _IngredientEditorDialog extends ConsumerStatefulWidget {
  const _IngredientEditorDialog({this.existing});

  final Ingredient? existing;

  @override
  ConsumerState<_IngredientEditorDialog> createState() =>
      _IngredientEditorDialogState();
}

class _IngredientEditorDialogState extends ConsumerState<_IngredientEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _unit;
  late final TextEditingController _stock;
  late final TextEditingController _threshold;

  bool _saving = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _unit = TextEditingController(text: e?.unit ?? 'pcs');
    _stock = TextEditingController(text: e == null ? '0' : '');
    _threshold = TextEditingController(
      text: (e?.alertThreshold ?? 20).toString().replaceAll('.0', ''),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _stock.dispose();
    _threshold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Tambah Bahan Baku' : 'Ubah ${widget.existing!.name}'),
      content: SizedBox(
        width: context.dialogWidth(420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: _isNew,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nama bahan'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(
                      labelText: 'Satuan',
                      hintText: 'kg / gram / liter / pcs',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _threshold,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Alert saat sisa',
                    ),
                  ),
                ),
              ],
            ),
            if (_isNew) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _stock,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Stok awal'),
              ),
            ] else ...[
              const SizedBox(height: 12),
              const Text(
                'Stok tidak diubah dari sini - pakai tombol "Sesuaikan" supaya '
                'perubahannya tercatat beserta alasannya.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
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
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nama bahan wajib diisi');
      return;
    }
    final threshold =
        double.tryParse(_threshold.text.trim().replaceAll(',', '.')) ?? 20;

    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(inventoryRepositoryProvider);
    try {
      if (_isNew) {
        await repo.create(
          name: name,
          unit: _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim(),
          stockQty: double.tryParse(_stock.text.trim().replaceAll(',', '.')) ?? 0,
          alertThreshold: threshold,
        );
      } else {
        await repo.update(
          widget.existing!.id,
          name: name,
          unit: _unit.text.trim(),
          alertThreshold: threshold,
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

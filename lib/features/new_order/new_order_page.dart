import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../models/catalog.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'cart_provider.dart';
import 'catalog_provider.dart';

/// Order manual (POS) untuk pelanggan yang tidak scan QR:
/// grid menu di kiri, keranjang di kanan (SPEC §11).
class NewOrderPage extends ConsumerWidget {
  const NewOrderPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(menuProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: menu.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: e is AppFailure ? e.message : 'Gagal memuat menu.\n$e',
              onRetry: () => ref.invalidate(menuProvider),
            ),
            data: (_) => const _MenuGrid(),
          ),
        ),
        const VerticalDivider(width: 1),
        const SizedBox(width: 400, child: _CartPane()),
      ],
    );
  }
}

class _MenuGrid extends ConsumerWidget {
  const _MenuGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(menuByCategoryProvider);

    if (categories.isEmpty) {
      return const EmptyState(icon: Icons.restaurant_menu, title: 'Menu kosong');
    }

    return CustomScrollView(
      slivers: [
        for (final entry in categories) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                entry.key.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: Colors.black45,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 210,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.55,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _MenuCard(item: entry.value[i]),
                childCount: entry.value.length,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _MenuCard extends ConsumerWidget {
  const _MenuCard({required this.item});

  final MenuItemModel item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderable = item.isOrderable;

    return Opacity(
      opacity: orderable ? 1 : 0.5,
      child: Container(
        decoration: AppTheme.panel(),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: orderable ? () => _pick(context, ref) : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  Row(
                    children: [
                      Text(
                        Fmt.rupiah(item.price),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.brand,
                        ),
                      ),
                      const Spacer(),
                      if (!orderable)
                        const StatusChip(label: 'Habis', color: AppTheme.unpaid),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final byType = ref.read(variationsByMenuProvider)[item.id];

    if (byType == null || byType.isEmpty) {
      ref.read(cartProvider.notifier).add(item);
      return;
    }

    final chosen = await showDialog<List<MenuVariation>>(
      context: context,
      builder: (ctx) => _VariationDialog(item: item, byType: byType),
    );
    if (chosen != null) {
      ref.read(cartProvider.notifier).add(item, variations: chosen);
    }
  }
}

class _VariationDialog extends StatefulWidget {
  const _VariationDialog({required this.item, required this.byType});

  final MenuItemModel item;
  final Map<String, List<MenuVariation>> byType;

  @override
  State<_VariationDialog> createState() => _VariationDialogState();
}

class _VariationDialogState extends State<_VariationDialog> {
  final Map<String, MenuVariation> _selected = {};

  @override
  void initState() {
    super.initState();
    // Pilihan pertama tiap jenis dipakai sebagai default supaya kasir bisa
    // langsung menekan Tambah saat pelanggan tidak minta apa-apa.
    widget.byType.forEach((type, options) {
      if (options.isNotEmpty) _selected[type] = options.first;
    });
  }

  int get _extra => _selected.values.fold(0, (sum, v) => sum + v.extraPrice);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item.name),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in widget.byType.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Text(
                    entry.key,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: entry.value.map((option) {
                    final active = _selected[entry.key]?.id == option.id;
                    return ChoiceChip(
                      selected: active,
                      onSelected: (_) =>
                          setState(() => _selected[entry.key] = option),
                      label: Text(
                        option.extraPrice == 0
                            ? option.label
                            : '${option.label} +${Fmt.number(option.extraPrice)}',
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected.values.toList()),
          child: Text('Tambah · ${Fmt.rupiah(widget.item.price + _extra)}'),
        ),
      ],
    );
  }
}

class _CartPane extends ConsumerStatefulWidget {
  const _CartPane();

  @override
  ConsumerState<_CartPane> createState() => _CartPaneState();
}

class _CartPaneState extends ConsumerState<_CartPane> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final tables = ref.watch(tablesProvider).valueOrNull ?? const [];

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Row(
              children: [
                const Text(
                  'Keranjang',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (!cart.isEmpty)
                  TextButton(
                    onPressed: () => ref.read(cartProvider.notifier).clear(),
                    child: const Text('Kosongkan'),
                  ),
              ],
            ),
          ),

          Expanded(
            child: cart.isEmpty
                ? const EmptyState(
                    icon: Icons.shopping_cart_outlined,
                    title: 'Keranjang kosong',
                    subtitle: 'Ketuk menu di kiri untuk menambah.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, __) => const Divider(height: 18),
                    itemBuilder: (context, i) => _CartRow(line: cart.lines[i]),
                  ),
          ),

          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickTable(tables),
                  icon: const Icon(Icons.table_restaurant),
                  label: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_tableLabel(cart.tableId, tables)),
                  ),
                ),
                const SizedBox(height: 12),

                SegmentedButton<PaymentMethod>(
                  segments: const [
                    ButtonSegment(value: PaymentMethod.cash, label: Text('Tunai')),
                    ButtonSegment(value: PaymentMethod.qris, label: Text('QRIS')),
                  ],
                  selected: {cart.method},
                  onSelectionChanged: (s) =>
                      ref.read(cartProvider.notifier).setMethod(s.first),
                ),
                const SizedBox(height: 8),

                // QRIS di POS berarti uangnya sudah diterima - kasir tidak
                // membuat transaksi Midtrans dari sini.
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: cart.paymentStatus.isPaid,
                  onChanged: cart.method == PaymentMethod.qris
                      ? null
                      : (v) => ref.read(cartProvider.notifier).setPaid(v),
                  title: const Text('Uang sudah diterima'),
                  subtitle: Text(
                    cart.paymentStatus.isPaid
                        ? 'Struk langsung tercetak setelah order dibuat.'
                        : 'Order masuk dapur, struk menunggu verifikasi kasir.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text(
                      Fmt.rupiah(cart.total),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: cart.isEmpty || _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text('Buat Order · ${cart.itemCount} item'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _tableLabel(String? tableId, List<CafeTable> tables) {
    if (tableId == null) return 'Tanpa meja';
    for (final table in tables) {
      if (table.id == tableId) return table.label;
    }
    return 'Meja tidak dikenal';
  }

  Future<void> _pickTable(List<CafeTable> tables) async {
    final selected = await showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pilih meja'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, _noTable),
            child: const Text('Tanpa meja'),
          ),
          const Divider(),
          ...tables.map(
            (t) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t.id),
              child: Text(t.label),
            ),
          ),
        ],
      ),
    );
    if (selected == null) return; // dialog ditutup tanpa memilih
    ref.read(cartProvider.notifier).setTable(selected == _noTable ? null : selected);
  }

  /// Penanda "tanpa meja" supaya bisa dibedakan dari dialog yang dibatalkan.
  static const _noTable = '__none__';

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final paid = ref.read(cartProvider).paymentStatus.isPaid;
      final order = await ref.read(cartProvider.notifier).submit();
      if (mounted) {
        showSnack(
          context,
          'Order #${order.orderNo} dibuat.'
          '${paid ? ' Struk masuk antrian cetak.' : ' Menunggu pembayaran.'}',
        );
      }
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _CartRow extends ConsumerWidget {
  const _CartRow({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.read(cartProvider.notifier);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                Fmt.rupiah(line.item.price + line.extraPerUnit),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => cart.setQuantity(line.key, line.quantity - 1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '${line.quantity}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => cart.setQuantity(line.key, line.quantity + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
        SizedBox(
          width: 84,
          child: Text(
            Fmt.number(line.subtotal),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../models/catalog.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../../shared/format.dart';
import '../../shared/layout.dart';
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

    final grid = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _MenuToolbar(),
        Expanded(
          child: menu.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: e is AppFailure ? e.message : 'Gagal memuat menu.\n$e',
              onRetry: () => refreshCatalog(ref),
            ),
            data: (_) => const _MenuGrid(),
          ),
        ),
      ],
    );

    // Keranjang selebar 400 menyisakan ruang yang tidak cukup untuk grid menu
    // di layar sempit - dan di HP malah lebih lebar dari layarnya sendiri.
    // Diukur dari lebar nyata, bukan kategori layar: tablet potret pun terlalu
    // sempit untuk dua panel.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < SplitLayout.posCart) {
          return Column(
            children: [
              Expanded(child: grid),
              const _CartBar(),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: grid),
            const VerticalDivider(width: 1),
            const SizedBox(width: 400, child: _CartPane()),
          ],
        );
      },
    );
  }
}

/// Cari menu, saring per kategori, dan muat ulang katalog.
///
/// Tombol muat ulang bukan hiasan: menu yang baru ditambahkan dari tab Menu
/// atau dari dashboard web tidak muncul di sini sampai katalognya diambil ulang.
class _MenuToolbar extends ConsumerStatefulWidget {
  const _MenuToolbar();

  @override
  ConsumerState<_MenuToolbar> createState() => _MenuToolbarState();
}

class _MenuToolbarState extends ConsumerState<_MenuToolbar> {
  final _controller = TextEditingController();
  bool _refreshing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    refreshCatalog(ref);
    try {
      await ref.read(menuProvider.future);
      if (mounted) showSnack(context, 'Menu dimuat ulang.');
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (_) {
      // Pesan errornya sudah tampil di grid lewat ErrorView.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(posCategoryNamesProvider);
    final active = ref.watch(posCategoryProvider);
    final query = ref.watch(posQueryProvider);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Cari menu',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Hapus pencarian',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _controller.clear();
                              ref.read(posQueryProvider.notifier).setQuery('');
                            },
                          ),
                  ),
                  onChanged: (v) => ref.read(posQueryProvider.notifier).setQuery(v),
                ),
              ),
              const SizedBox(width: 6),
              _refreshing
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Muat ulang menu',
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                    ),
            ],
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _categoryChip(label: 'Semua', value: null, active: active == null),
                  for (final name in categories)
                    _categoryChip(label: name, value: name, active: active == name),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoryChip({
    required String label,
    required String? value,
    required bool active,
  }) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: OptionChip(
          label: label,
          selected: active,
          onTap: () => ref.read(posCategoryProvider.notifier).select(active ? null : value),
        ),
      );
}

/// Bilah keranjang di bawah layar HP.
class _CartBar extends ConsumerWidget {
  const _CartBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final empty = cart.lines.isEmpty;

    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      empty ? 'Keranjang kosong' : '${cart.itemCount} item',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    Text(
                      Fmt.rupiah(cart.total),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: empty ? null : () => _openCart(context),
                icon: const Icon(Icons.shopping_cart),
                label: const Text('Keranjang'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCart(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        // Disisakan ruang di atas supaya kasir masih melihat menu di baliknya
        // dan tahu lembar ini bisa ditutup.
        height: MediaQuery.sizeOf(ctx).height * 0.85,
        child: const _CartPane(),
      ),
    );
  }
}

class _MenuGrid extends ConsumerWidget {
  const _MenuGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(menuByCategoryProvider);

    if (categories.isEmpty) {
      // Dibedakan supaya kasir tidak menyangka menunya hilang padahal hanya
      // tersaring kata kunci / kategori.
      final filtering = ref.watch(posQueryProvider).trim().isNotEmpty ||
          ref.watch(posCategoryProvider) != null;

      return filtering
          ? const EmptyState(
              icon: Icons.search_off,
              title: 'Menu tidak ditemukan',
              subtitle: 'Ubah kata kunci atau pilih kategori "Semua".',
            )
          : const EmptyState(
              icon: Icons.restaurant_menu,
              title: 'Menu kosong',
              subtitle: 'Tambahkan menu di tab Menu, lalu tekan muat ulang.',
            );
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
  /// Pilihan per jenis variasi. Jenis yang **tidak ada** di map berarti
  /// "tanpa" - dan itu pilihan yang sah, bukan keadaan setengah jadi.
  final Map<String, MenuVariation> _selected = {};

  @override
  void initState() {
    super.initState();
    // Hanya pilihan **gratis** yang boleh terpilih sendiri. Dulu opsi pertama
    // tiap jenis selalu dipakai sebagai default; kalau kebetulan itu topping
    // berbayar, setiap porsi ikut ditagih topping yang tidak diminta siapa pun
    // dan harga dasar menu jadi tidak pernah benar. Ini pernah terjadi.
    widget.byType.forEach((type, options) {
      for (final option in options) {
        if (option.extraPrice == 0) {
          _selected[type] = option;
          break;
        }
      }
    });
  }

  int get _extra => _selected.values.fold(0, (sum, v) => sum + v.extraPrice);

  /// "Tanpa extra topping" - label yang membaca wajar untuk jenis apa pun.
  String _noneLabel(String type) => 'Tanpa ${type.toLowerCase()}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item.name),
      content: SizedBox(
        width: context.dialogWidth(460),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Harga dasar ${Fmt.rupiah(widget.item.price)}',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
              for (final entry in widget.byType.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Selalu ada jalan keluar dari sebuah jenis variasi.
                    OptionChip(
                      label: _noneLabel(entry.key),
                      selected: !_selected.containsKey(entry.key),
                      onTap: () => setState(() => _selected.remove(entry.key)),
                    ),
                    for (final option in entry.value)
                      OptionChip(
                        label: option.label,
                        selected: _selected[entry.key]?.id == option.id,
                        trailing: option.extraPrice == 0
                            ? null
                            : '+${Fmt.number(option.extraPrice)}',
                        onTap: () => setState(() => _selected[entry.key] = option),
                      ),
                  ],
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
          child: Text(
            _extra == 0
                ? 'Tambah · ${Fmt.rupiah(widget.item.price)}'
                : 'Tambah · ${Fmt.rupiah(widget.item.price + _extra)}',
          ),
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
    final tables = ref.watch(tablesProvider).value ?? const [];

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
                  icon: Icon(
                    cart.tableId == null
                        ? Icons.takeout_dining
                        : Icons.table_restaurant,
                  ),
                  label: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _tableLabel(cart.tableId, tables),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
    if (tableId == null) return _takeAwayLabel;
    for (final table in tables) {
      if (table.id == tableId) return table.label;
    }
    return 'Meja tidak dikenal';
  }

  /// Order tanpa meja hampir selalu dibungkus. "Tanpa meja" saja membuat kasir
  /// ragu apakah itu pilihan yang benar; kata "Take Away" yang menjawabnya.
  static const _takeAwayLabel = 'Take Away · Tanpa Meja';

  Future<void> _pickTable(List<CafeTable> tables) async {
    final selected = await showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pilih meja'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, _noTable),
            child: const Row(
              children: [
                Icon(Icons.takeout_dining, size: 20),
                SizedBox(width: 10),
                Text(_takeAwayLabel),
              ],
            ),
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

  /// Penanda "take away / tanpa meja" supaya bisa dibedakan dari dialog yang
  /// ditutup tanpa memilih.
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

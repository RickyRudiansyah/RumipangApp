import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../core/providers.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../../shared/format.dart';
import '../../shared/layout.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../auth/staff_provider.dart';
import '../printer/print_queue.dart';
import 'history_provider.dart';

/// Riwayat order: arsip + dibatalkan, dengan tombol cetak ulang struk.
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final filtered = ref.watch(filteredHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final search = TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Cari nomor order, meja, atau menu',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => ref.read(historyQueryProvider.notifier).setQuery(v),
              );
              final reload = IconButton(
                tooltip: 'Muat ulang',
                onPressed: () => ref.read(historyProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
              );
              final purge = IconButton(
                tooltip: 'Hapus riwayat',
                onPressed: () => _openPurgeDialog(context, ref),
                icon: const Icon(Icons.delete_sweep_outlined),
                color: AppTheme.unpaid,
              );

              if (constraints.maxWidth < SplitLayout.searchBar) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Riwayat',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                        const Spacer(),
                        reload,
                        purge,
                      ],
                    ),
                    const SizedBox(height: 10),
                    search,
                  ],
                );
              }

              return Row(
                children: [
                  const Text(
                    'Riwayat',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 20),
                  SizedBox(width: 340, child: search),
                  const Spacer(),
                  reload,
                  purge,
                ],
              );
            },
          ),
        ),
        Expanded(
          child: history.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: e is AppFailure ? e.message : 'Gagal memuat riwayat.\n$e',
              onRetry: () => ref.read(historyProvider.notifier).refresh(),
            ),
            data: (_) => filtered.isEmpty
                ? const EmptyState(
                    icon: Icons.history,
                    title: 'Tidak ada riwayat',
                    subtitle: 'Order yang sudah diselesaikan atau dibatalkan '
                        'muncul di sini.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _HistoryTile(order: filtered[i]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

Future<void> _openPurgeDialog(BuildContext context, WidgetRef ref) async {
  final deleted = await showDialog<int>(
    context: context,
    builder: (_) => const _PurgeHistoryDialog(),
  );
  if (deleted == null || !context.mounted) return;

  await ref.read(historyProvider.notifier).refresh();
  if (context.mounted) {
    showSnack(context, '$deleted order dihapus dari riwayat.');
  }
}

/// Rentang riwayat yang akan dihapus.
enum _PurgeScope {
  day('Hari'),
  month('Bulan'),
  year('Tahun'),
  all('Semua');

  const _PurgeScope(this.label);

  final String label;
}

/// Hapus riwayat per hari / bulan / tahun.
///
/// Jumlah order yang terdampak dihitung dari daftar yang sudah dimuat, bukan
/// ditanyakan ke server: penghapusan ini tidak bisa dibatalkan, dan angka
/// "0 order" adalah cara paling cepat menyadari salah pilih periode.
class _PurgeHistoryDialog extends ConsumerStatefulWidget {
  const _PurgeHistoryDialog();

  @override
  ConsumerState<_PurgeHistoryDialog> createState() => _PurgeHistoryDialogState();
}

class _PurgeHistoryDialogState extends ConsumerState<_PurgeHistoryDialog> {
  _PurgeScope _scope = _PurgeScope.day;
  DateTime _anchor = DateTime.now();

  bool _busy = false;
  String? _error;

  /// Batas bawah (inklusif) dan atas (eksklusif) dari periode terpilih.
  (DateTime?, DateTime?) get _range => switch (_scope) {
        _PurgeScope.day => (
            DateTime(_anchor.year, _anchor.month, _anchor.day),
            DateTime(_anchor.year, _anchor.month, _anchor.day + 1),
          ),
        _PurgeScope.month => (
            DateTime(_anchor.year, _anchor.month),
            // Bulan 13 otomatis jadi Januari tahun berikutnya.
            DateTime(_anchor.year, _anchor.month + 1),
          ),
        _PurgeScope.year => (
            DateTime(_anchor.year),
            DateTime(_anchor.year + 1),
          ),
        _PurgeScope.all => (null, null),
      };

  int get _affected {
    final all = ref.read(historyProvider).value ?? const <OrderModel>[];
    final (from, to) = _range;
    if (from == null || to == null) return all.length;
    return all
        .where((o) => !o.createdAt.isBefore(from) && o.createdAt.isBefore(to))
        .length;
  }

  String get _periodLabel => switch (_scope) {
        _PurgeScope.day => Fmt.dayOnly(_anchor),
        _PurgeScope.month => Fmt.monthOnly(_anchor),
        _PurgeScope.year => '${_anchor.year}',
        _PurgeScope.all => 'seluruh riwayat',
      };

  @override
  Widget build(BuildContext context) {
    final affected = _affected;

    return AlertDialog(
      title: const Text('Hapus Riwayat'),
      content: SizedBox(
        width: context.dialogWidth(460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final scope in _PurgeScope.values)
                  OptionChip(
                    label: scope.label,
                    selected: _scope == scope,
                    onTap: () => setState(() => _scope = scope),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_scope != _PurgeScope.all) ...[
              Row(
                children: [
                  IconButton(
                    tooltip: 'Mundur',
                    onPressed: () => setState(() => _anchor = _shift(-1)),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      _periodLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Maju',
                    onPressed: () => setState(() => _anchor = _shift(1)),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: AppTheme.panel(
                background: AppTheme.unpaid.withValues(alpha: 0.06),
                outline: AppTheme.unpaid.withValues(alpha: 0.35),
              ),
              child: Text(
                affected == 0
                    ? 'Tidak ada order pada $_periodLabel.'
                    : '$affected order pada $_periodLabel akan dihapus permanen.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: affected == 0 ? Colors.black54 : AppTheme.unpaid,
                ),
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
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.unpaid),
          onPressed: _busy || affected == 0 ? null : _purge,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Hapus'),
        ),
      ],
    );
  }

  /// Geser periode satu satuan sesuai lingkup yang dipilih.
  DateTime _shift(int step) => switch (_scope) {
        _PurgeScope.day => DateTime(_anchor.year, _anchor.month, _anchor.day + step),
        _PurgeScope.month => DateTime(_anchor.year, _anchor.month + step),
        _PurgeScope.year => DateTime(_anchor.year + step, _anchor.month),
        _PurgeScope.all => _anchor,
      };

  Future<void> _purge() async {
    final affected = _affected;
    final ok = await confirmDialog(
      context,
      title: 'Hapus riwayat $_periodLabel?',
      message: '$affected order akan dihapus permanen dan tidak bisa '
          'dikembalikan. Struknya juga tidak bisa dicetak ulang lagi.',
      confirmLabel: 'Hapus Permanen',
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final (from, to) = _range;
    try {
      final deleted = await ref
          .read(orderRepositoryProvider)
          .deleteHistory(from: from, to: to);
      if (mounted) Navigator.pop(context, deleted);
    } on AppFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }
}

class _HistoryTile extends ConsumerStatefulWidget {
  const _HistoryTile({required this.order});

  final OrderModel order;

  @override
  ConsumerState<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends ConsumerState<_HistoryTile> {
  bool _busy = false;
  bool _expanded = false;

  OrderModel get order => widget.order;

  @override
  Widget build(BuildContext context) {
    final cancelled = order.status == OrderStatus.cancelled;

    return Container(
      decoration: AppTheme.panel(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < SplitLayout.historyRow
                ? _compactHeader()
                : _wideHeader(),
          ),
          if (cancelled && order.cancelReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Alasan batal: ${order.cancelReason}',
                style: const TextStyle(fontSize: 12, color: AppTheme.unpaid),
              ),
            ),
          if (_expanded) ...[
            const Divider(height: 20),
            ...order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${item.quantity}x',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(child: Text(item.displayName)),
                    Text(Fmt.number(item.subtotal)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Tata letak asli: satu baris, kolom sejajar antar-kartu.
  Widget _wideHeader() {
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            '#${order.orderNo}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        SizedBox(
          width: 110,
          child: Text(
            order.tableLabel,
            style: const TextStyle(color: Colors.black87),
          ),
        ),
        SizedBox(
          width: 150,
          child: Text(
            Fmt.dayClock(order.createdAt),
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
        OrderStatusChip(order.status),
        const SizedBox(width: 8),
        PaymentChip(order.paymentStatus, method: order.paymentMethod),
        const Spacer(),
        Text(
          Fmt.rupiah(order.totalAmount),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 12),
        _expandButton(),
        if (order.paymentStatus.isPaid) _reprintButton(),
      ],
    );
  }

  /// Layar sempit: nomor + harga di baris pertama, sisanya turun.
  ///
  /// Harga tidak pernah ikut menyempit - itu angka yang paling dicari saat
  /// menelusuri riwayat, dan sebelumnya justru itu yang terpotong.
  Widget _compactHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '#${order.orderNo}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                order.tableLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black87),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              Fmt.rupiah(order.totalAmount),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            _expandButton(),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OrderStatusChip(order.status),
            PaymentChip(order.paymentStatus, method: order.paymentMethod),
            Text(
              Fmt.dayClock(order.createdAt),
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            if (order.paymentStatus.isPaid) _reprintButton(),
          ],
        ),
      ],
    );
  }

  Widget _expandButton() => IconButton(
        tooltip: _expanded ? 'Sembunyikan item' : 'Lihat item',
        onPressed: () => setState(() => _expanded = !_expanded),
        icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
      );

  /// Cetak ulang hanya masuk akal untuk order yang benar-benar dibayar -
  /// server tidak membuat struk untuk order UNPAID.
  Widget _reprintButton() => _busy
      ? const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
      : TextButton.icon(
          onPressed: _reprint,
          icon: const Icon(Icons.print, size: 18),
          label: const Text('Cetak Ulang'),
        );

  Future<void> _reprint() async {
    final ok = await confirmDialog(
      context,
      title: 'Cetak ulang struk',
      message: 'Struk order #${order.orderNo} akan diantrikan ulang ke printer.',
      confirmLabel: 'Cetak Ulang',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final staff = ref.read(staffProvider).value;
      await ref.read(printQueueProvider.notifier).reprintOrder(
            orderId: order.id,
            verifiedBy: staff?.name ?? 'Kasir',
          );
      if (mounted) showSnack(context, 'Struk #${order.orderNo} masuk antrian cetak.');
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

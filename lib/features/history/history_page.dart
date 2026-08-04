import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../../shared/format.dart';
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
          child: Row(
            children: [
              const Text(
                'Riwayat',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 20),
              SizedBox(
                width: 340,
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Cari nomor order, meja, atau menu',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) =>
                      ref.read(historyQueryProvider.notifier).setQuery(v),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => ref.read(historyProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Muat Ulang'),
              ),
            ],
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
          Row(
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
              IconButton(
                tooltip: _expanded ? 'Sembunyikan item' : 'Lihat item',
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ),
              // Cetak ulang hanya masuk akal untuk order yang benar-benar
              // dibayar - server tidak membuat struk untuk order UNPAID.
              if (order.paymentStatus.isPaid)
                _busy
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
                      ),
            ],
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

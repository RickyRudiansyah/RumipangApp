import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../models/order.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../orders/orders_provider.dart';

/// Denyut 20 detik supaya hitung mundur ETA ikut bergerak tanpa harus
/// menembak server. Murni tampilan.
final _tickProvider = StreamProvider<int>(
  (ref) => Stream.periodic(const Duration(seconds: 20), (i) => i),
);

/// Kitchen display: dua kolom Antrian -> Sedang Diproses (SPEC §11).
class KitchenPage extends ConsumerWidget {
  const KitchenPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(_tickProvider);

    final queued = ref.watch(queuedOrdersProvider);
    final processing = ref.watch(processingOrdersProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _Column(
            title: 'ANTRIAN',
            color: AppTheme.queued,
            orders: queued,
            emptyText: 'Tidak ada order menunggu',
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _Column(
            title: 'SEDANG DIPROSES',
            color: AppTheme.warn,
            orders: processing,
            emptyText: 'Dapur sedang kosong',
          ),
        ),
      ],
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.title,
    required this.color,
    required this.orders,
    required this.emptyText,
  });

  final String title;
  final Color color;
  final List<OrderModel> orders;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              StatusChip(label: '${orders.length}', color: color, filled: true),
            ],
          ),
        ),
        Expanded(
          child: orders.isEmpty
              ? EmptyState(icon: Icons.ramen_dining, title: emptyText)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: orders.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _KitchenCard(order: orders[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _KitchenCard extends ConsumerStatefulWidget {
  const _KitchenCard({required this.order});

  final OrderModel order;

  @override
  ConsumerState<_KitchenCard> createState() => _KitchenCardState();
}

class _KitchenCardState extends ConsumerState<_KitchenCard> {
  bool _busy = false;

  OrderModel get order => widget.order;

  @override
  Widget build(BuildContext context) {
    final overdue = order.isOverdue;
    final remaining = order.remainingEta;

    return Container(
      decoration: AppTheme.panel(
        background: overdue ? AppTheme.unpaid.withValues(alpha: 0.06) : null,
        outline: overdue ? AppTheme.unpaid : null,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                order.tableLabel,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 10),
              Text(
                '#${order.orderNo}',
                style: const TextStyle(color: Colors.black54),
              ),
              const Spacer(),
              Text(
                Fmt.ago(order.createdAt),
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ),
          const SizedBox(height: 6),

          Row(
            children: [
              // Dapur perlu tahu status uang juga - order belum bayar tetap
              // dimasak, tapi jangan sampai lolos dari kasir.
              PaymentChip(order.paymentStatus, method: order.paymentMethod),
              if (remaining != null) ...[
                const SizedBox(width: 8),
                StatusChip(
                  label: Fmt.countdown(remaining),
                  color: overdue ? AppTheme.unpaid : AppTheme.paid,
                  icon: overdue ? Icons.warning_amber : Icons.timer_outlined,
                  filled: overdue,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          ...order.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${item.quantity}x',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayName,
                          style: const TextStyle(fontSize: 15),
                        ),
                        if (item.notes != null)
                          Text(
                            item.notes!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.warn,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (order.notes != null) ...[
            const SizedBox(height: 6),
            Text(
              'Catatan: ${order.notes}',
              style: const TextStyle(fontSize: 13, color: AppTheme.warn),
            ),
          ],

          const SizedBox(height: 14),
          if (order.canStartProcessing)
            FilledButton.icon(
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Mulai Proses'),
            )
          else if (order.canMarkServed)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _served,
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.paid),
                    icon: const Icon(Icons.room_service),
                    label: const Text('Sudah Diantar'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _busy ? null : () => _addEta(5),
                  child: const Text('+5 mnt'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _addEta(10),
                  child: const Text('+10'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _start() async {
    final minutes = await _askEta();
    if (minutes == null || !mounted) return;
    await _run(() => ref
        .read(cashierBoardProvider.notifier)
        .startProcessing(order, estimatedMinutes: minutes));
  }

  Future<void> _served() =>
      _run(() => ref.read(cashierBoardProvider.notifier).markServed(order));

  /// `update-eta` **menambah** dari ETA berjalan, bukan menimpa dari sekarang.
  Future<void> _addEta(int minutes) =>
      _run(() => ref.read(cashierBoardProvider.notifier).addEta(order, minutes));

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<int?> _askEta() => showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Estimasi untuk #${order.orderNo}'),
          content: const Text('Berapa lama pesanan ini siap?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            for (final m in [5, 10, 15, 20])
              FilledButton(
                onPressed: () => Navigator.pop(ctx, m),
                child: Text('$m mnt'),
              ),
          ],
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../models/order.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'orders_provider.dart';

/// Pintu ke daftar order QRIS yang sudah lunas hari ini.
///
/// Board kasir sengaja hanya berisi pekerjaan yang **belum selesai** -
/// praktisnya order tunai. QRIS lunas sebelum ordernya lahir, jadi ia langsung
/// masuk riwayat dan tidak pernah mampir ke board. Akibatnya warung kehilangan
/// pandangan atas pesanan yang justru sudah dibayar; ini mengembalikannya tanpa
/// menaruhnya kembali jadi pekerjaan yang harus ditutup.
class QrisPaidTile extends ConsumerWidget {
  const QrisPaidTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(qrisPaidProvider).value ?? const <OrderModel>[];
    final total = orders.fold<int>(0, (sum, o) => sum + o.totalAmount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Material(
        color: AppTheme.paid.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            ref.read(qrisPaidProvider.notifier).refresh();
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const QrisPaidPage()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.qr_code_2, size: 20, color: AppTheme.paid),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'QRIS Lunas',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        orders.isEmpty
                            ? 'hari ini belum ada'
                            : '${orders.length} order · ${Fmt.rupiah(total)}',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.black38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Daftar order QRIS lunas hari ini - **hanya untuk dilihat**.
///
/// Sengaja tanpa tombol "Selesai": ordernya sudah lunas dan sudah tercatat di
/// riwayat. Menaruh aksi di sini mengembalikannya jadi pekerjaan yang harus
/// ditutup kasir - persis keadaan yang ingin dihindari.
class QrisPaidPage extends ConsumerWidget {
  const QrisPaidPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(qrisPaidProvider);
    final orders = async.value ?? const <OrderModel>[];
    final total = orders.fold<int>(0, (sum, o) => sum + o.totalAmount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('QRIS Lunas Hari Ini'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () => ref.read(qrisPaidProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: e is AppFailure ? e.message : 'Gagal memuat.\n$e',
          onRetry: () => ref.read(qrisPaidProvider.notifier).refresh(),
        ),
        data: (_) => orders.isEmpty
            ? const EmptyState(
                icon: Icons.qr_code_2,
                title: 'Belum ada pembayaran QRIS hari ini',
                subtitle: 'Order QRIS langsung lunas dan masuk riwayat.',
              )
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: AppTheme.paid.withValues(alpha: 0.08),
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                    child: Text(
                      '${orders.length} order · ${Fmt.rupiah(total)}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.paid,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      itemCount: orders.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _QrisOrderTile(order: orders[i]),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _QrisOrderTile extends StatelessWidget {
  const _QrisOrderTile({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.panel(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '#${order.orderNo}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              Text(order.tableLabel, style: const TextStyle(color: Colors.black54)),
              Text(
                Fmt.clock(order.createdAt),
                style: const TextStyle(color: Colors.black54),
              ),
              const StatusChip(label: 'LUNAS · QRIS', color: AppTheme.paid),
            ],
          ),
          const SizedBox(height: 8),
          ...order.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
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
          const Divider(height: 18),
          Row(
            children: [
              const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(
                Fmt.rupiah(order.totalAmount),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

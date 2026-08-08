import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../models/order.dart';
import '../../shared/format.dart';
import '../../shared/layout.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../auth/staff_provider.dart';
import '../printer/print_queue.dart';
import 'orders_provider.dart';
import 'pending_actions.dart';
import 'qris_paid_page.dart';

/// Meja yang sedang dibuka di panel kanan. `null` = ikut meja pertama.
class SelectedTableNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? tableKey) => state = tableKey;
}

final selectedTableProvider =
    NotifierProvider<SelectedTableNotifier, String?>(SelectedTableNotifier.new);

/// Layar utama kasir: daftar meja di kiri, detail order di kanan
/// (master-detail, tablet landscape - SPEC §11).
class CashierBoardPage extends ConsumerWidget {
  const CashierBoardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(cashierBoardProvider);
    final groups = ref.watch(tableGroupsProvider);
    final pending = ref.watch(pendingActionsProvider);

    return board.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(
        message: error is AppFailure
            ? error.message
            : 'Gagal memuat board kasir.\n$error',
        onRetry: () => ref.read(cashierBoardProvider.notifier).refresh(),
      ),
      data: (data) {
        // Pilihan meja yang sudah tidak ada lagi (mis. baru diarsipkan) jatuh
        // kembali ke meja pertama, supaya panel kanan tidak pernah kosong
        // padahal masih ada order.
        final selectedId = ref.watch(selectedTableProvider);
        TableGroup? selected;
        for (final group in groups) {
          if (group.key == selectedId) {
            selected = group;
            break;
          }
        }
        selected ??= groups.isEmpty ? null : groups.first;

        const emptyState = EmptyState(
          icon: Icons.table_restaurant,
          title: 'Belum ada order aktif',
          subtitle: 'Order yang masuk akan muncul di sini secara otomatis.',
        );

        final selectedGroup = selected;

        return Column(
          children: [
            if (data.fromCache)
              OfflineBanner(updatedAt: data.updatedAt, pendingActions: pending.length),
            Expanded(
              // Diukur dari lebar yang benar-benar tersedia, bukan lebar layar:
              // tablet potret masih "medium" tapi sisa ruangnya setelah panel
              // meja tidak cukup untuk detail order.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < SplitLayout.cashierBoard) {
                    return groups.isEmpty
                        ? emptyState
                        : _TableList(
                            groups: groups,
                            selected: null,
                            onOpen: (group) => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => _TableDetailPage(tableKey: group.key),
                              ),
                            ),
                          );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 264,
                        child: _TableList(groups: groups, selected: selectedGroup),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: selectedGroup == null
                            ? emptyState
                            : _TableDetail(group: selectedGroup),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

extension on TableGroup {
  String get key => tableId ?? '_none';
}

/// Halaman detail meja untuk layar HP.
///
/// Sengaja mengambil ulang grup dari [tableGroupsProvider] lewat `tableKey`,
/// bukan menerima objek [TableGroup] jadi - supaya isinya tetap ikut berubah
/// saat realtime memperbarui board selagi halaman ini terbuka.
class _TableDetailPage extends ConsumerWidget {
  const _TableDetailPage({required this.tableKey});

  final String tableKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(tableGroupsProvider);

    TableGroup? group;
    for (final g in groups) {
      if (g.key == tableKey) {
        group = g;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(group?.label ?? 'Meja')),
      body: group == null
          // Meja bisa hilang saat order terakhirnya diarsipkan dari perangkat
          // lain. Menutup halaman sendiri lebih baik daripada layar kosong.
          ? const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'Meja ini sudah selesai',
              subtitle: 'Semua ordernya sudah diarsipkan.',
            )
          : _TableDetail(group: group),
    );
  }
}

class _TableList extends ConsumerWidget {
  const _TableList({
    required this.groups,
    required this.selected,
    this.onOpen,
  });

  final List<TableGroup> groups;
  final TableGroup? selected;

  /// Diisi hanya di layar HP, saat detail dibuka sebagai halaman baru.
  /// Kalau null, ketukan cukup mengubah pilihan di panel kanan.
  final void Function(TableGroup)? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (groups.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Tidak ada meja aktif', style: TextStyle(color: Colors.black45)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'MEJA',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: Colors.black45,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              final isSelected = group.key == selected?.key;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: isSelected ? AppTheme.brand.withValues(alpha: 0.10) : null,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      ref.read(selectedTableProvider.notifier).select(group.key);
                      onOpen?.call(group);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          if (group.unpaidCount > 0)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Icons.circle, size: 9, color: AppTheme.unpaid),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.label,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight:
                                        isSelected ? FontWeight.w800 : FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${group.orders.length} order · '
                                  '${Fmt.rupiah(group.total)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (group.unpaidCount > 0)
                            StatusChip(
                              label: '${group.unpaidCount}',
                              color: AppTheme.unpaid,
                              filled: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        // Board ini hanya berisi pekerjaan yang belum selesai - praktisnya
        // order tunai. QRIS lunas sebelum ordernya lahir dan langsung masuk
        // riwayat, jadi ia butuh pintunya sendiri supaya warung tidak
        // kehilangan pandangan atas pesanan yang justru sudah dibayar.
        const QrisPaidTile(),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(
            children: [
              Icon(Icons.circle, size: 9, color: AppTheme.unpaid),
              SizedBox(width: 8),
              Text(
                'belum bayar',
                style: TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TableDetail extends ConsumerWidget {
  const _TableDetail({required this.group});

  final TableGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  group.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${group.orders.length} order',
                style: const TextStyle(color: Colors.black54, fontSize: 15),
              ),
              const Spacer(),
              const SizedBox(width: 8),
              Text(
                Fmt.rupiah(group.total),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            itemCount: group.orders.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OrderCard(order: group.orders[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _OrderCard extends ConsumerStatefulWidget {
  const _OrderCard({required this.order});

  final OrderModel order;

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _busy = false;

  OrderModel get order => widget.order;

  @override
  Widget build(BuildContext context) {
    final isPendingSync = ref.watch(pendingActionsProvider).any(
          (a) => a.orderId == order.id,
        );

    return Container(
      decoration: AppTheme.panel(
        outline: order.paymentStatus.isPaid
            ? null
            : AppTheme.unpaid.withValues(alpha: 0.45),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wrap, bukan Row: nomor order + jam + dua chip status tidak selalu
          // muat sebaris di panel sempit, dan chip pembayaran adalah hal
          // terakhir yang boleh terpotong.
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '#${order.orderNo}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                Fmt.clock(order.createdAt),
                style: const TextStyle(color: Colors.black54),
              ),
              OrderStatusChip(order.status),
              PaymentChip(order.paymentStatus, method: order.paymentMethod),
              if (isPendingSync)
                const StatusChip(
                  label: 'menunggu terkirim',
                  color: AppTheme.warn,
                  icon: Icons.sync_problem,
                ),
            ],
          ),
          const SizedBox(height: 12),

          ...order.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${item.quantity}x',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.displayName),
                        if (item.notes != null)
                          Text(
                            'Catatan: ${item.notes}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.warn,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    Fmt.number(item.subtotal),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (order.notes != null) ...[
            const SizedBox(height: 4),
            Text(
              'Catatan order: ${order.notes}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],

          const Divider(height: 22),
          Row(
            children: [
              const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(
                Fmt.rupiah(order.totalAmount),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),

          // "Selesai" pindah ke kartu order, bukan bilah per meja: satu meja
          // bisa memesan beberapa kali, dan menutup semuanya sekaligus membuat
          // order yang baru masuk ikut hilang.
          if (order.isSettled) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _archive,
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.done_all),
              label: const Text('Selesai · Pindahkan ke Riwayat'),
            ),
          ],

          if (order.canMarkPaid || order.canCancel) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (order.canMarkPaid)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _markPaid,
                      icon: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.receipt_long),
                      label: const Text('Verifikasi & Cetak Struk'),
                    ),
                  ),
                if (order.canMarkPaid && order.canCancel) const SizedBox(width: 12),
                if (order.canCancel)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _cancel,
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.unpaid),
                    icon: const Icon(Icons.close),
                    label: const Text('Batalkan'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _markPaid() async {
    final ok = await confirmDialog(
      context,
      title: 'Verifikasi pembayaran tunai',
      message: 'Terima ${Fmt.rupiah(order.totalAmount)} untuk order '
          '#${order.orderNo}?\n\nStruk akan langsung dicetak.',
      confirmLabel: 'Sudah Terima Uang',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final outcome = await ref.read(cashierBoardProvider.notifier).markPaid(order);
      if (!mounted) return;

      switch (outcome) {
        case MarkPaidOutcome.paidAndQueued:
          showSnack(context, 'Lunas. Struk #${order.orderNo} masuk antrian cetak.');
        case MarkPaidOutcome.paidButNotQueued:
          await _warnPrintNotQueued();
        case MarkPaidOutcome.queuedOffline:
          showSnack(
            context,
            'Jaringan mati. Order #${order.orderNo} BELUM lunas - verifikasi '
            'disimpan dan akan dikirim otomatis saat internet kembali.',
            error: true,
          );
      }
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// `print_queued: false` - order tetap lunas, tapi strukya gagal diantrikan.
  /// Jangan gagalkan transaksinya; tawarkan cetak ulang (API-CONTRACT §3).
  Future<void> _warnPrintNotQueued() async {
    final retry = await confirmDialog(
      context,
      title: 'Lunas, tapi struk gagal diantrikan',
      message: 'Pembayaran order #${order.orderNo} sudah tercatat LUNAS.\n\n'
          'Struknya tidak masuk antrian cetak. Coba antrikan ulang sekarang?',
      confirmLabel: 'Antrikan Struk',
    );
    if (!retry || !mounted) return;

    final staff = ref.read(staffProvider).value;
    try {
      await ref.read(printQueueProvider.notifier).reprintOrder(
            orderId: order.id,
            verifiedBy: staff?.name ?? 'Kasir',
          );
      if (mounted) showSnack(context, 'Struk diantrikan ulang.');
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _archive() async {
    final ok = await confirmDialog(
      context,
      title: 'Selesaikan order #${order.orderNo}?',
      message: 'Order ini dipindahkan ke riwayat. Order lain di '
          '${order.tableLabel} tidak ikut terpengaruh.',
      confirmLabel: 'Selesaikan',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(cashierBoardProvider.notifier).archiveOrder(order);
      if (mounted) showSnack(context, 'Order #${order.orderNo} masuk riwayat.');
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final reason = await reasonDialog(context);
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(cashierBoardProvider.notifier).cancel(order, reason);
      if (mounted) showSnack(context, 'Order #${order.orderNo} dibatalkan.');
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

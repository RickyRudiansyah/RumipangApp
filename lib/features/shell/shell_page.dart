import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/realtime_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../auth/staff_provider.dart';
import '../history/history_page.dart';
import '../kitchen/kitchen_page.dart';
import '../new_order/new_order_page.dart';
import '../orders/cashier_board_page.dart';
import '../orders/orders_provider.dart';
import '../orders/pending_actions.dart';
import '../printer/print_queue.dart';
import '../printer/printer_provider.dart';
import '../printer/printer_settings_page.dart';

/// Kerangka aplikasi: NavigationRail di kiri, layar aktif di kanan.
///
/// Di sinilah semua layanan latar dinyalakan (realtime, loop cetak, wakelock)
/// dan dimatikan saat kasir keluar.
class ShellPage extends ConsumerStatefulWidget {
  const ShellPage({super.key});

  @override
  ConsumerState<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends ConsumerState<ShellPage> with WidgetsBindingObserver {
  int _index = 0;

  static const _printerTabIndex = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startServices());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  Future<void> _startServices() async {
    // Tablet dipakai seharian sambil di-charge - layar jangan mati sendiri
    // di tengah antrean pelanggan (SPEC §2).
    unawaited(WakelockPlus.enable());

    ref.read(realtimeSyncProvider).start();

    // Sambungkan printer yang tersimpan lalu jalankan loop antrian.
    await ref.read(printerControllerProvider.notifier).connect();
    ref.read(printQueueProvider.notifier).start();

    // Kalau ada verifikasi tunai yang tertunda dari sesi sebelumnya, kirim
    // sekarang selagi jaringan hidup.
    unawaited(ref.read(pendingActionsProvider.notifier).flush());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    // Websocket sering sudah mati diam-diam setelah layar lama tidak dipakai,
    // dan staff bisa saja dinonaktifkan owner sementara aplikasi di belakang.
    unawaited(ref.read(realtimeSyncProvider).resync());
    unawaited(ref.read(staffProvider.notifier).revalidate());
    unawaited(ref.read(printerControllerProvider.notifier).ensureReady());
    unawaited(ref.read(pendingActionsProvider.notifier).flush());
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffProvider).valueOrNull;
    final unpaid = ref.watch(unpaidCountProvider);
    final queue = ref.watch(printQueueProvider);
    final pending = ref.watch(pendingActionsProvider);

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Icon(Icons.coffee, color: AppTheme.brand, size: 28),
              ),
              destinations: [
                NavigationRailDestination(
                  icon: _badged(Icons.point_of_sale, unpaid, AppTheme.unpaid),
                  label: const Text('Kasir'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.soup_kitchen),
                  label: Text('Dapur'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.add_shopping_cart),
                  label: Text('Order'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.history),
                  label: Text('Riwayat'),
                ),
                NavigationRailDestination(
                  icon: _badged(
                    Icons.print,
                    queue.failed,
                    AppTheme.unpaid,
                  ),
                  label: const Text('Printer'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    staffName: staff?.name ?? 'Kasir',
                    staffRole: staff?.role ?? '',
                    pendingSync: pending.length,
                    onPrinterTap: () => setState(() => _index = _printerTabIndex),
                    onSignOut: _signOut,
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: IndexedStack(
                      index: _index,
                      children: const [
                        CashierBoardPage(),
                        KitchenPage(),
                        NewOrderPage(),
                        HistoryPage(),
                        PrinterSettingsPage(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badged(IconData icon, int count, Color color) {
    if (count <= 0) return Icon(icon);
    return Badge.count(count: count, backgroundColor: color, child: Icon(icon));
  }

  Future<void> _signOut() async {
    final ok = await confirmDialog(
      context,
      title: 'Keluar dari aplikasi?',
      message: 'Antrian cetak akan berhenti sampai kasir masuk lagi.',
      confirmLabel: 'Keluar',
      destructive: true,
    );
    if (!ok) return;

    await ref.read(printQueueProvider.notifier).stop();
    await ref.read(realtimeSyncProvider).stop();
    await ref.read(printerControllerProvider.notifier).disconnect();
    await WakelockPlus.disable();
    await ref.read(staffProvider.notifier).signOut();
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.staffName,
    required this.staffRole,
    required this.pendingSync,
    required this.onPrinterTap,
    required this.onSignOut,
  });

  final String staffName;
  final String staffRole;
  final int pendingSync;
  final VoidCallback onPrinterTap;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Text(
            'Rumipang · Kasir',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          if (pendingSync > 0) ...[
            StatusChip(
              label: '$pendingSync verifikasi menunggu terkirim',
              color: AppTheme.warn,
              icon: Icons.sync_problem,
            ),
            const SizedBox(width: 12),
          ],
          // Indikator printer wajib selalu terlihat (SPEC §11).
          PrinterIndicator(onTap: onPrinterTap),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                staffName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                staffRole,
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Keluar',
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
    );
  }
}

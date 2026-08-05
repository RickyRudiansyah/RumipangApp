import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/realtime_service.dart';
import '../../shared/layout.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../admin/menu_admin_page.dart';
import '../auth/staff_provider.dart';
import '../history/history_page.dart';
import '../inventory/inventory_page.dart';
import '../inventory/inventory_provider.dart';
import '../meals/staff_meals_page.dart';
import '../new_order/new_order_page.dart';
import '../orders/cashier_board_page.dart';
import '../orders/orders_provider.dart';
import '../orders/pending_actions.dart';
import '../printer/print_queue.dart';
import '../printer/printer_provider.dart';
import '../printer/printer_settings_page.dart';
import '../reports/reports_page.dart';
import '../settings/theme_settings_page.dart';

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

  /// Harus mengikuti urutan `destinations` dan [_pages].
  /// Indikator printer di TopBar melompat ke sini saat ditekan.
  static const _printerTabIndex = 8;

  /// Urutan halaman. **Satu-satunya sumber urutan** - `destinations` di rail,
  /// bar bawah, lembar "Lainnya", dan [_printerTabIndex] semuanya mengikuti
  /// indeks di sini.
  static const List<Widget> _pages = [
    CashierBoardPage(), // 0
    NewOrderPage(), // 1
    HistoryPage(), // 2
    MenuAdminPage(), // 3
    InventoryPage(), // 4
    ReportsPage(), // 5
    StaffMealsPage(), // 6
    ThemeSettingsPage(), // 7
    PrinterSettingsPage(), // 8
  ];

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
    final staff = ref.watch(staffProvider).value;
    final unpaid = ref.watch(unpaidCountProvider);
    final queue = ref.watch(printQueueProvider);
    final pending = ref.watch(pendingActionsProvider);
    final lowStock = ref.watch(lowStockCountProvider);

    final compact = context.isCompact;

    final topBar = _TopBar(
      staffName: staff?.name ?? 'Kasir',
      staffRole: staff?.role ?? '',
      pendingSync: pending.length,
      compact: compact,
      onPrinterTap: () => setState(() => _index = _printerTabIndex),
      onSignOut: _signOut,
    );

    if (compact) {
      // HP: navigasi pindah ke bawah. Sembilan tujuan tidak muat di bar bawah,
      // jadi lima yang paling sering dipakai ditaruh di bar dan sisanya masuk
      // lembar "Lainnya".
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              topBar,
              const Divider(height: 1),
              Expanded(child: IndexedStack(index: _index, children: _pages)),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _bottomSelectedIndex,
          onDestinationSelected: _onBottomTap,
          destinations: [
            NavigationDestination(
              icon: _badged(Icons.point_of_sale, unpaid, AppTheme.unpaid),
              label: 'Kasir',
            ),
            const NavigationDestination(
              icon: Icon(Icons.add_shopping_cart),
              label: 'Order',
            ),
            const NavigationDestination(
              icon: Icon(Icons.history),
              label: 'Riwayat',
            ),
            const NavigationDestination(
              icon: Icon(Icons.restaurant_menu),
              label: 'Menu',
            ),
            NavigationDestination(
              icon: _badged(
                Icons.more_horiz,
                lowStock + queue.failed,
                AppTheme.warn,
              ),
              label: 'Lainnya',
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              // Label disembunyikan di tablet sempit supaya rail tidak memakan
              // lebar yang dibutuhkan isi layar.
              labelType: context.screen.isExpanded
                  ? NavigationRailLabelType.all
                  : NavigationRailLabelType.selected,
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
                  icon: Icon(Icons.add_shopping_cart),
                  label: Text('Order'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.history),
                  label: Text('Riwayat'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.restaurant_menu),
                  label: Text('Menu'),
                ),
                NavigationRailDestination(
                  icon: _badged(Icons.inventory_2, lowStock, AppTheme.warn),
                  label: const Text('Stok'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.bar_chart),
                  label: Text('Laporan'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.lunch_dining),
                  label: Text('Jatah'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.palette),
                  label: Text('Tema'),
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
                  topBar,
                  const Divider(height: 1),
                  Expanded(
                    child: IndexedStack(index: _index, children: _pages),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- navigasi bawah (HP) ---

  /// Empat tujuan pertama dipetakan satu-satu; sisanya diwakili "Lainnya".
  static const _bottomTabs = 4;

  int get _bottomSelectedIndex =>
      _index < _bottomTabs ? _index : _bottomTabs;

  void _onBottomTap(int i) {
    if (i < _bottomTabs) {
      setState(() => _index = i);
    } else {
      _openMoreSheet();
    }
  }

  Future<void> _openMoreSheet() async {
    final lowStock = ref.read(lowStockCountProvider);
    final failed = ref.read(printQueueProvider).failed;

    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _moreTile(ctx, 4, Icons.inventory_2, 'Stok Bahan Baku',
                badge: lowStock, badgeColor: AppTheme.warn),
            _moreTile(ctx, 5, Icons.bar_chart, 'Laporan Penjualan'),
            _moreTile(ctx, 6, Icons.lunch_dining, 'Jatah Makan Karyawan'),
            _moreTile(ctx, 7, Icons.palette, 'Tema Event'),
            _moreTile(ctx, 8, Icons.print, 'Printer',
                badge: failed, badgeColor: AppTheme.unpaid),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _index = picked);
  }

  Widget _moreTile(
    BuildContext ctx,
    int index,
    IconData icon,
    String label, {
    int badge = 0,
    Color badgeColor = AppTheme.unpaid,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: _index == index,
      trailing: badge > 0
          ? StatusChip(label: '$badge', color: badgeColor, filled: true)
          : null,
      onTap: () => Navigator.pop(ctx, index),
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
    required this.compact,
    required this.onPrinterTap,
    required this.onSignOut,
  });

  final String staffName;
  final String staffRole;
  final int pendingSync;
  final bool compact;
  final VoidCallback onPrinterTap;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: 8),
      child: Row(
        children: [
          if (compact)
            const Icon(Icons.coffee, color: AppTheme.brand, size: 22)
          else
            const Text(
              'Rumipang · Kasir',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          const Spacer(),
          if (pendingSync > 0) ...[
            StatusChip(
              // Kalimat panjang tidak muat di HP, tapi penandanya tetap wajib
              // terlihat - jadi yang dipendekkan teksnya, bukan chip-nya.
              label: compact
                  ? '$pendingSync menunggu'
                  : '$pendingSync verifikasi menunggu terkirim',
              color: AppTheme.warn,
              icon: Icons.sync_problem,
            ),
            SizedBox(width: compact ? 8 : 12),
          ],
          // Indikator printer wajib selalu terlihat (SPEC §11).
          PrinterIndicator(onTap: onPrinterTap, compact: compact),
          SizedBox(width: compact ? 4 : 12),
          // Nama staff dikorbankan lebih dulu di layar sempit: informasinya
          // paling jarang dibutuhkan saat melayani.
          if (!compact) ...[
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
          ],
          IconButton(
            tooltip: 'Keluar ($staffName)',
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/orders/orders_provider.dart';
import '../features/orders/pending_actions.dart';
import '../features/printer/print_queue.dart';
import 'env.dart';
import 'providers.dart';

/// Menjaga board tetap segar tanpa polling agresif (SPEC §7).
///
/// Pola yang dipakai - sama dengan dashboard web: **event realtime hanya
/// pemicu refetch, bukan sumber data.** Payload realtime tidak membawa relasi
/// (`table`, `items`), jadi datanya tetap diambil ulang lewat REST.
///
/// Websocket bisa putus tanpa pemberitahuan (pindah Wi-Fi <-> 4G), karena itu
/// polling cadangan tiap 15 detik tetap jalan sebagai jaring pengaman.
class RealtimeSync {
  RealtimeSync(this._ref);

  final Ref _ref;

  RealtimeChannel? _channel;
  Timer? _pollTimer;
  Timer? _debounce;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _subscribe();
    _pollTimer = Timer.periodic(Env.boardPollInterval, (_) => _safetyNetPoll());
  }

  Future<void> stop() async {
    _started = false;
    _debounce?.cancel();
    _debounce = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _unsubscribe();
  }

  void dispose() => unawaited(stop());

  // ------------------------------------------------------------ internal ---

  void _subscribe() {
    final supabase = _ref.read(supabaseProvider);
    try {
      _channel = supabase
          .channel('kasir')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            callback: (_) => _scheduleBoardRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'order_items',
            callback: (_) => _scheduleBoardRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'print_jobs',
            // Struk baru masuk antrian -> jangan tunggu tick berikutnya.
            callback: (_) => unawaited(_ref.read(printQueueProvider.notifier).pump()),
          )
          .subscribe();
    } catch (_) {
      // Realtime gagal dipasang - polling cadangan tetap menutupi.
    }
  }

  Future<void> _unsubscribe() async {
    final channel = _channel;
    _channel = null;
    if (channel == null) return;
    try {
      await _ref.read(supabaseProvider).removeChannel(channel);
    } catch (_) {
      // Sudah tertutup duluan.
    }
  }

  /// Satu ledakan event (order + beberapa order_items sekaligus) cukup memicu
  /// satu refetch.
  void _scheduleBoardRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_ref.read(cashierBoardProvider.notifier).refresh());
    });
  }

  Future<void> _safetyNetPoll() async {
    await _ref.read(cashierBoardProvider.notifier).refresh();
    // Kesempatan bagus untuk mengirim ulang verifikasi tunai yang tertunda:
    // kalau poll ini berhasil, artinya jaringan sudah pulih.
    await _ref.read(pendingActionsProvider.notifier).flush();
  }

  /// Dipanggil saat aplikasi kembali ke foreground - websocket sering sudah
  /// mati diam-diam setelah layar lama tidak dipakai.
  Future<void> resync() async {
    if (!_started) return;
    await _unsubscribe();
    _subscribe();
    await _safetyNetPoll();
  }
}

final realtimeSyncProvider = Provider<RealtimeSync>((ref) {
  final sync = RealtimeSync(ref);
  ref.onDispose(sync.dispose);
  return sync;
});

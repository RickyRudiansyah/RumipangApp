import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../core/local_store.dart';
import '../../core/providers.dart';
import '../../models/json.dart';
import '../../models/order.dart';

/// Verifikasi tunai yang gagal terkirim karena jaringan (SPEC §9).
///
/// Aturan yang tidak boleh dilanggar: selama aksi masih di antrian ini, order
/// **tetap ditampilkan BELUM LUNAS**. Uang hanya boleh mengikuti satu sumber
/// kebenaran, yaitu database - bukan optimistic update di tablet.
class PendingAction {
  const PendingAction({
    required this.localId,
    required this.orderId,
    required this.orderNo,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
  });

  factory PendingAction.fromJson(Map<String, dynamic> json) => PendingAction(
        localId: asString(json['local_id']),
        orderId: asString(json['order_id']),
        orderNo: asString(json['order_no']),
        createdAt: asDateOr(json['created_at'], DateTime.now()),
        attempts: asInt(json['attempts']),
        lastError: asStringOrNull(json['last_error']),
      );

  final String localId;
  final String orderId;
  final String orderNo;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;

  PendingAction bumped(String error) => PendingAction(
        localId: localId,
        orderId: orderId,
        orderNo: orderNo,
        createdAt: createdAt,
        attempts: attempts + 1,
        lastError: error,
      );

  Map<String, dynamic> toJson() => {
        'local_id': localId,
        'order_id': orderId,
        'order_no': orderNo,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'last_error': lastError,
      };
}

class PendingActionsNotifier extends Notifier<List<PendingAction>> {
  /// Setelah sekian percobaan gagal-bisnis, aksi dibuang supaya tidak
  /// menghantui antrian selamanya. Kegagalan jaringan tidak dihitung.
  static const _maxAttempts = 20;

  LocalStore get _store => ref.read(localStoreProvider);

  @override
  List<PendingAction> build() {
    return _store
        .readPendingActions()
        .map(PendingAction.fromJson)
        .toList(growable: false);
  }

  bool isPending(String orderId) => state.any((a) => a.orderId == orderId);

  Future<void> _persist(List<PendingAction> next) async {
    state = List.unmodifiable(next);
    await _store.writePendingActions(next.map((e) => e.toJson()).toList());
  }

  Future<void> enqueueMarkPaid(OrderModel order) async {
    if (isPending(order.id)) return;
    await _persist([
      ...state,
      PendingAction(
        localId: '${order.id}-${DateTime.now().microsecondsSinceEpoch}',
        orderId: order.id,
        orderNo: order.orderNo,
        createdAt: DateTime.now(),
      ),
    ]);
  }

  Future<void> drop(String localId) =>
      _persist(state.where((a) => a.localId != localId).toList());

  /// Coba kirim ulang semua aksi tertunda. Aman dipanggil berkali-kali.
  /// Mengembalikan jumlah aksi yang berhasil diselesaikan.
  Future<int> flush() async {
    if (state.isEmpty || _flushing) return 0;
    _flushing = true;
    try {
      final repo = ref.read(orderRepositoryProvider);
      final remaining = <PendingAction>[];
      var done = 0;

      for (final action in state) {
        try {
          await repo.markPaid(action.orderId);
          done++;
        } on ApiFailure catch (e) {
          // Sudah lunas di server (percobaan sebelumnya ternyata sampai),
          // atau ordernya sudah tidak ada. Dua-duanya: selesai, buang.
          if (e.isAlreadyPaid || e.isNotFound) {
            done++;
          } else {
            final bumped = action.bumped(e.message);
            if (bumped.attempts < _maxAttempts) remaining.add(bumped);
          }
        } on NetworkFailure {
          remaining.add(action); // masih offline, pertahankan apa adanya
        } on ServerFailure catch (e) {
          remaining.add(action.bumped(e.message));
        } on SessionExpiredFailure {
          remaining.add(action); // tunggu kasir login lagi
        }
      }

      await _persist(remaining);
      return done;
    } finally {
      _flushing = false;
    }
  }

  bool _flushing = false;
}

final pendingActionsProvider =
    NotifierProvider<PendingActionsNotifier, List<PendingAction>>(
  PendingActionsNotifier.new,
);

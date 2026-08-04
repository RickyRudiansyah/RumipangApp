import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/failure.dart';
import '../../core/providers.dart';
import '../../models/enums.dart';
import '../../models/print_job.dart';
import 'print_foreground_service.dart';
import 'printer_provider.dart';

class PrintQueueState {
  const PrintQueueState({
    this.running = false,
    this.pending = 0,
    this.failed = 0,
    this.lastSuccessAt,
    this.lastError,
  });

  final bool running;

  /// Job `PENDING` + `PRINTING` di server (dari layar monitoring).
  final int pending;
  final int failed;
  final DateTime? lastSuccessAt;
  final String? lastError;

  PrintQueueState copyWith({
    bool? running,
    int? pending,
    int? failed,
    DateTime? lastSuccessAt,
    String? lastError,
    bool clearError = false,
  }) =>
      PrintQueueState(
        running: running ?? this.running,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
        lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

/// Loop `klaim -> cetak -> ACK` (PRINTER.md §2).
///
/// ```
/// 1. GET /api/print/jobs?claim=1&limit=3   -> job dikunci jadi PRINTING
/// 2. tiap job: kirim byte ke printer
/// 3. sukses -> PATCH ack PRINTED   |   gagal -> PATCH ack FAILED
/// 4. ulangi tiap 4 detik (atau saat ada event realtime INSERT)
/// ```
class PrintQueueController extends Notifier<PrintQueueState> {
  Timer? _timer;
  bool _pumping = false;
  int _tick = 0;

  @override
  PrintQueueState build() {
    ref.onDispose(_stopTimer);
    return const PrintQueueState();
  }

  // ------------------------------------------------------------ siklus -----

  void start() {
    if (state.running) return;
    state = state.copyWith(running: true);
    _timer?.cancel();
    _timer = Timer.periodic(Env.printPollInterval, (_) => _onTick());
    unawaited(PrintForegroundService.start(text: 'Menunggu struk...'));
    unawaited(pump());
    unawaited(refreshMonitor());
  }

  Future<void> stop() async {
    _stopTimer();
    state = state.copyWith(running: false);
    await PrintForegroundService.stop();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _onTick() {
    _tick++;
    unawaited(pump());
    // Hitungan untuk layar monitoring tidak perlu sesering loop cetak.
    if (_tick % 5 == 0) unawaited(refreshMonitor());
  }

  // -------------------------------------------------------------- pump -----

  /// Aman dipanggil kapan saja (timer, event realtime, tombol manual).
  /// Panggilan yang tumpang tindih diabaikan.
  Future<void> pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      final printer = ref.read(printerServiceProvider);
      final printerCtl = ref.read(printerControllerProvider.notifier);

      // Jangan mengklaim job kalau printer belum siap. Job yang sudah diklaim
      // tapi tidak bisa dicetak akan terkunci di PRINTING selama 2 menit -
      // struk jadi tertahan lama tanpa alasan.
      if (!await printerCtl.ensureReady()) return;

      final jobs = await ref.read(printRepositoryProvider).claim(
            limit: Env.printClaimLimit,
          );
      if (jobs.isEmpty) return;

      var printerDown = false;
      for (final job in jobs) {
        if (printerDown) {
          // Sisa job yang terlanjur diklaim: kembalikan sekarang juga supaya
          // tidak menunggu timeout 2 menit di server.
          await _ack(job, printed: false, error: 'Printer terputus di tengah antrian');
          continue;
        }
        try {
          await printer.printReceipt(job.textBody);
          await _ack(job, printed: true);
          state = state.copyWith(lastSuccessAt: DateTime.now(), clearError: true);
        } on PrinterFailure catch (e) {
          printerDown = true;
          await _ack(job, printed: false, error: e.message);
          state = state.copyWith(lastError: e.message);
        }
      }
      await refreshMonitor();
    } on SessionExpiredFailure {
      await stop(); // kasir akan dilempar ke layar login
    } on AppFailure catch (e) {
      state = state.copyWith(lastError: e.message);
    } finally {
      _pumping = false;
    }
  }

  /// ACK **wajib** sampai ke server.
  ///
  /// ACK `PRINTED` yang hilang adalah satu-satunya cara struk bisa tercetak
  /// dua kali (job kembali ke `PENDING` setelah 2 menit), jadi pengiriman ulang
  /// di sini sengaja dibuat gigih. ACK bersifat idempoten - aman diulang.
  Future<void> _ack(PrintJob job, {required bool printed, String? error}) async {
    final repo = ref.read(printRepositoryProvider);
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await repo.ack(job.id, printed: printed, error: error);
        return;
      } on ApiFailure {
        return; // 404/400: server sudah memindahkan job, tidak perlu dipaksa
      } on SessionExpiredFailure {
        rethrow;
      } on AppFailure {
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    state = state.copyWith(
      lastError: 'ACK gagal terkirim untuk struk ${job.orderNo} - '
          'struk itu mungkin tercetak dua kali.',
    );
  }

  // ----------------------------------------------------------- monitor -----

  Future<void> refreshMonitor() async {
    try {
      final jobs = await ref.read(printRepositoryProvider).recent();
      final pending = jobs
          .where((j) =>
              j.status == PrintJobStatus.pending || j.status == PrintJobStatus.printing)
          .length;
      final failed = jobs.where((j) => j.status == PrintJobStatus.failed).length;
      state = state.copyWith(pending: pending, failed: failed);

      await PrintForegroundService.update(
        text: pending == 0 ? 'Tidak ada struk menunggu' : '$pending struk menunggu',
      );
    } on AppFailure {
      // Hitungan monitor bukan hal kritis - diamkan saja kalau jaringan sedang
      // bermasalah.
    }
  }

  /// 50 job terakhir untuk layar printer.
  Future<List<PrintJob>> recentJobs() =>
      ref.read(printRepositoryProvider).recent();

  Future<void> retryJob(String jobId) async {
    await ref.read(printRepositoryProvider).retry(jobId);
    await refreshMonitor();
    unawaited(pump());
  }

  Future<void> reprintOrder({
    required String orderId,
    required String verifiedBy,
  }) async {
    await ref.read(printRepositoryProvider).reprint(
          orderId: orderId,
          verifiedBy: verifiedBy,
        );
    await refreshMonitor();
    unawaited(pump());
  }
}

final printQueueProvider =
    NotifierProvider<PrintQueueController, PrintQueueState>(PrintQueueController.new);

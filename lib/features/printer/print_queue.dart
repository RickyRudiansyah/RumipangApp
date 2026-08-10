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

    // Sapuan pembayaran QRIS yang tertinggal, ~2 menit sekali.
    //
    // Menumpang loop ini karena inilah satu-satunya yang benar-benar berjalan
    // sepanjang hari (foreground service, tablet selalu menyala di kasir).
    // Servernya sendiri tidak punya penjadwal, dan webhook Midtrans terbukti
    // bisa tidak sampai - lihat lib/reconcile.ts di repo web.
    if (_tick % 30 == 0) unawaited(_reconcilePayments());
  }

  /// Selamatkan order QRIS yang uangnya sudah masuk tapi ordernya tidak pernah
  /// dibuat. Sengaja diam saat tidak ada apa-apa; hanya bersuara kalau benar-
  /// benar ada yang diselamatkan.
  Future<void> _reconcilePayments() async {
    try {
      final recovered = await ref.read(orderRepositoryProvider).reconcilePayments();
      if (recovered > 0) {
        state = state.copyWith(
          lastError: '$recovered pembayaran QRIS tertinggal berhasil '
              'diselamatkan - ordernya baru saja masuk.',
        );
      }
    } on AppFailure {
      // Jaring pengaman, bukan jalur utama. Kegagalannya tidak boleh
      // mengganggu antrian cetak.
    }
  }

  // -------------------------------------------------------------- pump -----

  /// Aman dipanggil kapan saja (timer, event realtime, tombol manual).
  /// Panggilan yang tumpang tindih diabaikan.
  Future<void> pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      final stations = ref.read(printerControllerProvider).configured;
      if (stations.isEmpty) return;

      // Satu printer: jalan lurus seperti dulu, tanpa biaya tambahan.
      if (stations.length == 1) {
        await _pumpStation(stations.first);
        await refreshMonitor();
        return;
      }

      // Dua printer, satu socket. Berpindah printer makan waktu dan kadang
      // gagal, jadi **jangan berpindah kalau tidak ada yang perlu dicetak** -
      // itu akan terjadi tiap 4 detik seumur hari. Daftar monitoring (yang
      // tidak mengunci apa pun) dipakai untuk tahu stasiun mana yang punya
      // antrian, baru stasiun itu yang disambangi.
      final waiting = await _stationsWithPendingJobs();
      for (final station in stations) {
        if (!waiting.contains(station)) continue;
        await _pumpStation(station);
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

  /// Stasiun yang punya job `PENDING` di server, tanpa menguncinya.
  Future<Set<PrintStation>> _stationsWithPendingJobs() async {
    final jobs = await ref.read(printRepositoryProvider).recent();
    return jobs
        .where((j) => j.status == PrintJobStatus.pending)
        .map((j) => j.station)
        .toSet();
  }

  /// Cetak seluruh antrian satu stasiun sampai habis, lalu selesai.
  ///
  /// Urutannya **sambung dulu, baru klaim**. Job yang diklaim tapi tidak bisa
  /// dicetak terkunci `PRINTING` selama 2 menit; dengan dua printer itu lebih
  /// mudah terjadi, karena "printer tersambung" belum tentu berarti printer
  /// yang benar. Semua ACK stasiun ini juga sudah tuntas sebelum fungsi ini
  /// kembali — pindah printer selagi ada job yang belum di-ACK adalah cara
  /// tercepat menuju struk dobel.
  Future<void> _pumpStation(PrintStation station) async {
    final printerCtl = ref.read(printerControllerProvider.notifier);
    if (!await printerCtl.useStation(station)) {
      final message = ref.read(printerControllerProvider).slot(station).message;
      if (message != null) {
        state = state.copyWith(lastError: 'Printer ${station.label}: $message');
      }
      return;
    }

    final printer = ref.read(printerServiceProvider);
    final store = ref.read(localStoreProvider);
    final jobs = await ref.read(printRepositoryProvider).claim(
          limit: Env.printClaimLimit,
          station: station,
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
        // Kertasnya sudah keluar di percobaan sebelumnya, hanya ACK-nya yang
        // belum sampai. Mencetaknya lagi = struk dobel.
        if (store.printedPendingAck.contains(job.id)) {
          await _ack(job, printed: true);
          continue;
        }

        await printer.printReceipt(job.textBody);
        // Dicatat SEBELUM ACK dikirim. Kalau aplikasi mati tepat di sini,
        // catatan inilah yang mencegah kertasnya keluar dua kali.
        await store.markPrinted(job.id);

        await _ack(job, printed: true);
        state = state.copyWith(lastSuccessAt: DateTime.now(), clearError: true);
      } on PrinterFailure catch (e) {
        printerDown = true;
        await _ack(job, printed: false, error: e.message);
        state = state.copyWith(lastError: 'Printer ${station.label}: ${e.message}');
      }
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
        await ref.read(localStoreProvider).clearPrinted(job.id);
        return;
      } on ApiFailure {
        // 404/400: server sudah memindahkan job sendiri, jadi urusannya
        // selesai - catatan lokalnya ikut dibuang.
        await ref.read(localStoreProvider).clearPrinted(job.id);
        return;
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

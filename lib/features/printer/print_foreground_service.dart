import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Foreground service supaya loop cetak tidak dimatikan sistem saat layar mati
/// (SPEC §8.3), plus notifikasi persisten "Printer aktif - N struk menunggu".
///
/// **Pembagian tugas yang penting:** isolate service ini TIDAK memegang socket
/// Bluetooth. Socket SPP hidup di isolate utama bersama plugin printer, jadi
/// service hanya bertugas (a) menahan proses tetap hidup dan (b) mengetuk
/// isolate utama tiap beberapa detik. Seluruh klaim-cetak-ACK tetap dikerjakan
/// [PrintQueueController] di isolate utama.
///
/// Kalau service gagal dijalankan (izin notifikasi ditolak, OEM agresif),
/// aplikasi tetap berfungsi: `Timer` di isolate utama jadi penggeraknya selama
/// layar menyala. Karena itu semua pemanggilan di sini dibungkus try/catch.
@pragma('vm:entry-point')
void printServiceCallback() {
  FlutterForegroundTask.setTaskHandler(_PrintKeepAliveHandler());
}

class _PrintKeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Ketukan ke isolate utama. Isinya tidak penting, kehadirannya yang penting.
    FlutterForegroundTask.sendDataToMain('pump');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class PrintForegroundService {
  const PrintForegroundService._();

  static bool _initialised = false;

  static void init() {
    if (_initialised) return;
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'rumipang_printer',
          channelName: 'Antrian Cetak Struk',
          channelDescription: 'Menjaga koneksi printer dan antrian struk tetap jalan.',
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(5000),
          autoRunOnBoot: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      _initialised = true;
    } catch (_) {
      // Bukan Android / plugin tidak tersedia - loop utama tetap jalan.
    }
  }

  static Future<void> start({required String text}) async {
    init();
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await update(text: text);
        return;
      }
      await FlutterForegroundTask.startService(
        serviceId: 4210,
        notificationTitle: 'Rumipang Kasir - printer aktif',
        notificationText: text,
        callback: printServiceCallback,
      );
    } catch (_) {
      // Diabaikan dengan sengaja: lihat catatan di atas kelas.
    }
  }

  static Future<void> update({required String text}) async {
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Rumipang Kasir - printer aktif',
        notificationText: text,
      );
    } catch (_) {
      // Diabaikan dengan sengaja.
    }
  }

  static Future<void> stop() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {
      // Diabaikan dengan sengaja.
    }
  }
}

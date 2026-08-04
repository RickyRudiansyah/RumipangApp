import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../core/failure.dart';
import 'receipt_bytes.dart';

/// Perangkat printer yang sudah ter-pair di Pengaturan Bluetooth Android.
///
/// Aplikasi **tidak melakukan pairing sendiri** - hanya memilih dari daftar
/// yang sudah dipasangkan (README handoff, "Yang perlu kamu siapkan sendiri").
class PairedPrinter {
  const PairedPrinter({required this.name, required this.mac});

  final String name;
  final String mac;
}

enum PrinterLinkState {
  /// Belum ada printer yang dipilih kasir.
  notSelected,
  disconnected,
  connecting,
  connected,

  /// Izin BLUETOOTH_CONNECT / BLUETOOTH_SCAN ditolak.
  permissionDenied,

  /// Bluetooth perangkat dimatikan.
  bluetoothOff,
}

class PrinterStatus {
  const PrinterStatus({
    required this.link,
    this.deviceName,
    this.deviceMac,
    this.message,
  });

  final PrinterLinkState link;
  final String? deviceName;
  final String? deviceMac;
  final String? message;

  bool get isConnected => link == PrinterLinkState.connected;
  bool get isBusy => link == PrinterLinkState.connecting;

  /// Indikator di kanan atas layar kasir: hijau = terhubung, merah = tidak.
  bool get isHealthy => isConnected;

  String get label => switch (link) {
        PrinterLinkState.connected => 'Terhubung',
        PrinterLinkState.connecting => 'Menyambungkan...',
        PrinterLinkState.disconnected => 'Terputus',
        PrinterLinkState.notSelected => 'Belum dipilih',
        PrinterLinkState.permissionDenied => 'Izin ditolak',
        PrinterLinkState.bluetoothOff => 'Bluetooth mati',
      };

  PrinterStatus copyWith({
    PrinterLinkState? link,
    String? deviceName,
    String? deviceMac,
    String? message,
    bool clearMessage = false,
  }) =>
      PrinterStatus(
        link: link ?? this.link,
        deviceName: deviceName ?? this.deviceName,
        deviceMac: deviceMac ?? this.deviceMac,
        message: clearMessage ? null : (message ?? this.message),
      );
}

/// Pembungkus tipis di atas `print_bluetooth_thermal`.
///
/// Printer Panda PRJ-R58D memakai **Bluetooth Classic (SPP)**, bukan BLE.
/// Jangan pernah menukar paket ini dengan `flutter_blue_plus` - printer tidak
/// akan terdeteksi sama sekali (SPEC §8.1).
class PrinterService {
  /// Hanya satu operasi tulis boleh jalan pada satu waktu. Socket SPP tidak
  /// aman dipakai dua penulis bersamaan - hasilnya struk saling menimpa.
  Future<void> _lock = Future.value();

  Future<bool> get bluetoothEnabled async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  Future<bool> get isConnected async {
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      return false;
    }
  }

  /// Minta izin runtime Android 12+/13. Manifest saja tidak cukup (SPEC §8.2).
  Future<bool> ensurePermissions() async {
    final results = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.notification,
    ].request();

    // Notifikasi hanya untuk foreground service - kalau ditolak, mencetak
    // masih boleh jalan.
    return (results[Permission.bluetoothConnect]?.isGranted ?? false) &&
        (results[Permission.bluetoothScan]?.isGranted ?? false);
  }

  Future<List<PairedPrinter>> pairedPrinters() async {
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    return devices
        // `macAdress` memang dieja begitu di paketnya (satu 'd').
        .map((d) => PairedPrinter(name: d.name, mac: d.macAdress))
        .toList();
  }

  Future<void> connect(String mac) async {
    final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
    if (!ok) {
      throw const PrinterFailure(
        'Gagal menyambung ke printer. Pastikan printer menyala dan sudah '
        'ter-pair di Pengaturan Bluetooth.',
      );
    }
  }

  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {
      // Sudah terputus duluan - tidak ada yang perlu dilakukan.
    }
  }

  /// Cetak satu struk. Melempar [PrinterFailure] kalau gagal, supaya pemanggil
  /// bisa mengirim ACK `FAILED` dengan pesan yang berguna.
  Future<void> printReceipt(String textBody) =>
      _write(ReceiptBytes.receipt(textBody));

  Future<void> printTestPage(String deviceName) =>
      _write(ReceiptBytes.testPage(deviceName: deviceName));

  Future<void> _write(List<int> bytes) {
    // Antrikan di belakang tulisan yang sedang berjalan.
    final result = _lock.then((_) => _writeNow(bytes));
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _writeNow(List<int> bytes) async {
    if (!await isConnected) {
      throw const PrinterFailure('Printer tidak terhubung');
    }
    final bool ok;
    try {
      ok = await PrintBluetoothThermal.writeBytes(bytes);
    } catch (e) {
      throw PrinterFailure('Gagal mengirim ke printer: $e');
    }
    if (!ok) {
      throw const PrinterFailure(
        'Printer menolak data. Cek kertas dan sambungan Bluetooth.',
      );
    }
  }
}

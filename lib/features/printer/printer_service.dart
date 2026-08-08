import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../core/failure.dart';
import '../../models/enums.dart';
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

/// Satu printer beserta kondisinya. Ada satu per [PrintStation].
class PrinterSlot {
  const PrinterSlot({
    required this.link,
    this.deviceName,
    this.deviceMac,
    this.message,
  });

  static const empty = PrinterSlot(link: PrinterLinkState.notSelected);

  final PrinterLinkState link;
  final String? deviceName;
  final String? deviceMac;
  final String? message;

  bool get isSelected => deviceMac != null;
  bool get isConnected => link == PrinterLinkState.connected;
  bool get isBusy => link == PrinterLinkState.connecting;

  String get label => switch (link) {
        PrinterLinkState.connected => 'Terhubung',
        PrinterLinkState.connecting => 'Menyambungkan...',
        PrinterLinkState.disconnected => 'Terputus',
        PrinterLinkState.notSelected => 'Belum dipilih',
        PrinterLinkState.permissionDenied => 'Izin ditolak',
        PrinterLinkState.bluetoothOff => 'Bluetooth mati',
      };

  PrinterSlot copyWith({
    PrinterLinkState? link,
    String? deviceName,
    String? deviceMac,
    String? message,
    bool clearMessage = false,
  }) =>
      PrinterSlot(
        link: link ?? this.link,
        deviceName: deviceName ?? this.deviceName,
        deviceMac: deviceMac ?? this.deviceMac,
        message: clearMessage ? null : (message ?? this.message),
      );
}

/// Kondisi seluruh printer.
///
/// **Hanya satu yang benar-benar tersambung pada satu waktu.**
/// `print_bluetooth_thermal` memegang satu socket SPP global, jadi mencetak ke
/// printer dapur berarti memutus printer kasir lebih dulu. [activeStation]
/// menandai siapa yang sedang memegang socket itu.
class PrinterStatus {
  const PrinterStatus({this.slots = const {}, this.activeStation});

  final Map<PrintStation, PrinterSlot> slots;
  final PrintStation? activeStation;

  PrinterSlot slot(PrintStation station) => slots[station] ?? PrinterSlot.empty;

  /// Stasiun yang sudah dipilihkan printer — hanya ini yang ikut loop cetak.
  List<PrintStation> get configured =>
      PrintStation.values.where((s) => slot(s).isSelected).toList();

  bool get anySelected => configured.isNotEmpty;

  /// Indikator di kanan atas layar kasir: hijau kalau **semua** printer yang
  /// sudah dipilih sedang tersambung, atau — karena socketnya bergantian —
  /// setidaknya satu sedang aktif dan tidak ada yang bermasalah.
  bool get isHealthy {
    final selected = configured;
    if (selected.isEmpty) return false;
    return selected.every((s) {
      final st = slot(s);
      return st.isConnected ||
          st.link == PrinterLinkState.disconnected; // giliran, bukan kerusakan
    });
  }

  /// Printer yang sudah dipilih tapi benar-benar bermasalah (izin/Bluetooth).
  List<PrintStation> get broken => configured
      .where((s) =>
          slot(s).link == PrinterLinkState.permissionDenied ||
          slot(s).link == PrinterLinkState.bluetoothOff)
      .toList();

  String get label {
    final selected = configured;
    if (selected.isEmpty) return 'Belum dipilih';
    if (broken.isNotEmpty) return slot(broken.first).label;
    if (selected.length == 1) return slot(selected.first).label;
    final active = activeStation;
    return active == null ? 'Siap' : 'Aktif: ${active.label}';
  }

  PrinterStatus copyWith({
    Map<PrintStation, PrinterSlot>? slots,
    PrintStation? activeStation,
    bool clearActive = false,
  }) =>
      PrinterStatus(
        slots: slots ?? this.slots,
        activeStation: clearActive ? null : (activeStation ?? this.activeStation),
      );

  PrinterStatus withSlot(PrintStation station, PrinterSlot value) =>
      copyWith(slots: {...slots, station: value});
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

  /// MAC yang sedang dipegang socket, kalau ada.
  ///
  /// `PrintBluetoothThermal.connectionStatus` hanya menjawab "tersambung atau
  /// tidak" - ia tidak tahu **ke printer yang mana**. Padahal dengan dua
  /// printer, jawaban "tersambung" bisa berarti tersambung ke printer yang
  /// salah, dan struk dapur keluar di kasir. Jadi kita catat sendiri.
  String? get connectedMac => _connectedMac;
  String? _connectedMac;

  Future<void> connect(String mac) async {
    // Socketnya cuma satu. Pindah printer berarti melepas yang lama dulu -
    // tanpa ini, `connect` ke MAC kedua bisa dijawab "sukses" oleh paketnya
    // sementara socket yang hidup masih milik printer pertama.
    if (_connectedMac != null && _connectedMac != mac) {
      await disconnect();
      // Beri jeda; menutup lalu langsung membuka SPP di Android sering gagal
      // pada percobaan pertama.
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
    if (!ok) {
      _connectedMac = null;
      throw const PrinterFailure(
        'Gagal menyambung ke printer. Pastikan printer menyala dan sudah '
        'ter-pair di Pengaturan Bluetooth.',
      );
    }
    _connectedMac = mac;
  }

  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {
      // Sudah terputus duluan - tidak ada yang perlu dilakukan.
    }
    _connectedMac = null;
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

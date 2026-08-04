import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../core/providers.dart';
import 'printer_service.dart';

final printerServiceProvider = Provider<PrinterService>((ref) => PrinterService());

/// Koneksi ke printer: pilih perangkat, sambung, tes cetak.
///
/// MAC printer disimpan lokal supaya kasir tidak perlu memilih ulang tiap pagi
/// (SPEC §8.5).
class PrinterController extends Notifier<PrinterStatus> {
  PrinterService get _service => ref.read(printerServiceProvider);

  @override
  PrinterStatus build() {
    final store = ref.read(localStoreProvider);
    final mac = store.printerMac;
    return PrinterStatus(
      link: mac == null ? PrinterLinkState.notSelected : PrinterLinkState.disconnected,
      deviceMac: mac,
      deviceName: store.printerName,
    );
  }

  Future<List<PairedPrinter>> listDevices() async {
    if (!await _service.ensurePermissions()) {
      state = state.copyWith(
        link: PrinterLinkState.permissionDenied,
        message: 'Izin Bluetooth ditolak. Buka Pengaturan > Aplikasi > '
            'Rumipang Kasir > Izin, lalu aktifkan "Perangkat di sekitar".',
      );
      return const [];
    }
    if (!await _service.bluetoothEnabled) {
      state = state.copyWith(
        link: PrinterLinkState.bluetoothOff,
        message: 'Bluetooth tablet sedang mati.',
      );
      return const [];
    }
    try {
      return await _service.pairedPrinters();
    } catch (e) {
      state = state.copyWith(message: 'Gagal membaca daftar perangkat: $e');
      return const [];
    }
  }

  Future<void> select(PairedPrinter printer) async {
    await ref.read(localStoreProvider).savePrinter(
          mac: printer.mac,
          name: printer.name,
        );
    state = PrinterStatus(
      link: PrinterLinkState.disconnected,
      deviceMac: printer.mac,
      deviceName: printer.name,
    );
    await connect();
  }

  Future<void> forget() async {
    await _service.disconnect();
    await ref.read(localStoreProvider).clearPrinter();
    state = const PrinterStatus(link: PrinterLinkState.notSelected);
  }

  /// Sambungkan ke printer yang tersimpan. Mengembalikan `true` kalau siap
  /// menerima byte.
  Future<bool> connect() async {
    final mac = state.deviceMac;
    if (mac == null) {
      state = state.copyWith(link: PrinterLinkState.notSelected);
      return false;
    }
    if (state.isBusy) return false;

    state = state.copyWith(link: PrinterLinkState.connecting, clearMessage: true);
    try {
      if (!await _service.ensurePermissions()) {
        state = state.copyWith(
          link: PrinterLinkState.permissionDenied,
          message: 'Izin Bluetooth belum diberikan.',
        );
        return false;
      }
      if (!await _service.bluetoothEnabled) {
        state = state.copyWith(
          link: PrinterLinkState.bluetoothOff,
          message: 'Nyalakan Bluetooth tablet.',
        );
        return false;
      }

      await _service.connect(mac);
      state = state.copyWith(link: PrinterLinkState.connected, clearMessage: true);
      return true;
    } on PrinterFailure catch (e) {
      state = state.copyWith(link: PrinterLinkState.disconnected, message: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
        link: PrinterLinkState.disconnected,
        message: 'Gagal menyambung: $e',
      );
      return false;
    }
  }

  Future<void> disconnect() async {
    await _service.disconnect();
    state = state.copyWith(link: PrinterLinkState.disconnected, clearMessage: true);
  }

  /// Dipakai loop antrian sebelum mengklaim job: pastikan printer benar-benar
  /// tersambung, sambungkan ulang diam-diam kalau perlu.
  Future<bool> ensureReady() async {
    if (state.deviceMac == null) return false;
    if (await _service.isConnected) {
      if (!state.isConnected) {
        state = state.copyWith(link: PrinterLinkState.connected, clearMessage: true);
      }
      return true;
    }
    if (state.isConnected) {
      // Socket putus tanpa pemberitahuan (printer dimatikan, keluar jangkauan).
      state = state.copyWith(link: PrinterLinkState.disconnected);
    }
    return connect();
  }

  /// Struk contoh - tidak menyentuh antrian server sama sekali.
  Future<void> testPrint() async {
    if (!await ensureReady()) {
      throw PrinterFailure(state.message ?? 'Printer tidak terhubung');
    }
    await _service.printTestPage(state.deviceName ?? 'Printer');
  }
}

final printerControllerProvider =
    NotifierProvider<PrinterController, PrinterStatus>(PrinterController.new);

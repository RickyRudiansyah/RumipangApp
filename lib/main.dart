import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'core/local_store.dart';
import 'core/providers.dart';
import 'features/printer/print_foreground_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Semua orientasi diizinkan.
  //
  // Dulu dikunci landscape karena tablet kasir dipasang mendatar di meja
  // (SPEC §2). Sekarang aplikasi juga dipakai di HP, dan mengunci landscape
  // di layar 6" membuat semuanya sempit tanpa alasan. Tata letak menyesuaikan
  // lebar layar lewat [ScreenSize], bukan lewat kunci orientasi.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Format "03/08/2026, 23.39" dan "Rp 8.000" butuh data lokal id_ID.
  await initializeDateFormatting('id_ID');

  // Sesi disimpan otomatis di penyimpanan aman bawaan supabase_flutter dan
  // token disegarkan sendiri, jadi kasir tidak perlu login ulang tiap pagi
  // (SPEC §5).
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  // Jalur komunikasi antara isolate foreground service dan isolate utama.
  // Harus dipanggil sebelum runApp.
  FlutterForegroundTask.initCommunicationPort();
  PrintForegroundService.init();

  final localStore = await LocalStore.open();

  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(localStore)],
      child: const RumipangKasirApp(),
    ),
  );
}

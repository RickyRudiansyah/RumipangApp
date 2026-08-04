import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/login_page.dart';
import 'features/auth/staff_provider.dart';
import 'features/settings/theme_provider.dart';
import 'features/shell/shell_page.dart';
import 'shared/theme.dart';
import 'shared/widgets.dart';

class RumipangKasirApp extends ConsumerWidget {
  const RumipangKasirApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tema event diambil dari server supaya aplikasi dan web berganti bersamaan.
    final preset = ref.watch(activeThemeProvider);

    return MaterialApp(
      title: 'Rumipang Kasir',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(preset),
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Tablet 10,4" 2K: skala teks sistem yang ekstrem bisa merusak layout
        // master-detail, jadi dibatasi.
        final scale = MediaQuery.textScalerOf(context).clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.2,
        );
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scale),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const _AuthGate(),
    );
  }
}

/// Menentukan layar mana yang tampil berdasarkan sesi staff.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(staffProvider);

    return staff.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: ErrorView(
          message: error.toString().replaceFirst('Exception: ', ''),
          onRetry: () => ref.invalidate(staffProvider),
        ),
      ),
      data: (identity) => identity == null ? const LoginPage() : const ShellPage(),
    );
  }
}

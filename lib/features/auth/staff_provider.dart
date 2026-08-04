import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../models/json.dart';
import '../../models/staff.dart';

/// Dipakai untuk menyalakan ulang [staffProvider] saat sesi berubah.
final authChangeProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

class StaffNotifier extends AsyncNotifier<StaffIdentity?> {
  @override
  Future<StaffIdentity?> build() async {
    // Bangun ulang tiap kali status auth berubah (login, logout, refresh).
    ref.watch(authChangeProvider);
    return _load();
  }

  Future<StaffIdentity?> _load() async {
    final supabase = ref.read(supabaseProvider);
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final row = await supabase
        .from('staff_users')
        .select('id, role, name, is_active')
        .eq('id', user.id)
        .maybeSingle();

    if (row == null) {
      // User Supabase yang bukan staff sama sekali.
      await supabase.auth.signOut();
      return null;
    }

    final staff = StaffIdentity.fromJson(asMap(row), email: user.email);

    // SPEC §12: staff yang dinonaktifkan harus langsung terkunci - bukan hanya
    // saat login, tapi juga tiap aplikasi dibuka lagi.
    if (!staff.canUseApp) {
      await supabase.auth.signOut();
      return null;
    }
    return staff;
  }

  /// Login + pemeriksaan staff dalam satu langkah.
  /// Melempar [Exception] dengan pesan siap tampil kalau gagal.
  Future<void> signIn({required String email, required String password}) async {
    // Sengaja TIDAK menyetel state ke loading di sini. Kalau disetel, gerbang
    // auth akan mengganti LoginPage dengan spinner seluruh layar, widget login
    // dibuang, dan pesan error tidak pernah sempat tampil. Spinner tombol di
    // LoginPage sudah cukup.
    final supabase = ref.read(supabaseProvider);
    try {
      final res = await supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (res.session == null) throw Exception('Login gagal');

      final staff = await _load();
      if (staff == null) {
        // Login Supabase berhasil tapi barisnya tidak terbaca. Dua sebab yang
        // mungkin: memang bukan staff, atau RLS `staff_users` tidak
        // mengizinkan pengguna membaca barisnya sendiri.
        throw Exception(
          'Akun ini bukan staff aktif Rumipang.\n'
          'Kalau yakin sudah terdaftar, periksa is_active dan kebijakan RLS '
          'SELECT pada tabel staff_users.',
        );
      }
      state = AsyncValue.data(staff);
    } catch (error) {
      try {
        await supabase.auth.signOut();
      } catch (_) {
        // Abaikan: yang penting error aslinya sampai ke layar login.
      }
      // Tetap di layar login (bukan layar error) - kasir tinggal coba lagi.
      state = const AsyncValue.data(null);
      throw _readable(error);
    }
  }

  Future<void> signOut() async {
    await ref.read(supabaseProvider).auth.signOut();
    state = const AsyncValue.data(null);
  }

  /// Dipanggil saat aplikasi kembali ke foreground.
  Future<void> revalidate() async {
    try {
      final staff = await _load();
      state = AsyncValue.data(staff);
    } catch (_) {
      // Jaringan mati saat resume -> pertahankan sesi yang ada, jangan
      // mengunci kasir hanya karena wifi sempat putus.
    }
  }

  Object _readable(Object error) {
    if (error is AuthException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('invalid login')) return Exception('Email atau kata sandi salah');
      if (msg.contains('network')) return Exception('Tidak ada koneksi internet');
      return Exception(error.message);
    }
    return error;
  }
}

final staffProvider =
    AsyncNotifierProvider<StaffNotifier, StaffIdentity?>(StaffNotifier.new);

/// Ringkasan untuk UI: sudah login sebagai staff aktif atau belum.
final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(staffProvider).valueOrNull != null,
);

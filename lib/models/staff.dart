import 'json.dart';

/// Baris `staff_users`. Hanya role `cashier` dan `owner` yang boleh memakai
/// aplikasi ini.
///
/// Role `koki` **masih ada** di constraint tabel dan di web, tapi dapur sudah
/// dipensiunkan (BACKEND-ADDITIONS.md §7). Constraint-nya sengaja tidak dihapus
/// supaya baris staff lama tetap valid; akun koki hanya tidak bisa masuk ke
/// aplikasi kasir - dan memang tidak perlu.
class StaffIdentity {
  const StaffIdentity({
    required this.id,
    required this.role,
    required this.name,
    required this.isActive,
    this.email,
  });

  factory StaffIdentity.fromJson(Map<String, dynamic> json, {String? email}) =>
      StaffIdentity(
        id: asString(json['id']),
        role: asString(json['role']).toLowerCase(),
        name: asString(json['name'], 'Kasir'),
        isActive: asBool(json['is_active'], true),
        email: email ?? asStringOrNull(json['email']),
      );

  final String id;
  final String role;
  final String name;
  final bool isActive;
  final String? email;

  bool get isOwner => role == 'owner';
  bool get isCashier => role == 'cashier';

  /// Boleh memakai aplikasi kasir.
  ///
  /// **Semua role aktif boleh masuk** - yang membedakan hanya apa yang mereka
  /// lihat di dalamnya (`isOwner` menjaga HPP, laba, dan kelola karyawan).
  ///
  /// Dulu di sini tertulis `isOwner || isCashier`, dan itu jadi ranjau begitu
  /// owner boleh membuat role sendiri: mengubah peran seseorang jadi "koki"
  /// diam-diam mengunci dia keluar dari aplikasi, tanpa pesan yang menjelaskan
  /// kenapa.
  bool get canUseApp => isActive;
}

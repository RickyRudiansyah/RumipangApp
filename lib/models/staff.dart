import 'json.dart';

/// Baris `staff_users`. Hanya role `cashier` dan `owner` yang berlaku
/// (role `koki` sudah dihapus di backend - API-CONTRACT §1).
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

  /// Role yang diizinkan memakai aplikasi kasir.
  bool get canUseApp => isActive && (isOwner || isCashier);
}

import 'json.dart';

/// Karyawan yang berhak mengambil jatah makan.
///
/// Berbeda dengan [StaffIdentity] yang mewakili *siapa yang sedang login*,
/// ini hanya baris daftar untuk dipilih.
class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.role,
    this.email,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        id: asString(json['id']),
        name: asString(json['name'], 'Karyawan'),
        role: asString(json['role']).toLowerCase(),
        email: asStringOrNull(json['email']),
      );

  final String id;
  final String name;
  final String role;
  final String? email;
}

/// Satu pencatatan jatah makan.
///
/// Aturan **1 kali per karyawan per hari** ditegakkan server lewat
/// `unique (staff_id, meal_date)`; aplikasi hanya menampilkan pesan 409 yang
/// dikembalikan server. Pengecekan di aplikasi saja tidak cukup - dua tablet
/// bisa mencatat bersamaan (BACKEND-ADDITIONS.md §5).
class StaffMeal {
  const StaffMeal({
    required this.id,
    required this.staffId,
    required this.mealDate,
    required this.costSnapshot,
    this.staffName,
    this.menuItemId,
    this.menuItemName,
    this.note,
  });

  factory StaffMeal.fromJson(Map<String, dynamic> json) => StaffMeal(
        id: asString(json['id']),
        staffId: asString(json['staff_id']),
        mealDate: asDateOr(json['meal_date'], DateTime.now()),
        costSnapshot: asInt(json['cost_snapshot']),
        staffName: asStringOrNull(json['staff_name']),
        menuItemId: asStringOrNull(json['menu_item_id']),
        menuItemName: asStringOrNull(json['menu_item_name']),
        note: asStringOrNull(json['note']),
      );

  final String id;
  final String staffId;
  final DateTime mealDate;

  /// HPP menu **saat dicatat**. Sengaja snapshot: memperbarui HPP hari ini
  /// tidak boleh mengubah biaya jatah makan bulan lalu.
  final int costSnapshot;

  final String? staffName;
  final String? menuItemId;
  final String? menuItemName;
  final String? note;

  String get menuLabel => menuItemName ?? 'Tidak dicatat';
}

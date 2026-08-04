/// Pembantu parsing yang tahan bentuk data tak terduga.
///
/// Model ditulis tangan (bukan freezed/json_serializable seperti disebut
/// SPEC §10) supaya proyek ini **compile tanpa langkah build_runner**.
/// Keamanan tipenya sama; yang hilang hanya boilerplate generator.
library;

int asInt(Object? v, [int fallback = 0]) => switch (v) {
      final int i => i,
      final num n => n.toInt(),
      final String s => int.tryParse(s) ?? fallback,
      _ => fallback,
    };

int? asIntOrNull(Object? v) => v == null ? null : asInt(v);

String asString(Object? v, [String fallback = '']) =>
    v is String ? v : (v == null ? fallback : v.toString());

String? asStringOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

bool asBool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

/// Server mengirim ISO-8601 UTC. Selalu dikonversi ke waktu perangkat (WIB)
/// supaya jam di layar sama dengan jam di dinding warung.
DateTime? asDate(Object? v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v)?.toLocal();
}

DateTime asDateOr(Object? v, DateTime fallback) => asDate(v) ?? fallback;

Map<String, dynamic> asMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

Map<String, dynamic>? asMapOrNull(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

List<T> asList<T>(Object? v, T Function(Map<String, dynamic>) parse) {
  if (v is! List) return const [];
  return v.whereType<Map>().map((e) => parse(Map<String, dynamic>.from(e))).toList();
}

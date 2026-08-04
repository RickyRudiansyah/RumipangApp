# Dokumen rujukan

Salin empat berkas berikut ke folder ini dari paket serah-terima repo web
(`docs/flutter-handoff/`). Semuanya sudah dipakai sebagai dasar implementasi;
disimpan di sini supaya repo ini tetap mandiri.

| Berkas | Isi | Asal di repo web |
|---|---|---|
| `SPEC.md` | Spesifikasi aplikasi: ruang lingkup, perangkat, arsitektur, layar, printer, tahapan | `docs/FLUTTER-KASIR-APP.md` |
| `API-CONTRACT.md` | Seluruh endpoint, aturan bisnis, penanganan error | `docs/flutter-handoff/API-CONTRACT.md` |
| `PRINTER.md` | Kontrak antrian cetak & siklus hidup job | `docs/BLUETOOTH-PRINTER.md` |
| `api-samples.json` | Contoh respons asli server, dasar pembuatan model | `docs/flutter-handoff/api-samples.json` |

`BACKEND-PREREQ.md` **tidak** disalin ke sini — isinya pekerjaan di repo web
(Next.js), bukan di repo ini. Tapi pekerjaan itu **memblokir** aplikasi ini:
selama header `Authorization: Bearer` belum diterima backend, seluruh endpoint
staff membalas 401.

## Rujukan silang ke kode

| Bagian dokumen | Diterapkan di |
|---|---|
| SPEC §5 Autentikasi | [lib/features/auth/staff_provider.dart](../lib/features/auth/staff_provider.dart), [lib/core/api_client.dart](../lib/core/api_client.dart) |
| SPEC §7 Realtime | [lib/core/realtime_service.dart](../lib/core/realtime_service.dart) |
| SPEC §8 Modul printer | [lib/features/printer/](../lib/features/printer/) |
| SPEC §9 Jaringan putus | [lib/features/orders/pending_actions.dart](../lib/features/orders/pending_actions.dart), [lib/core/local_store.dart](../lib/core/local_store.dart) |
| SPEC §11 Rancangan layar | [lib/features/shell/shell_page.dart](../lib/features/shell/shell_page.dart) dan halaman di `lib/features/*` |
| API-CONTRACT §3 Aturan tombol | [lib/models/order.dart](../lib/models/order.dart) (`canMarkPaid`, `canCancel`, `isSettled`) |
| API-CONTRACT §4 Siklus job | [lib/features/printer/print_queue.dart](../lib/features/printer/print_queue.dart) |

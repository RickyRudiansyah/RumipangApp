# Rumipang Kasir — Aplikasi Kasir + Dashboard Admin

Aplikasi Android untuk **ADVAN Tab VX Lite** (10,4" · Android 13) yang
menggantikan dashboard kasir web, menjadi jembatan ke printer termal
**Panda PRJ-R58D** (58 mm, Bluetooth Classic/SPP), sekaligus dashboard admin:
HPP, stok bahan, laporan penjualan, jatah makan karyawan, dan tema event.

---

## Status: apa yang sudah jalan

### ✅ `Authorization: Bearer` sudah diterima backend

Dulu ini blocker nomor satu — API Next.js hanya mengenal cookie sesi sementara
aplikasi memegang JWT. **Sudah tidak lagi.** Terbukti pada 5 Agustus 2026:
mengubah harga menu (`PUT /api/menu/[id]`) dan mengunggah foto
(`POST /api/upload`) berhasil dari tablet, dan keduanya endpoint ber-auth staff.

Artinya sisa pekerjaan backend murni **"endpoint-nya belum dibuat"**, bukan
soal autentikasi.

### ❌ Yang masih 404

Layar **Stok, Laporan, Jatah, dan Tema** memanggil endpoint yang belum ada dan
menampilkan "Endpoint ini belum tersedia di server". Seluruh daftarnya, beserta
DDL tabel dan contoh JSON, ada di
[docs/BACKEND-ADDITIONS.md](docs/BACKEND-ADDITIONS.md).

Layar **Kasir, Order, Riwayat, Printer, dan Menu** sudah bisa dipakai.

---

## ⚠️ Service role key sempat tersebar

`SUPABASE_SERVICE_ROLE_KEY` mem-bypass seluruh RLS. Kunci itu dikirim lewat
percakapan biasa, jadi anggap sudah bocor: **rotasi di Supabase Dashboard →
Project Settings → API → Rotate**. Kunci itu tidak ada — dan tidak boleh ada —
di repo ini.

Yang tertanam di aplikasi hanya **anon key**, dan itu memang dirancang untuk
dipasang di klien (keamanannya dijaga RLS).

---

## Menjalankan

Scaffolding native (`android/`) **sudah dibuat** dan ikut tersimpan di repo —
`bootstrap.ps1` hanya perlu dijalankan sekali di mesin baru yang belum punya
folder itu.

```powershell
flutter devices                    # tablet harus muncul (USB debugging aktif)
flutter run --release
```

### Toolchain yang terverifikasi

| Komponen | Versi |
|---|---|
| Flutter | 3.44.8 (Dart 3.12.2) |
| JDK | Adoptium 21 — setel dengan `flutter config --jdk-dir` |
| Gradle · AGP · Kotlin | 9.1.0 · 9.0.1 · 2.3.20 |
| Android SDK | `compileSdk 37` (paket `platforms;android-37.0`), `minSdk 26`, `targetSdk 34` |

Tiga hal yang memakan waktu paling lama saat menyiapkan mesin baru, supaya
tidak diulangi:

- **`compileSdk` harus 37**, dan paketnya bernama `platforms;android-37.0` —
  `platforms;android-37` polos tidak pernah dirilis Google. AGP di bawah 9
  tidak mengenal penomoran minor ini dan akan gagal mencarinya selamanya.
- **`kotlin.incremental=false`** di [gradle.properties](android/gradle.properties)
  bukan hiasan. Tanpa itu KGP 2.3.20 gagal menutup cache `.tab` di Windows dan
  build berhenti dengan `Could not close incremental caches`.
- **JDK 21, bukan JDK bawaan Android Studio.** JBR bawaan bisa saja tidak
  lengkap (tanpa `java.exe`), dan `java` di PATH sering masih versi 8/11.

> **Emulator tidak punya Bluetooth Classic.** Modul printer mustahil diuji di
> emulator — siapkan tablet fisik sejak awal.

### Build APK

Kredensial default sudah tertanam di [env.dart](lib/core/env.dart). Untuk
menimpanya tanpa mengubah kode:

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://rumipang.vercel.app \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbG...
```

---

## Struktur

```
lib/
├── main.dart                    # init Supabase, locale id_ID, orientasi landscape
├── app.dart                     # MaterialApp + gerbang auth + tema dari server
├── core/
│   ├── env.dart                 # base URL + anon key (bisa ditimpa --dart-define)
│   ├── api_client.dart          # REST + Bearer + refresh 401 + retry
│   ├── failure.dart             # ApiFailure / NetworkFailure / SessionExpired / Printer
│   ├── local_store.dart         # MAC printer, cache board, antrian aksi tertunda
│   ├── providers.dart           # dependency injection
│   └── realtime_service.dart    # websocket + polling cadangan 15 dtk
├── models/                      # ditulis tangan, tanpa build_runner
├── data/                        # repository per domain
├── features/
│   ├── auth/                    # login + guard role staff
│   ├── orders/                  # board kasir + antrian aksi offline
│   ├── new_order/               # POS manual
│   ├── history/                 # riwayat + cetak ulang
│   ├── admin/                   # menu & HPP: kategori, harga, margin, foto
│   ├── inventory/               # stok bahan baku + alert ambang
│   ├── reports/                 # menu terlaris & kurang laku, laba kotor
│   ├── meals/                   # jatah makan karyawan (1x per orang per hari)
│   ├── settings/                # tema event, dipakai bersama web
│   ├── printer/                 # SPP, loop klaim-cetak-ACK, foreground service
│   └── shell/                   # NavigationRail + siklus hidup layanan latar
└── shared/                      # tema, preset event, format rupiah/tanggal, widget umum
```

Urutan tab di NavigationRail: Kasir · Order · Riwayat · Menu · Stok · Laporan ·
Jatah · Tema · Printer. `_printerTabIndex` di
[shell_page.dart](lib/features/shell/shell_page.dart) harus ikut diperbarui
kalau urutannya berubah.

---

## Keputusan teknis yang menyimpang dari SPEC

| Hal | SPEC | Di sini | Alasan |
|---|---|---|---|
| Model | freezed + json_serializable | ditulis tangan | Proyek compile tanpa langkah `build_runner`. Keamanan tipe sama, hanya boilerplate yang bertambah. |
| Alur dapur | layar dapur + ETA + mulai proses + sudah diantar | **dihapus** | Keputusan pemilik: order cukup masuk, tanpa langkah proses manual. Server menyetel `status = SERVED` saat order dibuat (BACKEND-ADDITIONS.md §7). |
| HPP | — | input manual per menu | Keputusan pemilik. Tanpa resep bahan baku, jadi **stok tidak berkurang otomatis** saat ada penjualan. |
| Pemilih meja di POS | dropdown | dialog daftar | `DropdownButtonFormField` berganti nama parameter antar versi Flutter; dialog juga lebih ramah untuk sentuhan. |

---

## Dashboard admin

Lima layar tambahan, semuanya butuh endpoint di
[docs/BACKEND-ADDITIONS.md](docs/BACKEND-ADDITIONS.md).

| Layar | Isi |
|---|---|
| **Menu** | Dikelompokkan per kategori. Tambah menu & kategori, ubah harga, isi HPP, margin otomatis, foto menu (ambil → potong/putar → unggah). Menu yang dijual di bawah modal ditandai merah. |
| **Stok** | Bahan baku + alert saat menyentuh ambang (default 20, bisa beda per bahan). Perubahan stok lewat "Sesuaikan" beserta alasannya, tidak pernah menimpa angka langsung. |
| **Laporan** | Menu terlaris & kurang laku, omzet, total HPP, laba kotor. Rentang hari ini / 7 hari / 30 hari. |
| **Jatah** | Jatah makan karyawan, satu kali per orang per hari. |
| **Tema** | Tema event (Normal, Natal, Ramadan, Kemerdekaan, Imlek). Berlaku untuk aplikasi **dan** web. |

Empat keputusan yang mudah dirusak tanpa sengaja:

- **Snapshot biaya, bukan referensi.** `order_items.cost_price_snapshot` dan
  `staff_meals.cost_snapshot` menyimpan HPP **saat transaksi terjadi**. Tanpa
  itu, menaikkan HPP hari ini akan mengubah laba bulan lalu.
- **Aturan 1x sehari ada di database,** lewat `unique (staff_id, meal_date)`.
  Pemeriksaan di aplikasi hanya untuk menonaktifkan tombol lebih awal — dua
  tablet bisa menekan bersamaan dan keduanya lolos.
- **Warna status tidak ikut tema.** Hijau lunas dan merah belum-bayar tetap
  sama di tema apa pun; tema Natal yang membuat semuanya merah akan
  menenggelamkan penanda belum-bayar.
- **`PUT /api/menu/[id]` mengganti seluruh baris.** Setiap field yang boleh
  disunting **wajib** ikut dikirim, termasuk `image_url` dan `category_id` yang
  tidak berubah. Parameternya sengaja `required` di
  [menu_admin_repository.dart](lib/data/menu_admin_repository.dart) supaya
  kelalaian ini gagal saat compile, bukan menghapus foto menu diam-diam di
  server. Ini pernah terjadi.

### Status endpoint

Layar **Kasir, Order, Riwayat, Printer** memakai endpoint yang sudah ada dan
berfungsi. Layar **Stok, Laporan, Jatah, Tema** memanggil endpoint yang
**belum dibuat** — semuanya menampilkan "Endpoint ini belum tersedia di
server" (HTTP 404) sampai [docs/BACKEND-ADDITIONS.md](docs/BACKEND-ADDITIONS.md)
dikerjakan. Layar **Menu** berada di antaranya: sebagian besar sudah jalan,
tapi HPP dan kategori baru butuh tambahan di web.

---

## Aturan yang tidak boleh dilanggar saat mengubah kode

Semuanya sudah diterapkan; ini catatan supaya tidak tidak sengaja dirusak nanti.

1. **Setiap perubahan status order lewat REST API.** Jangan pernah update tabel
   Supabase langsung — logika bisnisnya (mis. `mark-paid` yang membuat job cetak)
   ada di server. Supabase SDK di sini hanya untuk login dan realtime.

2. **`status` dan `payment_status` (uang) terpisah.** Order bisa `SERVED` tapi
   masih `UNPAID`. Jangan menyimpulkan salah satu dari yang lain — meski alur
   dapur sudah dihapus, pengarsipan tetap mensyaratkan keduanya
   ([order.dart](lib/models/order.dart) `isSettled`).

3. **Jangan optimistic update untuk uang.** Baru tandai lunas setelah server
   membalas 200. Saat jaringan mati, verifikasi masuk antrian lokal dan order
   **tetap tampil belum lunas** sampai server mengonfirmasi.

4. **ACK wajib sampai.** Job `PRINTING` yang tidak di-ACK dalam 2 menit kembali
   ke `PENDING` dan struknya tercetak dua kali. Pengiriman ACK sengaja diulang
   gigih di [print_queue.dart](lib/features/printer/print_queue.dart).

5. **Jangan klaim job kalau printer belum tersambung.** Job yang diklaim tapi
   tidak bisa dicetak terkunci 2 menit tanpa alasan.

6. **Bluetooth Classic (SPP), bukan BLE.** Jangan ganti
   `print_bluetooth_thermal` dengan `flutter_blue_plus` — printer tidak akan
   terdeteksi sama sekali.

7. **`text_body` dipakai apa adanya.** Server sudah merender struk 32 kolom.
   Jangan menyusun format sendiri.

8. **Jangan hitung ulang HPP historis.** Laporan laba memakai snapshot biaya
   dari saat penjualan. Menggantinya dengan `menu_items.cost_price` yang
   sekarang akan membuat angka bulan lalu bergerak sendiri setiap harga modal
   diperbarui.

9. **Perubahan stok lewat `delta`, bukan menimpa `stock_qty`.** Dua orang yang
   menyesuaikan stok bersamaan dengan PATCH akan saling menghapus.

---

## Checklist sebelum dipakai di warung

Belum satu pun diverifikasi — butuh tablet + printer fisik.

- [ ] Cetak berhasil setelah tablet **restart** (pairing bertahan?)
- [ ] Cetak berhasil setelah printer **dimatikan lalu dinyalakan**
- [ ] Struk **tidak** tercetak dua kali saat aplikasi ditutup paksa di tengah cetak
- [ ] Kertas habis → job jadi `FAILED`, bukan hilang diam-diam
- [ ] Wi-Fi dimatikan saat verifikasi tunai → tidak ada "lunas palsu" di layar
- [ ] Dua order QRIS bersamaan → dua struk, tidak tertukar
- [ ] Tablet dicas semalaman → aplikasi masih jalan & printer masih tersambung
- [ ] Nama menu terpanjang tidak merusak lebar 32 kolom
- [ ] Order tunai: struk **baru** keluar setelah tombol verifikasi ditekan
- [ ] Order QRIS: struk keluar **otomatis** tanpa disentuh kasir

---

## Rujukan

Salin keempat berkas handoff ke [docs/](docs/) — lihat [docs/README.md](docs/README.md).

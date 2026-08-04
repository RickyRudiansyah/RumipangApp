# Rumipang Kasir — Aplikasi Kasir + Dashboard Admin

Aplikasi Android untuk **ADVAN Tab VX Lite** (10,4" · Android 13) yang
menggantikan dashboard kasir web, menjadi jembatan ke printer termal
**Panda PRJ-R58D** (58 mm, Bluetooth Classic/SPP), sekaligus dashboard admin:
HPP, stok bahan, laporan penjualan, jatah makan karyawan, dan tema event.

---

## ⚠️ Baca ini dulu — dua hal yang memblokir

### 1. Backend belum menerima `Authorization: Bearer`

API Next.js saat ini mengautentikasi staff lewat **cookie sesi**. Aplikasi ini
memegang **JWT**. Selama `BACKEND-PREREQ.md` belum dikerjakan di repo web,
**semua endpoint staff membalas 401** dan aplikasi tidak bisa apa-apa selain
menampilkan layar login.

Aplikasi ini sudah siap; yang kurang ada di sisi server.

Fitur dashboard admin menambah kebutuhan endpoint **baru** di atas itu —
seluruhnya terdaftar di [docs/BACKEND-ADDITIONS.md](docs/BACKEND-ADDITIONS.md).
Selama endpoint itu belum ada, layar Menu/Stok/Laporan/Jatah/Tema tetap terbuka
tapi menampilkan pesan error, dan aplikasi tetap bisa dipakai untuk kasir.

### 2. Service role key sempat tersebar

`SUPABASE_SERVICE_ROLE_KEY` mem-bypass seluruh RLS. Kunci itu dikirim lewat
percakapan biasa, jadi anggap sudah bocor: **rotasi di Supabase Dashboard →
Project Settings → API → Rotate**. Kunci itu tidak ada — dan tidak boleh ada —
di repo ini.

Yang tertanam di aplikasi hanya **anon key**, dan itu memang dirancang untuk
dipasang di klien (keamanannya dijaga RLS).

---

## Menjalankan

Flutter SDK belum terpasang di mesin ini. Setelah terpasang
([panduan resmi](https://docs.flutter.dev/get-started/install/windows)):

```powershell
# 1. Lengkapi scaffolding native (gradle wrapper, res/, MainActivity)
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1

# 2. Sambungkan tablet lewat USB (USB debugging aktif)
flutter devices

# 3. Jalankan
flutter run --release
```

`bootstrap.ps1` menjalankan `flutter create` untuk mengisi berkas native yang
tidak bisa dibuat tanpa SDK, lalu mengembalikan `pubspec.yaml`, `lib/`, dan
`AndroidManifest.xml` milik proyek ini, dan menyetel `minSdk 26` / `targetSdk 34`.

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
│   ├── admin/                   # menu & HPP: tambah menu, ubah harga, margin
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
| **Menu** | Tambah menu, ubah harga, isi HPP, margin per porsi dihitung otomatis. Menu yang dijual di bawah modal ditandai merah. |
| **Stok** | Bahan baku + alert saat menyentuh ambang (default 20, bisa beda per bahan). Perubahan stok lewat "Sesuaikan" beserta alasannya, tidak pernah menimpa angka langsung. |
| **Laporan** | Menu terlaris & kurang laku, omzet, total HPP, laba kotor. Rentang hari ini / 7 hari / 30 hari. |
| **Jatah** | Jatah makan karyawan, satu kali per orang per hari. |
| **Tema** | Tema event (Normal, Natal, Ramadan, Kemerdekaan, Imlek). Berlaku untuk aplikasi **dan** web. |

Tiga keputusan yang mudah dirusak tanpa sengaja:

- **Snapshot biaya, bukan referensi.** `order_items.cost_price_snapshot` dan
  `staff_meals.cost_snapshot` menyimpan HPP **saat transaksi terjadi**. Tanpa
  itu, menaikkan HPP hari ini akan mengubah laba bulan lalu.
- **Aturan 1x sehari ada di database,** lewat `unique (staff_id, meal_date)`.
  Pemeriksaan di aplikasi hanya untuk menonaktifkan tombol lebih awal — dua
  tablet bisa menekan bersamaan dan keduanya lolos.
- **Warna status tidak ikut tema.** Hijau lunas dan merah belum-bayar tetap
  sama di tema apa pun; tema Natal yang membuat semuanya merah akan
  menenggelamkan penanda belum-bayar.

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

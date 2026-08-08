# Rumipang Kasir — Aplikasi Kasir + Dashboard Admin

Aplikasi Android untuk **ADVAN Tab VX Lite** (10,4" · Android 13) yang
menggantikan dashboard kasir web, menjadi jembatan ke printer termal
**Panda PRJ-R58D** (58 mm, Bluetooth Classic/SPP), sekaligus dashboard admin:
HPP, stok bahan, laporan penjualan, jatah makan karyawan, dan tema event.

**Jalan di HP maupun tablet.** Tata letak menyesuaikan lebar layar; lihat
[Tata letak adaptif](#tata-letak-adaptif).

---

## Status: apa yang sudah jalan

### ✅ `Authorization: Bearer` sudah diterima backend

Dulu ini blocker nomor satu — API Next.js hanya mengenal cookie sesi sementara
aplikasi memegang JWT. **Sudah tidak lagi.** Terbukti pada 5 Agustus 2026:
mengubah harga menu (`PUT /api/menu/[id]`) dan mengunggah foto
(`POST /api/upload`) berhasil dari tablet, dan keduanya endpoint ber-auth staff.

Artinya sisa pekerjaan backend murni **"endpoint-nya belum dibuat"**, bukan
soal autentikasi.

### ✅ Endpoint Stok · Laporan · Jatah · Tema sudah dibuat

Dulu keempat layar ini menampilkan "Endpoint ini belum tersedia di server".
Rutenya sekarang **ada di repo web** — `app/api/ingredients`,
`app/api/reports/menu-sales`, `app/api/staff`, `app/api/staff-meals`, dan
`app/api/settings/theme`. Yang tersisa hanya urusan penerapan:

- **deploy ulang web-nya**, dan
- **jalankan migrasi SQL-nya** (`scripts/create-admin-features.sql`, lalu
  `scripts/staff-optional-email.sql` untuk kelola karyawan).

Kalau salah satu layar masih berkata "belum tersedia di server", curigai kedua
hal itu lebih dulu — bukan kodenya. Kontrak lengkapnya (DDL + contoh JSON) tetap
di [docs/BACKEND-ADDITIONS.md](docs/BACKEND-ADDITIONS.md).

Seluruh layar — Kasir, Order, Riwayat, Menu, Stok, Laporan, Jatah, Tema,
Printer — sudah punya endpoint pasangannya.

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

### ⚠️ Build saja belum sampai ke tablet

APK yang dipasang ke perangkat bukan `build/app/outputs/…`, melainkan artefak
bernama versi di `MobileApp/RumipangKasir-v<versi>.apk`. Melewatkan langkah
salin = memasang build kemarin dan menyangka perbaikannya tidak jalan. Ini
pernah terjadi.

1. Naikkan `version:` di [pubspec.yaml](pubspec.yaml) — **jangan** menimpa nama
   file versi lama dengan isi berbeda; nomor versi itulah satu-satunya cara
   membedakan APK yang sudah terpasang dari yang baru.
2. `flutter build apk --release`
3. Salin:
   ```powershell
   Copy-Item "RumipangApp\build\app\outputs\flutter-apk\app-release.apk" `
             "RumipangKasir-v1.6.0.apk"
   ```

Memastikan sebuah APK benar-benar berisi perubahan, tanpa memasangnya —
teks UI Dart ikut tertanam di `libapp.so`:

```bash
unzip -p RumipangKasir-v1.6.0.apk lib/arm64-v8a/libapp.so | grep -a -c "QRIS Lunas"
```

`0` berarti APK itu build lama.

> **Cari teks ASCII murni.** Karakter seperti `·` tidak tersimpan sebagai UTF-8
> polos di `libapp.so`, jadi mencari `"Selesai · Pindahkan"` selalu menjawab
> `0` walau kodenya jelas ada. Sudah pernah menyesatkan diagnosis.

### Riwayat versi

| Versi | Isi |
|---|---|
| 1.0.0 | Rilis awal |
| 1.1.0 | Warna opsi variasi (`OptionChip`), "Tanpa topping", cari + filter + muat ulang di POS, jatah karyawan tanpa HPP, hapus riwayat per periode, Take Away |
| 1.2.0 | Tombol "Selesai" kembali untuk order **tunai** (QRIS tetap otomatis) |
| 1.3.0 | Dua printer: stasiun Kasir & Dapur |
| 1.3.1 | **Perbaikan:** pemilih printer selalu kosong kalau ditekan saat pemindaian awal masih jalan |
| 1.4.0 | "Selesai" **per order** (bukan per meja), section **QRIS Lunas** |
| 1.5.0 | Riwayat: filter 1/7/30 hari + omzet · HPP hanya owner |
| 1.6.0 | Penyapu pembayaran QRIS yang tertinggal (~2 menit sekali) |

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
│   ├── local_store.dart         # MAC printer per stasiun, cache board, antrian aksi
│   ├── providers.dart           # dependency injection
│   └── realtime_service.dart    # websocket + polling cadangan 15 dtk
├── models/                      # ditulis tangan, tanpa build_runner
├── data/                        # repository per domain
├── features/
│   ├── auth/                    # login + guard role staff
│   ├── orders/                  # board kasir, QRIS Lunas, antrian aksi offline
│   ├── new_order/               # POS manual
│   ├── history/                 # riwayat + cetak ulang
│   ├── admin/                   # menu & HPP: kategori, harga, margin, foto
│   ├── inventory/               # stok bahan baku + alert ambang
│   ├── reports/                 # menu terlaris & kurang laku, laba kotor
│   ├── meals/                   # jatah makan karyawan (1x per orang per hari)
│   ├── settings/                # tema event, dipakai bersama web
│   ├── printer/                 # SPP 2 stasiun, loop klaim-cetak-ACK, foreground service
│   └── shell/                   # NavigationRail + siklus hidup layanan latar
└── shared/                      # tema, preset event, breakpoint, format, widget umum
```

Urutan tab: Kasir · Order · Riwayat · Menu · Stok · Laporan · Jatah · Tema ·
Printer. Sumber urutannya **satu tempat**: daftar `_pages` di
[shell_page.dart](lib/features/shell/shell_page.dart). Rail, bar bawah, lembar
"Lainnya", dan `_printerTabIndex` semuanya mengikuti indeks di situ — kalau
urutannya diubah, semua ikut.

---

## Tata letak adaptif

Aplikasi lahir untuk tablet landscape, lalu ditambah dukungan HP. Ambang layar
ada di [shared/layout.dart](lib/shared/layout.dart), mengikuti Material 3:

| Nama | Lebar | Perangkat |
|---|---|---|
| `compact` | < 600 | HP potret |
| `medium` | 600–999 | HP landscape, tablet kecil |
| `expanded` | ≥ 1000 | Tablet landscape (tata letak asli) |

Yang berubah di layar sempit:

| Bagian | Lebar | Sempit |
|---|---|---|
| Navigasi | NavigationRail 9 tab di kiri | NavigationBar 4 tab + lembar "Lainnya" |
| Board kasir | Master-detail berdampingan | Daftar meja; detail jadi halaman baru |
| Order (POS) | Grid + keranjang 400px | Grid penuh + keranjang di lembar bawah |
| Bilah atas POS | Cari + filter kategori + muat ulang | Sama; deretan kategori digulung mendatar |
| Daftar menu | Tabel 6 kolom | Dua baris; harga & margin tetap terlihat |
| Laporan | 4 kartu sebaris | 2×2, kartu peringkat bertumpuk |
| Dialog | Lebar tetap | `context.dialogWidth()` mengikuti layar |

### ⚠️ Master-detail diukur dari lebar nyata, bukan `ScreenSize`

**Jangan pakai `context.isCompact` untuk memutuskan pecah-kolom.** Tablet 10,4"
dalam potret lebarnya ±600dp — masih kategori `medium`, tapi setelah dipotong
panel meja 264px sisanya hanya ±335dp. Detail order tidak muat, dan tombol
berlabel panjang menghimpit teks sampai pecah satu huruf per baris. Ini pernah
terjadi.

Ambangnya ada di `SplitLayout` ([shared/layout.dart](lib/shared/layout.dart))
dan **selalu diukur lewat `LayoutBuilder`**:

| Konstanta | Nilai | Untuk |
|---|---|---|
| `cashierBoard` | 720 | panel meja + detail order |
| `posCart` | 760 | grid menu + keranjang |
| `printerPane` | 760 | panel printer + antrian cetak |
| `historyRow` | 860 | baris riwayat 6 kolom |
| `searchBar` | 640 | judul + kolom cari + tombol |
| `textWithAction` | 520 | teks penjelas + tombol panjang sebaris |

Aturan turunannya: **baris berisi beberapa chip status pakai `Wrap`, bukan
`Row`.** Chip pembayaran adalah hal terakhir yang boleh terpotong.

Orientasi **tidak lagi dikunci landscape**. Dulu dikunci karena tablet dipasang
mendatar di meja (SPEC §2); di layar 6" itu hanya membuat semuanya sempit tanpa
alasan.

Dua hal yang sengaja dipertahankan di HP karena penting: **indikator printer**
di kanan atas (versi ikon saja) dan **penanda belum-bayar**. Yang dikorbankan
lebih dulu saat ruang sempit adalah nama staff dan teks penjelasan.

---

## Keputusan teknis yang menyimpang dari SPEC

| Hal | SPEC | Di sini | Alasan |
|---|---|---|---|
| Model | freezed + json_serializable | ditulis tangan | Proyek compile tanpa langkah `build_runner`. Keamanan tipe sama, hanya boilerplate yang bertambah. |
| Alur dapur | layar dapur + ETA + mulai proses + sudah diantar | **dihapus** | Keputusan pemilik: order cukup masuk, tanpa langkah proses manual. Server menyetel `status = SERVED` saat order dibuat (BACKEND-ADDITIONS.md §7). |
| Pindah ke riwayat | tombol "Selesai" per meja | **QRIS otomatis, tunai tetap manual** | Keputusan pemilik. Uang QRIS sudah masuk sebelum ordernya lahir — tidak ada langkah tersisa. Di tunai masih ada uang dihitung & kembalian diberikan; hanya kasir yang tahu kapan itu selesai. Penyaringnya di server (`lib/archive.ts` di web). |
| Variasi menu | opsi pertama terpilih otomatis | hanya opsi **gratis** yang jadi default, plus chip "Tanpa …" | Topping berbayar yang terpilih diam-diam membuat harga dasar menu tidak pernah benar. |
| HPP | — | input manual per menu | Keputusan pemilik. Tanpa resep bahan baku, jadi **stok tidak berkurang otomatis** saat ada penjualan. |
| Pemilih meja di POS | dropdown | dialog daftar | `DropdownButtonFormField` berganti nama parameter antar versi Flutter; dialog juga lebih ramah untuk sentuhan. |
| Order tanpa meja | "Tanpa meja" | **"Take Away · Tanpa Meja"** (board & riwayat: "Take Away") | "Tanpa meja" terbaca seperti data meja yang belum diisi, bukan seperti jenis pesanan yang memang dipilih. |

---

## Dashboard admin

Lima layar tambahan, semuanya butuh endpoint di
[docs/BACKEND-ADDITIONS.md](docs/BACKEND-ADDITIONS.md).

| Layar | Isi |
|---|---|
| **Kasir** | Board per meja berisi **pekerjaan yang belum selesai** — praktisnya order tunai. Tombol **"Selesai" ada di tiap kartu order, bukan per meja**: satu meja bisa memesan beberapa kali semalam, dan menutup semuanya sekaligus ikut menelan order yang baru masuk. Baris **"QRIS Lunas"** di panel meja menampilkan order QRIS hari ini (jumlah + total) — **hanya-baca**, karena ordernya sudah lunas dan sudah di riwayat. |
| **Menu** | **HPP, margin, dan laba hanya terlihat oleh owner** (`canSeeCostProvider`) — kolomnya, chip-nya, peringatan "HPP belum diisi", judul layar, kolom input di dialog, sampai angka laba per menu di Laporan. Kasir melihat layar yang sama tanpa satu pun angka modal. Ini penjagaan **tampilan**, bukan keamanan: `cost_price` tetap ikut di respons `/api/menu`. Dikelompokkan per kategori. Tambah menu, kategori, dan topping/variasi berharga. Ubah harga, isi HPP, margin otomatis, foto menu (ambil → potong/putar → unggah). Menu yang dijual di bawah modal ditandai merah. |
| **Stok** | Bahan baku + alert saat menyentuh ambang (default 20, bisa beda per bahan). Perubahan stok lewat "Sesuaikan" beserta alasannya, tidak pernah menimpa angka langsung. |
| **Laporan** | Menu terlaris & kurang laku, omzet, dan — **khusus owner** — total HPP + laba kotor. Rentang hari ini / 7 hari / 30 hari. Jumlah kartunya berubah mengikuti peran, jadi tata letaknya **tidak boleh** memakai indeks tetap (`summaries[3]`) — itu crash begitu kartunya berkurang. |
| **Jatah** | Jatah makan karyawan: **satu menu per orang per hari, bebas menu apa pun**. Menunya wajib dipilih (ada kolom cari), dan HPP tidak ditampilkan di layar ini — "HPP belum diisi" di sebelah nama menu membuatnya terbaca seperti menu bermasalah yang tidak boleh diambil. **Owner** bisa menambah karyawan dan mengubah namanya; kasir tidak melihat tombol itu. |
| **Tema** | Tema event (Normal, Natal, Ramadan, Kemerdekaan, Imlek). Berlaku untuk aplikasi **dan** web. |
| **Printer** | **Dua stasiun: Kasir & Dapur**, masing-masing printer sendiri, struknya sama persis. Satu order = satu job per stasiun (kolom `print_jobs.station` di server). Tiap kartu punya tombol Hubungkan · Tes Cetak · Ganti · Lupakan. |
| **Riwayat** | Filter periode (Hari Ini · 7 Hari · 30 Hari · Semua) dengan **omzet** periode itu di atasnya. Omzet hanya menjumlahkan order **lunas & tidak dibatalkan** — menjumlahkan semua baris riwayat akan melaporkan uang yang tidak pernah diterima. Cari + cetak ulang struk, dan **hapus riwayat per hari / bulan / tahun** (atau semuanya). Jumlah order yang terdampak dihitung dari daftar yang sudah dimuat dan ditampilkan sebelum dikonfirmasi — penghapusannya permanen. |

Lima keputusan yang mudah dirusak tanpa sengaja:

- **Snapshot biaya, bukan referensi.** `order_items.cost_price_snapshot` dan
  `staff_meals.cost_snapshot` menyimpan HPP **saat transaksi terjadi**. Tanpa
  itu, menaikkan HPP hari ini akan mengubah laba bulan lalu.
- **Aturan 1x sehari ada di database,** lewat `unique (staff_id, meal_date)`.
  Pemeriksaan di aplikasi hanya untuk menonaktifkan tombol lebih awal — dua
  tablet bisa menekan bersamaan dan keduanya lolos.
- **Warna status tidak ikut tema.** Hijau lunas dan merah belum-bayar tetap
  sama di tema apa pun; tema Natal yang membuat semuanya merah akan
  menenggelamkan penanda belum-bayar.
- **Chip pilihan memakai `OptionChip`, bukan `ChoiceChip`.**
  ([shared/widgets.dart](lib/shared/widgets.dart)) Warna bawaan `ChoiceChip`
  diturunkan dari `ColorScheme.fromSeed`, dan seed itu ikut berganti setiap
  tema event diubah. Pada sebagian preset, label yang belum terpilih nyaris
  tidak terbaca — kasir harus menekan opsi satu per satu dulu untuk tahu
  isinya. Ini pernah terjadi pada daftar topping. `OptionChip` menuliskan
  warnanya sendiri, jadi tema event tidak bisa menyembunyikan teks pilihan.
- **`PUT /api/menu/[id]` mengganti seluruh baris.** Setiap field yang boleh
  disunting **wajib** ikut dikirim, termasuk `image_url` dan `category_id` yang
  tidak berubah. Parameternya sengaja `required` di
  [menu_admin_repository.dart](lib/data/menu_admin_repository.dart) supaya
  kelalaian ini gagal saat compile, bukan menghapus foto menu diam-diam di
  server. Ini pernah terjadi.

### Status endpoint

Seluruh layar sudah punya endpoint pasangannya di repo web — lihat
[Status](#-endpoint-stok--laporan--jatah--tema-sudah-dibuat) di atas untuk dua
hal yang masih bisa membuatnya tampak 404 (belum di-deploy / migrasi SQL belum
dijalankan).

Khusus **Jatah**, tombol "Tambah Karyawan" dan "Ubah Karyawan" dulu selalu gagal
diam-diam: `POST /api/staff` membalas 405 dan `PATCH /api/staff/[id]` membalas
404. Keduanya sudah dibuat, **owner-only ditegakkan di server**, dan butuh
migrasi `scripts/staff-optional-email.sql` supaya karyawan tanpa email bisa
disimpan.

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

   `isSettled` juga dipakai
   [orders_provider.dart](lib/features/orders/orders_provider.dart) untuk
   menyapu order **QRIS** lunas yang masih tampil di board (arsip di server
   sempat gagal, atau baris lama). Dua batasnya jangan dilepas: **hanya QRIS**
   — menyapu order tunai sama saja menekan "Selesai" tanpa sepengetahuan kasir
   — dan **sengaja satu putaran saja**, supaya board tidak berputar tanpa henti
   kalau `archive` selalu gagal.

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

   Paket itu juga memegang **satu socket global**, bukan objek per-koneksi.
   Dua printer karena itu dilayani bergantian, dan **`PrinterController.useStation()`
   adalah satu-satunya pintu untuk berpindah** — memanggil
   `PrinterService.connect()` langsung akan meninggalkan slot lain berstatus
   "Terhubung" padahal socketnya sudah direbut, dan struk dapur keluar di
   printer kasir.

7. **`text_body` dipakai apa adanya.** Server sudah merender struk 32 kolom.
   Jangan menyusun format sendiri.

8. **Jangan hitung ulang HPP historis.** Laporan laba memakai snapshot biaya
   dari saat penjualan. Menggantinya dengan `menu_items.cost_price` yang
   sekarang akan membuat angka bulan lalu bergerak sendiri setiap harga modal
   diperbarui.

9. **Loop cetak juga menyapu pembayaran QRIS yang tertinggal.** Tiap ~2 menit
   `print_queue.dart` memanggil `POST /api/payments/reconcile`. Terlihat tidak
   nyambung dengan mencetak, dan memang - tapi loop itulah satu-satunya yang
   benar-benar berjalan sepanjang hari (foreground service, tablet selalu
   menyala di kasir). Server tidak punya penjadwal, dan webhook Midtrans
   terbukti bisa tidak sampai: pernah dua pelanggan membayar Rp 107.000 dan
   ordernya tidak pernah dibuat. **Jangan hapus pemanggilan itu hanya karena ia
   tidak ada urusannya dengan printer.**

10. **Perubahan stok lewat `delta`, bukan menimpa `stock_qty`.** Dua orang yang
   menyesuaikan stok bersamaan dengan PATCH akan saling menghapus.

11. **Katalog tidak menyegarkan dirinya sendiri.** `menuProvider`,
    `menuVariationsProvider`, `menuCategoriesProvider`, dan `tablesProvider`
    adalah `FutureProvider` yang menyimpan hasil pertamanya — menu yang
    ditambahkan dari dashboard web (atau dari tablet lain) tidak akan pernah
    muncul di layar Order sampai keempatnya di-invalidate. Itulah gunanya
    `refreshCatalog()` di
    [catalog_provider.dart](lib/features/new_order/catalog_provider.dart) dan
    tombol muat ulang di bilah atas POS. Menambah sumber katalog baru? Ikutkan
    di fungsi itu juga, kalau tidak ia akan basi diam-diam.

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

### Khusus dua printer (kasir + dapur)

Satu socket SPP dipakai bergantian, jadi yang perlu diuji justru **perpindahannya**:

- [ ] Satu order → **dua struk**, satu di tiap printer, isinya sama persis
- [ ] Printer dapur **dimatikan** → struk kasir tetap keluar, dan job dapur
      menunggu (bukan menggagalkan keduanya)
- [ ] Printer dapur dinyalakan lagi → struk yang tertunda menyusul sendiri
- [ ] Antrian ramai (5+ order) → tidak ada struk yang tercetak **dua kali** di
      printer yang sama saat aplikasi berpindah-pindah
- [ ] Aplikasi ditutup paksa tepat saat berpindah printer → setelah dibuka lagi,
      job yang belum di-ACK tercetak **sekali**, bukan dua kali
- [ ] Layar Printer: hanya **satu** kartu bertanda "memegang koneksi"

### Khusus pembayaran QRIS

Yang diuji di sini bukan jalur normalnya, tapi **jalur gagalnya** — di situlah
uang pernah hilang:

- [ ] Bayar QRIS lalu **tutup tab** sebelum kembali ke aplikasi → ordernya tetap
      muncul (paling lama ~2 menit, lewat penyapu di app)
- [ ] Bayar QRIS lalu **matikan data HP** tepat setelah bayar → sama, tetap masuk
- [ ] Order QRIS **tidak** muncul di board kasir, tapi ada di "QRIS Lunas" dan
      Riwayat, dan ikut terhitung di omzet
- [ ] Setelah bayar, pelanggan **tidak** terlempar ke halaman kosong
      (`NEXT_PUBLIC_APP_URL` sudah domain publik)

---

## Rujukan

Salin keempat berkas handoff ke [docs/](docs/) — lihat [docs/README.md](docs/README.md).

# Yang perlu ditambahkan di repo web + Supabase

Dokumen ini untuk **agent yang mengurus repo web (Next.js) dan Supabase**.
Aplikasi kasir Flutter sudah ditulis terhadap kontrak di bawah ini; selama
endpoint-endpoint ini belum ada, layar-layar baru akan tampil kosong atau
menampilkan pesan error.

Aturan yang tidak berubah: **aplikasi tidak pernah menulis ke tabel Supabase
langsung.** Semua perubahan lewat REST API supaya logika bisnis tetap satu
tempat. Supabase SDK di aplikasi hanya untuk login dan realtime.

---

## 0. Prasyarat auth — ✅ SUDAH SELESAI

`Authorization: Bearer <JWT>` **sudah diterima backend.** Terbukti 5 Agustus
2026: `PUT /api/menu/[id]` dan `POST /api/upload` — keduanya ber-auth staff —
berhasil dipanggil dari tablet.

Jadi seluruh pekerjaan di dokumen ini murni soal **membuat endpoint yang belum
ada**, bukan lagi soal autentikasi. Setiap endpoint baru cukup memakai
`requireAuth` yang sama seperti endpoint staff lain; tidak ada perlakuan khusus
untuk aplikasi Flutter.

> Aplikasi mengirim header itu di setiap request
> ([api_client.dart](../lib/core/api_client.dart), fungsi `_headers`), termasuk
> pada unggah multipart.

---

## 1. HPP per menu

**Keputusan pemilik:** HPP diisi manual per menu, **bukan** dihitung dari resep
bahan baku. Konsekuensinya stok bahan tidak berkurang otomatis saat ada
penjualan (lihat §4).

### Perubahan tabel `menu_items`

```sql
alter table menu_items
  add column cost_price integer not null default 0;

comment on column menu_items.cost_price is
  'HPP per porsi dalam rupiah, diisi manual oleh owner. 0 = belum diisi.';
```

### Perubahan tabel `order_items` — PENTING

```sql
alter table order_items
  add column cost_price_snapshot integer not null default 0;
```

Isi kolom ini dengan `menu_items.cost_price` **pada saat order dibuat**, sama
seperti `menu_item_price` yang sudah disimpan sebagai snapshot.

Alasannya: tanpa snapshot, menaikkan HPP hari ini akan mengubah laba bulan lalu.
Laporan jadi tidak bisa dipercaya dan angka historis bergerak sendiri. Ini
kesalahan yang mahal untuk diperbaiki belakangan karena data lamanya sudah
hilang.

---

## 2. Menu bisa ditambah & harga bisa diubah

**Hampir semuanya sudah ada di web.** Endpoint berikut tidak perlu dibuat baru:

| Endpoint | Status |
|---|---|
| `GET /api/menu` | ✅ sudah ada |
| `POST /api/menu` | ✅ sudah ada |
| `PUT /api/menu/[id]` | ✅ sudah ada |
| `DELETE /api/menu/[id]` | ✅ sudah ada |
| `PATCH /api/menu/[id]/sold-out` | ✅ sudah ada |

Yang perlu dikerjakan hanya **menambahkan `cost_price`** ke:

1. **Respons `GET /api/menu`** — kalau tidak ada, aplikasi membacanya sebagai 0
   dan seluruh kolom HPP tampil "belum diisi".
2. **Payload `POST /api/menu`** — nilai awal saat menu dibuat.
3. **Payload `PUT /api/menu/[id]`** — supaya HPP bisa diubah.

```jsonc
// POST /api/menu  &  PUT /api/menu/[id]
{
  "name": "Roti Coklat",
  "price": 15000,
  "cost_price": 6000,        // <-- satu-satunya yang baru
  "category_id": "uuid-atau-null",
  "description": "",
  "is_available": true
}
```

Aplikasi Flutter memanggil **`PUT`** untuk update menu, mengikuti web — bukan
`PATCH` seperti endpoint order. `is_sold_out` dikirim terpisah lewat
`PATCH /api/menu/[id]/sold-out`, juga mengikuti web.

**Validasi yang diharapkan:** `price >= 0`, `cost_price >= 0`. Kalau
`cost_price > price`, **tetap terima** — margin negatif itu keputusan bisnis
(menu promo), bukan error teknis. Aplikasi sudah menandainya merah sendiri.

Soal `DELETE`: web menghapus baris sungguhan, dan itu aman karena `order_items`
menyimpan `menu_item_name` + `menu_item_price` sebagai snapshot. Tidak perlu
diubah jadi soft delete. (Tabel `menu_items` tidak punya kolom `is_active` —
yang ada `is_available` dan `is_sold_out`.)

### ⚠️ `PUT` harus mempertahankan `image_url`

Aplikasi sekarang mengirim **seluruh** field pada `PUT`, termasuk `image_url`
dan `category_id` yang tidak diubah. Pastikan handler web:

1. **Menyimpan `cost_price`** — kalau field ini diabaikan diam-diam, HPP akan
   selalu kembali ke 0 setiap kali menu disunting dan owner tidak akan tahu
   kenapa.
2. **Menyimpan `image_url` apa adanya** — termasuk saat nilainya `null`
   (owner menghapus foto). Jangan "melindungi" foto lama dengan mengabaikan
   `null`, karena tombol Hapus Foto jadi tidak berfungsi.

Kalau `PUT` sekarang menolak payload yang memuat field tak dikenal seperti
`cost_price`, **itu penyebab "harga tidak ter-update"** — seluruh request
ditolak, bukan hanya field barunya.

### Foto menu: `POST /api/upload`

Endpoint ini **sudah ada** di web (staff, ≤5 MB). Aplikasi memakainya untuk
foto menu: ambil dari galeri/kamera → potong & putar di tablet → unggah →
URL hasilnya dikirim sebagai `image_url` lewat `POST`/`PUT /api/menu`.

Yang perlu dipastikan hanya **bentuk responsnya**. Aplikasi menerima salah satu
dari ini:

```jsonc
"https://...supabase.co/storage/v1/object/public/menu-images/foo.jpg"
{ "url": "https://..." }
{ "image_url": "https://..." }
{ "publicUrl": "https://..." }
{ "data": { "url": "https://..." } }
```

Kalau bentuknya di luar daftar itu, aplikasi menampilkan "Server tidak
mengembalikan URL foto yang bisa dibaca" — beri tahu bentuk aslinya dan sisi
Flutter yang menyesuaikan.

Field multipart-nya bernama **`file`**, tipe `image/jpeg`. Aplikasi sudah
memampatkan ke maksimal 1200×1200 kualitas 85, jadi jauh di bawah batas 5 MB.

---

## 2b. Tambah kategori dari aplikasi

Aplikasi mengelompokkan menu per kategori dan bisa menambah kategori baru.
`GET /api/menu/categories` sudah ada; **`POST`-nya belum.**

### `POST /api/menu/categories`

```jsonc
// request
{ "name": "Minuman", "sort_order": 4 }

// response 201
{ "id": "uuid", "name": "Minuman", "sort_order": 4 }
```

`sort_order` menentukan urutan tampil kategori di aplikasi **dan** di web.
Aplikasi mengisinya sendiri dengan `max(sort_order) + 1`, jadi kategori baru
selalu masuk paling belakang.

Duplikat nama sudah dicegah di aplikasi, tapi **tambahkan juga unique index**
di database — dua tablet bisa menambah nama yang sama bersamaan:

```sql
create unique index if not exists categories_name_unique
  on categories (lower(name));
```

Balas **409** dengan `{"error": "Kategori ini sudah ada"}` saat dilanggar;
aplikasi menampilkan pesannya apa adanya.

Mengubah nama, mengatur ulang urutan, dan menghapus kategori sengaja **tidak**
dibuat di aplikasi — itu pekerjaan sesekali yang lebih nyaman lewat web.

---

## 3. Laporan menu terlaris & kurang laku

### `GET /api/reports/menu-sales?from=<ISO8601>&to=<ISO8601>`

```jsonc
// response 200
{
  "from": "2026-07-01T00:00:00Z",
  "to": "2026-07-31T23:59:59Z",
  "items": [
    {
      "menu_item_id": "uuid",
      "menu_item_name": "Es Kopi Susu",
      "qty_sold": 412,
      "revenue": 6180000,        // jumlah subtotal
      "cost": 2472000,           // jumlah cost_price_snapshot * quantity
      "gross_profit": 3708000    // revenue - cost
    }
  ]
}
```

Hitung **hanya dari order yang `payment_status = 'PAID'` dan
`status != 'CANCELLED'`**. Order batal atau belum bayar tidak boleh masuk
laporan penjualan.

Urutan tidak perlu diatur server — aplikasi menyortir sendiri untuk menampilkan
"terlaris" dan "kurang laku" dari daftar yang sama.

Menu yang **tidak pernah terjual** dalam rentang itu sebaiknya tetap muncul
dengan `qty_sold: 0`. Justru menu inilah yang paling ingin dilihat owner di
daftar "kurang laku" — kalau dihilangkan, menu mati jadi tak terlihat.

> **Sudah ada yang mirip di web.** Owner dashboard punya "Top menu terlaris" dan
> "Rekap penjualan (Hari Ini / 7 Hari / Semua)". Kalau logikanya sekarang
> dihitung di dalam halaman, pindahkan ke endpoint ini lalu halaman owner ikut
> memakainya — supaya angka di web dan di tablet tidak pernah berbeda. Dua
> tambahan dibanding versi web sekarang: kolom `cost`/`gross_profit`, dan menu
> ber-`qty_sold: 0` yang justru sengaja ditampilkan.

---

## 4. Stok bahan baku + alert

**Catatan penting:** karena HPP diisi manual dan tidak ada resep, **server tidak
bisa mengurangi stok otomatis saat ada penjualan.** Sistem tidak tahu satu roti
coklat menghabiskan berapa gram tepung. Semua perubahan stok adalah input
manual dari aplikasi.

### Tabel baru `ingredients`

```sql
create table ingredients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  unit text not null default 'pcs',        -- 'kg', 'gram', 'liter', 'pcs', ...
  stock_qty numeric not null default 0,
  alert_threshold numeric not null default 20,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

`alert_threshold` default 20 sesuai permintaan, tapi dibuat per bahan supaya
bisa beda — 20 kg tepung dan 20 pcs kemasan bukan tingkat urgensi yang sama.

### Tabel baru `stock_movements` (jejak audit)

```sql
create table stock_movements (
  id uuid primary key default gen_random_uuid(),
  ingredient_id uuid not null references ingredients(id) on delete cascade,
  delta numeric not null,                  -- positif = masuk, negatif = pakai
  reason text not null,                    -- 'PURCHASE' | 'USAGE' | 'WASTE' | 'CORRECTION'
  note text,
  actor_email text,
  created_at timestamptz not null default now()
);
```

Tanpa tabel ini, stok cuma satu angka yang berubah tanpa jejak dan selisih
tidak akan pernah bisa ditelusuri.

### Endpoint

| Method | Path | Isi |
|---|---|---|
| `GET` | `/api/ingredients` | daftar bahan aktif + `stock_qty`, `alert_threshold` |
| `POST` | `/api/ingredients` | `{name, unit, stock_qty, alert_threshold}` |
| `PATCH` | `/api/ingredients/:id` | partial: `name`, `unit`, `alert_threshold`, `is_active` |
| `POST` | `/api/ingredients/:id/movements` | `{delta, reason, note}` → server update `stock_qty` **dan** catat movement dalam satu transaksi |

Perubahan stok **wajib** lewat `/movements`, bukan `PATCH stock_qty` langsung.
Dua kasir yang menyesuaikan stok bersamaan dengan `PATCH` akan saling menimpa;
dengan `delta` keduanya terakumulasi benar.

---

## 5. Jatah makan karyawan

**Aturan:** 3 karyawan, masing-masing berhak **1 kali makan per hari**.

### Tabel baru `staff_meals`

```sql
create table staff_meals (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references staff_users(id),
  meal_date date not null default current_date,
  menu_item_id uuid references menu_items(id),
  cost_snapshot integer not null default 0,   -- cost_price saat dicatat
  note text,
  created_at timestamptz not null default now(),
  unique (staff_id, meal_date)                -- inilah yang menegakkan 1x/hari
);
```

Constraint `unique (staff_id, meal_date)` adalah tempat aturan "1 kali sehari"
ditegakkan. Jangan andalkan pengecekan di aplikasi saja — dua tablet bisa
mencatat bersamaan dan keduanya lolos.

Saat constraint dilanggar, balas **409 Conflict** dengan
`{"error": "Karyawan ini sudah mengambil jatah makan hari ini"}`. Aplikasi
menampilkan pesan itu apa adanya.

`cost_snapshot` diisi dari `menu_items.cost_price` saat pencatatan — alasannya
sama dengan §1: biaya jatah makan bulan lalu tidak boleh berubah saat HPP
diperbarui.

### Endpoint

| Method | Path | Isi |
|---|---|---|
| `GET` | `/api/staff-meals?date=YYYY-MM-DD` | jatah makan pada tanggal itu |
| `GET` | `/api/staff-meals?from=&to=` | rekap rentang, untuk laporan biaya |
| `POST` | `/api/staff-meals` | `{staff_id, menu_item_id?, note?}` — `meal_date` = hari ini di server |
| `DELETE` | `/api/staff-meals/:id` | koreksi salah input |

Juga dibutuhkan **`GET /api/staff`** (daftar karyawan aktif: `id`, `name`,
`email`, `role`) supaya aplikasi bisa menampilkan tiga nama untuk dipilih.
Endpoint ini **belum ada** — tabelnya (`staff_users`) sudah, tapi tidak pernah
diekspos lewat API. Cukup `select id, name, email, role from staff_users where
is_active = true`.

---

## 6. Tema event (aplikasi **dan** web ikut berubah)

Owner memilih tema dari aplikasi kasir; web membaca nilai yang sama.

### Tabel baru `app_settings`

```sql
create table app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by text
);

insert into app_settings (key, value)
values ('theme', '{"preset":"NORMAL"}');
```

Bentuk key-value dipilih supaya pengaturan berikutnya (jam buka, pesan promo)
tidak perlu migrasi tabel lagi.

### Endpoint

| Method | Path | Isi |
|---|---|---|
| `GET` | `/api/settings/theme` | `{"preset": "NATAL"}` |
| `PATCH` | `/api/settings/theme` | `{"preset": "NATAL"}` → balas objek terbaru |

`PATCH`, bukan `PUT` — klien REST di aplikasi hanya mengenal GET/POST/PATCH/DELETE
([api_client.dart:41-50](../lib/core/api_client.dart#L41-L50)), dan menambah verb
baru hanya untuk satu endpoint tidak sepadan.

`GET` harus **boleh diakses publik** (tanpa login) — web pengunjung perlu
membacanya juga. `PATCH` khusus role owner/admin.

### Nilai preset yang disepakati

| `preset` | Nama tampil | Warna utama |
|---|---|---|
| `NORMAL` | Normal | `#7B3F00` cokelat kopi (warna asli) |
| `NATAL` | Natal | `#C62828` merah + `#1B7F4B` hijau |
| `RAMADAN` | Ramadan | `#00695C` hijau tosca + emas |
| `KEMERDEKAAN` | Kemerdekaan | `#C62828` merah + putih |
| `IMLEK` | Imlek | `#B71C1C` merah + `#D4AF37` emas |

Daftar ini dipakai identik di aplikasi ([shared/app_theme_preset.dart](../lib/shared/app_theme_preset.dart))
dan harus dipakai identik di web. Kalau web menambah preset baru, aplikasi akan
jatuh ke `NORMAL` — tidak error, tapi temanya tidak ikut berubah sampai
aplikasi diperbarui.

Realtime opsional: kalau `app_settings` ikut dipublikasikan lewat Supabase
realtime, tema berubah di semua perangkat tanpa perlu muat ulang.

### Hubungannya dengan dark mode yang sudah ada

Web sudah punya dark mode (`ThemeContext` + `localStorage` + Tailwind v4
`@theme`). **Keduanya sumbu yang berbeda dan tidak boleh saling menimpa:**

- **Dark/light** = preferensi tiap pengunjung, disimpan di perangkat masing-masing
- **Preset event** = keputusan toko, disimpan di server, sama untuk semua orang

Jadi tema Natal harus tetap punya versi terang dan gelap. Cara paling rapi:
preset hanya mengganti nilai warna *brand/primary* di `@theme`, sementara
token light/dark tetap seperti sekarang. Jangan menjadikan preset event sebagai
tema ketiga yang menggantikan keduanya.

---

## 7. Alur dapur dipensiunkan — di aplikasi **dan** di web

**Keputusan pemilik:** dapur tidak dipakai lagi. Order cukup masuk lalu
dibayar. Ini bukan hanya perubahan di aplikasi Flutter — Kitchen Display di web
ikut dipensiunkan.

### Yang harus dilakukan server

**Set `status = 'SERVED'` saat order dibuat**, bukan `QUEUED`. Berlaku untuk
ketiga jalur pembuatan order:

- `POST /api/orders` (Cash dari customer)
- `settleIntent()` (QRIS Mayar, order dibuat setelah lunas)
- Manual order / POS dari kasir

Alasannya, aturan pengarsipan mensyaratkan order berstatus `SERVED` **dan**
lunas sebelum boleh diarsipkan ([order.dart](../lib/models/order.dart)
`isSettled`) — sama persis dengan tombol "Selesai" di board kasir web. Kalau
order berhenti di `QUEUED` selamanya, order lunas tidak akan pernah bisa
diarsipkan dan board kasir menumpuk tanpa batas.

### Yang bisa dipensiunkan di web

| Bagian | Tindakan |
|---|---|
| `/dashboard/kitchen` | Tidak dipakai lagi |
| Role `koki` di `staff_users` | Tidak dipakai lagi; **jangan hapus constraint-nya** agar baris lama tetap valid |
| `PATCH /api/orders/[id]/status` | Boleh tetap hidup, tidak dipanggil siapa pun |
| `PATCH /api/orders/[id]/update-eta` | Sama |
| `GET /api/orders` (mode dapur) | Sama — board kasir memakai `?mode=cashier` |
| Kolom `estimated_ready_at`, `confirmed_at` | Biarkan; data historis, tidak diisi lagi |

Endpoint sengaja **tidak** disuruh dihapus. Menghapusnya tidak menambah apa pun
selain risiko, dan kalau suatu saat dapur dipakai lagi tinggal dinyalakan.

> Catatan: README aplikasi Flutter sempat menyebut "role `koki` sudah dihapus di
> backend". Itu **tidak benar** — role dan layarnya masih ada di web sampai
> perubahan ini dikerjakan.

---

## 8. Ringkasan RLS

Tabel baru semuanya berisi data operasional toko, bukan data pelanggan:

- `ingredients`, `stock_movements`, `staff_meals` → hanya role staff/owner.
  Tidak ada alasan pengunjung web membacanya.
- `app_settings` → **baca publik**, tulis khusus owner. Web pengunjung perlu
  membaca tema.

Karena semua akses dari aplikasi lewat REST API dengan JWT staff, RLS berperan
sebagai lapisan pertahanan kedua, bukan yang pertama.

---

## Urutan pengerjaan yang disarankan

| # | Pekerjaan | Ukuran |
|---|---|---|
| ~~0~~ | ~~Bearer auth~~ | ✅ selesai |
| 1 | Kolom `cost_price` + `cost_price_snapshot` | kecil |
| 2 | `cost_price` masuk ke `GET/POST /api/menu` + `PUT /api/menu/[id]` | kecil |
| 3 | `POST /api/menu/categories` (§2b) | kecil |
| 4 | `status = 'SERVED'` saat order dibuat (§7) | kecil |
| 5 | `app_settings` + `GET/PATCH /api/settings/theme` | kecil |
| 6 | `ingredients` + `stock_movements` + 4 endpoint | sedang |
| 7 | `staff_meals` + `GET /api/staff` | sedang |
| 8 | `GET /api/reports/menu-sales` | sedang |

Nomor 1 sengaja ditaruh paling awal meski fiturnya belum dipakai: **setiap hari
kolom itu belum ada adalah satu hari data laba yang hilang permanen.** Angka
bulan lalu tidak bisa direkonstruksi kalau snapshot-nya tidak pernah ditulis.

Nomor 1–5 semuanya kecil dan bisa selesai dalam satu sesi. Setelah itu layar
Menu berfungsi penuh dan tema sudah bisa dipakai — sisanya fitur tambahan yang
bisa menyusul.

---

## Ringkasan: apa yang sudah ada vs benar-benar baru

| | Sudah ada di web | Perlu dibuat |
|---|---|---|
| **Menu** | POST, PUT, DELETE, sold-out, GET | kolom `cost_price`; `image_url` harus tersimpan lewat PUT |
| **Kategori** | `GET /api/menu/categories` | `POST /api/menu/categories` + unique index |
| **Foto** | `POST /api/upload` | pastikan bentuk respons terbaca (§2) |
| **Order** | seluruh alur | `status='SERVED'` saat dibuat |
| **Laporan** | top menu di halaman owner | endpoint + kolom biaya |
| **Staff** | tabel `staff_users` | `GET /api/staff` |
| **Tema** | dark mode (per perangkat) | `app_settings` + 2 endpoint |
| **Stok bahan** | — | tabel + 4 endpoint |
| **Jatah makan** | — | tabel + 4 endpoint |
| **Activity log** | sudah dipakai aplikasi | — |
